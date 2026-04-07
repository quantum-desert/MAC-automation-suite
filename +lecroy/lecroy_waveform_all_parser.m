

function out = lecroy_waveform_all_parser(io, chan, varargin)
%LECROY_WAVEFORM_ALL_PARSER Setup, acquire, and parse a LeCroy WF? ALL transfer.
%
%   out = lecroy_waveform_all_parser(io)
%   out = lecroy_waveform_all_parser(io, "C1")
%   out = lecroy_waveform_all_parser(io, "C1", 'AcquireSingle', true)
%
% One-file utility for MATLAB visadev objects. It:
%   1) configures LeCroy waveform transfer for robust binary readout,
%   2) optionally triggers a SINGLE acquisition and waits for completion,
%   3) reads the entire WF? ALL reply as one IEEE-488.2 block,
%   4) parses the LeCroy WAVEDESC metadata and DAT1 waveform,
%   5) returns a struct with volts, time axis, raw bytes, and metadata.
%
% This file is intentionally self-contained. All helpers are local
% functions below.
%
% IMPORTANT
%   - This is written for analog traces (C1..Cn) and DAT1 parsing.
%   - It prefers little-endian WORD/BIN transfer for Intel hosts.
%   - For >2 GB traces or uncommon descriptor variants, the parser may
%     need extension.
%
% Name-value options:
%   'AcquireSingle'      : false (default) | true
%   'TimeoutSeconds'     : [] (auto) or scalar seconds
%   'SampleRateGuessBps' : 5e6 default, used for timeout estimate only
%   'Verbose'            : true default
%   'StopBeforeSetup'    : true default
%   'CommHeader'         : "SHORT" default
%   'CommFormat'         : "DEF9,WORD,BIN" default
%   'CommOrder'          : "LO" default
%   'WaveformSetup'      : "SP,1,NP,0,FP,0,SN,0" default
%   'ReadTimeScaleFromDescriptor' : true default
%   'FallbackInspectTimeScale'    : false default
%
% Example:
%   io = visadev("USB0::0x05FF::0x1023::4609N02990::0::INSTR");
%   out = lecroy_waveform_all_parser(io, "C1", 'AcquireSingle', true);
%   plot(out.t, out.volts);
%
% Notes grounded in the uploaded Teledyne LeCroy manual:
%   - WF? ALL transfers all logical waveform entities in one arbitrary data block.
%   - The returned format depends on WAVEFORM_SETUP, COMM_ORDER, and COMM_FORMAT.
%   - For Intel-based hosts, CORD LO is recommended.
%
% Copyright: generated for the user request.

    if nargin < 2 || isempty(chan)
        chan = "C1";
    end
    chan = string(chan);

    p = inputParser;
    addParameter(p, 'AcquireSingle', false, @(x)islogical(x) || isnumeric(x));
    addParameter(p, 'TimeoutSeconds', [], @(x) isempty(x) || (isscalar(x) && x > 0));
    addParameter(p, 'SampleRateGuessBps', 5e6, @(x) isscalar(x) && x > 0);
    addParameter(p, 'Verbose', true, @(x)islogical(x) || isnumeric(x));
    addParameter(p, 'StopBeforeSetup', true, @(x)islogical(x) || isnumeric(x));
    addParameter(p, 'CommHeader', "SHORT", @(x)isstring(x) || ischar(x));
    addParameter(p, 'CommFormat', "DEF9,WORD,BIN", @(x)isstring(x) || ischar(x));
    addParameter(p, 'CommOrder', "LO", @(x)isstring(x) || ischar(x));
    addParameter(p, 'WaveformSetup', "SP,1,NP,0,FP,0,SN,0", @(x)isstring(x) || ischar(x));
    addParameter(p, 'ReadTimeScaleFromDescriptor', true, @(x)islogical(x) || isnumeric(x));
    addParameter(p, 'FallbackInspectTimeScale', false, @(x)islogical(x) || isnumeric(x));
    parse(p, varargin{:});
    opt = p.Results;

    validateattributes(io, {'visalib.USB'}, {}, mfilename, 'io', 1);

    configureTerminator(io, "LF");

    if opt.StopBeforeSetup
        tryWriteLine(io, "STOP");
    end

    setupTransfer(io, opt, opt.Verbose);

    if opt.AcquireSingle
        acquireSingle(io, opt.Verbose);
    end

    if isempty(opt.TimeoutSeconds)
        % Conservative default before we know record size.
        io.Timeout = 30;
    else
        io.Timeout = opt.TimeoutSeconds;
    end

    flush(io);
    cmd = sprintf('%s:WF? ALL', chan);
    if opt.Verbose
        fprintf('Sending %s\n', cmd);
    end
    writeline(io, cmd);

    [payload, blockInfo] = readIEEE4882Block(io);

    % Now that we know actual block size, extend timeout heuristically for future use.
    estTimeout = estimateTimeoutSeconds(numel(payload), opt.SampleRateGuessBps);
    out = parseLeCroyWFAllPayload(payload);
    out.block = blockInfo;
    out.block.payloadBytes = numel(payload);
    out.recommendedTimeoutSeconds = estTimeout;

    if opt.ReadTimeScaleFromDescriptor && isfield(out, 'horizInterval') && isfield(out, 'horizOffset') ...
            && ~isempty(out.horizInterval) && ~isempty(out.horizOffset)
        out.t = out.horizOffset + (0:numel(out.volts)-1).' .* out.horizInterval;
        out.timeSource = "descriptor";
    elseif opt.FallbackInspectTimeScale
        [dt, t0] = queryTimeScaleInspect(io, chan);
        out.t = t0 + (0:numel(out.volts)-1).' .* dt;
        out.horizInterval = dt;
        out.horizOffset = t0;
        out.timeSource = "inspect";
    else
        out.t = [];
        out.timeSource = "unavailable";
    end

    out.channel = chan;
    out.visadevResource = string(io.ResourceName);
end

function setupTransfer(io, opt, verbose)
    flush(io);
    if verbose, fprintf('Configuring waveform transfer...\n'); end
    tryWriteLine(io, sprintf('CHDR %s', string(opt.CommHeader)));
    tryWriteLine(io, sprintf('CFMT %s', string(opt.CommFormat)));
    tryWriteLine(io, sprintf('CORD %s', string(opt.CommOrder)));
    tryWriteLine(io, sprintf('WFSU %s', string(opt.WaveformSetup)));
end

function acquireSingle(io, verbose)
    if verbose, fprintf('Arming SINGLE acquisition...\n'); end
    tryWriteLine(io, 'TRMD SINGLE');
    % Use *OPC? to wait until previous operations complete.
    writeline(io, '*OPC?');
    try
        ack = strtrim(readline(io));
        if verbose
            fprintf('*OPC? -> %s\n', ack);
        end
    catch ME
        warning(ME.iodentifier,'Could not complete *OPC? wait: %s', ME.message);
    end
end

function [payload, info] = readIEEE4882Block(io)
% Reads an arbitrary IEEE-488.2 block, tolerating a short ASCII prefix such as C1:.
%
% Expected framing:
%   [optional ASCII prefix] # <N> <N decimal digits giving payload length> <payload>

    prefix = uint8([]);
    while true
        b = read(io, 1, 'uint8');
        prefix(end+1,1) = b; %#ok<AGROW>
        if b == uint8('#')
            break
        end
    end

    nDigitsChar = char(read(io, 1, 'char'));
    nDigits = str2double(nDigitsChar);
    if ~isscalar(nDigits) || isnan(nDigits) || nDigits < 1
        error('Invalid IEEE-488.2 block header: bad digit-count after #.');
    end

    lenStr = char(read(io, nDigits, 'char')).';
    payloadLen = str2double(lenStr);
    if ~isscalar(payloadLen) || isnan(payloadLen) || payloadLen < 0
        error('Invalid IEEE-488.2 block header: bad payload length.');
    end

    payload = read(io, payloadLen, 'uint8');

    % Best-effort drain of one trailing LF if present.
    try
        trailing = read(io, 1, 'uint8'); %#ok<NASGU>
    catch
    end

    info = struct;
    info.prefix = char(prefix(:).');
    info.nDigits = nDigits;
    info.payloadLen = payloadLen;
    info.headerLengthBytes = numel(prefix) + 1 + nDigits;
end

function out = parseLeCroyWFAllPayload(payload)
% Parses a LeCroy WF? ALL payload using WAVEDESC offsets.
% This parser targets the common analog DAT1 case.

    u8 = uint8(payload(:)).';
    descStart = findSubarray(u8, uint8('WAVEDESC'));
    if isempty(descStart)
        error('Could not locate WAVEDESC in payload.');
    end
    descStart = descStart(1);

    % Descriptor uses 0-based offsets relative to WAVEDESC in the manual.
    z = @(off0) descStart + off0;

    % Determine endianness from COMM_ORDER. The manual documents COMM_ORDER and
    % recommends CORD LO for Intel hosts. We probe both byte orders if needed.
    commOrderLE = rd_u16(u8, z(34), true);
    if ismember(commOrderLE, [0 1])
        littleEndian = (commOrderLE == 1);
        commOrder = commOrderLE;
    else
        commOrderBE = rd_u16(u8, z(34), false);
        if ~ismember(commOrderBE, [0 1])
            error('Could not decode COMM_ORDER from WAVEDESC.');
        end
        littleEndian = (commOrderBE == 1);
        commOrder = commOrderBE;
    end

    out = struct;
    out.payload = u8(:);
    out.descStart = descStart;
    out.littleEndian = littleEndian;
    out.commOrder = commOrder;

    % Core documented fields.
    out.commType       = rd_u16(u8, z(32), littleEndian);    % 0=BYTE, 1=WORD
    out.waveDescLen    = rd_i32(u8, z(36), littleEndian);
    out.userTextLen    = rd_i32(u8, z(40), littleEndian);
    out.trigtimeLen    = rd_i32(u8, z(48), littleEndian);
    out.risTimeLen     = rd_i32(u8, z(52), littleEndian);
    out.waveArray1Len  = rd_i32(u8, z(60), littleEndian);
    out.waveArray2Len  = rd_i32(u8, z(64), littleEndian);

    % Frequently useful fields in the standard LeCroy descriptor.
    % These offsets are conventional for analog trace descriptors.
    out.instrumentName = rd_string(u8, z(76), 16);
    out.traceLabel     = rd_string(u8, z(96), 16);
    out.waveArrayCount = rd_i32(u8, z(116), littleEndian);
    out.pointsPerScreen= rd_i32(u8, z(120), littleEndian);
    out.firstValidPnt  = rd_i32(u8, z(124), littleEndian);
    out.lastValidPnt   = rd_i32(u8, z(128), littleEndian);
    out.firstPoint     = rd_i32(u8, z(132), littleEndian);
    out.sparsingFactor = rd_i32(u8, z(136), littleEndian);
    out.segmentIndex   = rd_i32(u8, z(140), littleEndian);
    out.subarrayCount  = rd_i32(u8, z(144), littleEndian);
    out.sweepsPerAcq   = rd_i32(u8, z(148), littleEndian);
    out.pointsPerPair  = rd_u16(u8, z(152), littleEndian);
    out.pairOffset     = rd_u16(u8, z(154), littleEndian);
    out.verticalGain   = rd_f32(u8, z(156), littleEndian);
    out.verticalOffset = rd_f32(u8, z(160), littleEndian);
    out.maxValue       = rd_f32(u8, z(164), littleEndian);
    out.minValue       = rd_f32(u8, z(168), littleEndian);
    out.nominalBits    = rd_u16(u8, z(172), littleEndian);
    out.nomSubarrayCnt = rd_u16(u8, z(174), littleEndian);
    out.horizInterval  = rd_f32(u8, z(176), littleEndian);
    out.horizOffset    = rd_f64(u8, z(180), littleEndian);
    out.pixelOffset    = rd_f64(u8, z(188), littleEndian);
    out.vertUnit       = rd_string(u8, z(196), 48);
    out.horUnit        = rd_string(u8, z(244), 48);
    out.triggerTime    = rd_bytes(u8, z(292), 16); %# raw 2x double pair in many templates
    out.acqDuration    = rd_f32(u8, z(312), littleEndian);
    out.recordType     = rd_u16(u8, z(316), littleEndian);
    out.processingDone = rd_u16(u8, z(318), littleEndian);
    out.timebase       = rd_u16(u8, z(324), littleEndian);
    out.vertCoupling   = rd_u16(u8, z(326), littleEndian);
    out.probeAtt       = rd_f32(u8, z(328), littleEndian);
    out.fixedVertGain  = rd_u16(u8, z(332), littleEndian);
    out.bandwidthLimit = rd_u16(u8, z(334), littleEndian);
    out.verticalVernier= rd_f32(u8, z(336), littleEndian);
    out.acqVertOffset  = rd_f32(u8, z(340), littleEndian);
    out.waveSource     = rd_u16(u8, z(344), littleEndian);

    % Block starts after descriptor.
    pos = descStart + double(out.waveDescLen);
    out.userText = uint8([]);
    if out.userTextLen > 0
        out.userText = rd_bytes(u8, pos, out.userTextLen);
        pos = pos + double(out.userTextLen);
    end

    out.trigtimeRaw = uint8([]);
    if out.trigtimeLen > 0
        out.trigtimeRaw = rd_bytes(u8, pos, out.trigtimeLen);
        pos = pos + double(out.trigtimeLen);
    end

    out.risTimeRaw = uint8([]);
    if out.risTimeLen > 0
        out.risTimeRaw = rd_bytes(u8, pos, out.risTimeLen);
        pos = pos + double(out.risTimeLen);
    end

    out.dat1Start = pos;
    dat1Bytes = double(out.waveArray1Len);
    if dat1Bytes <= 0
        % Fallback: use the tail if descriptor length fields are unavailable.
        dat1Bytes = numel(u8) - pos + 1;
    end
    dat1End = min(numel(u8), pos + dat1Bytes - 1);
    dat1 = u8(pos:dat1End);
    out.dat1Bytes = dat1(:);

    % Parse analog samples.
    switch out.commType
        case 0 % BYTE
            raw = typecast(uint8(dat1), 'int8');
        case 1 % WORD
            if mod(numel(dat1), 2) ~= 0
                dat1 = dat1(1:end-1);
            end
            if littleEndian
                raw = typecast(uint8(dat1), 'int16');
            else
                tmp = reshape(uint8(dat1), 2, []);
                tmp = flipud(tmp);
                raw = typecast(uint8(tmp(:).'), 'int16');
            end
        otherwise
            error('Unsupported COMM_TYPE %d. Expected 0 (BYTE) or 1 (WORD).', out.commType);
    end

    out.raw = raw(:);
    out.volts = double(out.raw) .* double(out.verticalGain) - double(out.verticalOffset);

    % Sanity-fix sample count if WAVEDESC count disagrees with actual bytes.
    out.nSamples = numel(out.raw);
    if out.waveArrayCount <= 0
        out.waveArrayCount = out.nSamples;
    end

    % Best-effort trigger time parse if present and length is at least one pair of doubles.
    if ~isempty(out.trigtimeRaw) && mod(numel(out.trigtimeRaw), 16) == 0
        nPairs = numel(out.trigtimeRaw) / 16;
        tt = zeros(nPairs, 2);
        for k = 1:nPairs
            base = (k-1)*16 + 1;
            tt(k,1) = rd_f64(out.trigtimeRaw, base, littleEndian); % TRIGGER_TIME
            tt(k,2) = rd_f64(out.trigtimeRaw, base+8, littleEndian); % TRIGGER_OFFSET
        end
        out.trigtimePairs = tt;
    else
        out.trigtimePairs = [];
    end
end

function [dt, t0] = queryTimeScaleInspect(io, chan)
% Optional helper when you want intelligible values instead of descriptor offsets.
    flush(io);
    writeline(io, sprintf('%s:INSP? "HORIZ_INTERVAL"', chan));
    s1 = readline(io);
    writeline(io, sprintf('%s:INSP? "HORIZ_OFFSET"', chan));
    s2 = readline(io);
    dt = firstNumericToken(s1);
    t0 = firstNumericToken(s2);
end

function x = firstNumericToken(s)
    tok = regexp(char(s), '([-+]?\d*\.?\d+(?:[eE][-+]?\d+)?)', 'match');
    if isempty(tok)
        error('Could not parse numeric token from INSPECT response: %s', string(s));
    end
    x = str2double(tok{1});
end

function secs = estimateTimeoutSeconds(nBytes, bytesPerSecond)
    secs = max(10, 3.0 * double(nBytes) / double(bytesPerSecond));
end

function tryWriteLine(io, cmd)
    writeline(io, char(cmd));
end

function idx = findSubarray(hay, needle)
    idx = strfind(hay, needle);
end

function b = rd_bytes(u8, idx1, n)
    idx2 = idx1 + n - 1;
    if idx1 < 1 || idx2 > numel(u8)
        error('Descriptor read out of bounds.');
    end
    b = u8(idx1:idx2);
end

function s = rd_string(u8, idx1, n)
    b = rd_bytes(u8, idx1, n);
    b = b(:).';
    z = find(b == 0, 1, 'first');
    if ~isempty(z)
        b = b(1:z-1);
    end
    s = strtrim(char(b));
end

function v = rd_u16(u8, idx1, little)
    b = rd_bytes(u8, idx1, 2);
    if ~little, b = fliplr(b); end
    v = double(typecast(uint8(b), 'uint16'));
end

function v = rd_i16(u8, idx1, little)
    b = rd_bytes(u8, idx1, 2);
    if ~little, b = fliplr(b); end
    v = double(typecast(uint8(b), 'int16'));
end

function v = rd_u32(u8, idx1, little)
    b = rd_bytes(u8, idx1, 4);
    if ~little, b = fliplr(b); end
    v = double(typecast(uint8(b), 'uint32'));
end

function v = rd_i32(u8, idx1, little)
    b = rd_bytes(u8, idx1, 4);
    if ~little, b = fliplr(b); end
    v = double(typecast(uint8(b), 'int32'));
end

function v = rd_f32(u8, idx1, little)
    b = rd_bytes(u8, idx1, 4);
    if ~little, b = fliplr(b); end
    v = double(typecast(uint8(b), 'single'));
end

function v = rd_f64(u8, idx1, little)
    b = rd_bytes(u8, idx1, 8);
    if ~little, b = fliplr(b); end
    v = double(typecast(uint8(b), 'double'));
end

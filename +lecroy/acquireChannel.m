function channelData = acquireChannel(session, cfg, channel)
% lecroy.acquireChannel  Acquire one channel via INSPECT? queries.

arguments
    session struct
    cfg struct
    channel (1,1) double {mustBeInteger, mustBePositive}
end

source = sprintf('C%d', channel);

channelData = struct();
channelData.source = string(source);
channelData.label = lecroy.lookupChannelLabel(cfg, source);
channelData.meta = struct();

for k = 1:numel(cfg.transfer.queryVariables)
    v = string(cfg.transfer.queryVariables(k));
    info = lecroy.inspectValue(session, source, v);
    channelData.meta.(matlab.lang.makeValidName(char(v))) = info;
end

channelData.amplitude = lecroy.readDataArray(session, source, cfg.transfer.dataBlock, cfg.transfer.dataType);

horizInterval = channelData.meta.HORIZ_INTERVAL.numeric;
horizOffset = channelData.meta.HORIZ_OFFSET.numeric;
N = numel(channelData.amplitude);
channelData.time = horizOffset + (0:N-1).' .* horizInterval;

channelData.units = struct('time', "s", 'amplitude', string(lecroy.extractQuotedValue(channelData.meta.VERTUNIT.raw)));
if strlength(channelData.units.amplitude) == 0
    channelData.units.amplitude = "V";
end

% Additional convenience fields.
channelData.sampleCount = N;
channelData.dt = horizInterval;
channelData.t0 = horizOffset;
end

function result = acquireRun(cfg)
% lecroy.acquireRun  Acquire one run from the oscilloscope using WF? ALL only.
%
% This version assumes:
%   - waveform readback is done exclusively through lecroy_waveform_all_parser
%   - the parser file is on the MATLAB path
%   - CSV output remains compatible with the existing post-processing code
%
% Required config fields:
%   cfg.connection.*
%   cfg.acquisition.*
%   cfg.transfer.parser.*
%   cfg.storage.*
%   cfg.logging.*
%
% Returns:
%   result struct with paths, manifest, and per-channel waveform data

    arguments
        cfg struct
    end

    validateConfig(cfg);

    session = [];
    try
        session = lecroy.connect(cfg);

        if cfg.acquisition.stopBeforeSetup
            tryWriteLine(session, "STOP");
        end

        if cfg.acquisition.clearSweeps
            tryWriteLine(session, "CLSW");
        end

        % Optional user setup commands before arming
        runCommandList(session, cfg.acquisition.setupCommands);

        % Arm acquisition if requested
        switch lower(string(cfg.acquisition.acquireMode))
            case "single"
                tryWriteLine(session, "TRMD SINGLE");
                waitForAcquisitionComplete(session, cfg.acquisition.waitTimeoutSeconds);
            otherwise
                error("lecroy.acquireRun:UnsupportedAcquireMode", ...
                    "Unsupported acquireMode: %s", cfg.acquisition.acquireMode);
        end

        % Optional post-arm commands
        runCommandList(session, cfg.acquisition.postArmCommands);

        % Extra settle time if desired
        if isfield(cfg.acquisition, "waitAfterIdleSeconds") && cfg.acquisition.waitAfterIdleSeconds > 0
            pause(cfg.acquisition.waitAfterIdleSeconds);
        end

        % Build storage paths
        runDir = buildRunDir(cfg.storage, cfg.acquisition.runIndex);

        if ~exist(runDir, 'dir')
            mkdir(runDir);
        end
        % else
        %     timeout=tic;
        %     while(exist(runDir,'dir'))
        %         % update run index folder until new # if existing
        %         cfg.acquisition.runIndex = cfg.acquisition.runIndex + 1;
        %         runDir = buildRunDir(cfg.storage, cfg.acquisition.runIndex);
        %         mkdir(runDir);
        % 
        %         % prevent infinite
        %         if toc(timeout) > 10
        %             error('Timeout creating new run dir folder');
        %         end
        %     end
        % end
        runIndex = cfg.acquisition.runIndex;


        % Read all requested channels using WFALL parser only
        channelData = struct();
        % parserFcn = str2func(cfg.transfer.parser.functionName);

        for ch = cfg.acquisition.channels
            chanName = "C" + string(ch);

            wf = lecroy.lecroy_waveform_all_parser( ...
                session.io, chanName, ...
                "AcquireSingle", cfg.transfer.parser.acquireSingle, ...
                "TimeoutSeconds", cfg.transfer.parser.timeoutSeconds, ...
                "CommFormat", cfg.transfer.parser.commFormat, ...
                "CommOrder", cfg.transfer.parser.commOrder, ...
                "WaveformSetup", cfg.transfer.parser.waveformSetup, ...
                "FallbackInspectTimeScale", cfg.transfer.parser.fallbackInspectTimeScale, ...
                "Verbose", cfg.transfer.parser.verbose);

            entry = struct();
            entry.channel = chanName;
            entry.time = wf.t(:);
            entry.amplitude = wf.volts(:);
            entry.raw = wf.raw(:);
            entry.waveform = wf;

            if isfield(wf, 'verticalGain');    entry.verticalGain = wf.verticalGain; end
            if isfield(wf, 'verticalOffset');  entry.verticalOffset = wf.verticalOffset; end
            if isfield(wf, 'horizInterval');   entry.horizInterval = wf.horizInterval; end
            if isfield(wf, 'horizOffset');     entry.horizOffset = wf.horizOffset; end
            if isfield(wf, 'waveArrayCount');  entry.waveArrayCount = wf.waveArrayCount; end

            channelData.(chanName) = entry;

            % Write CSV immediately to preserve compatibility with post-processing
            if cfg.storage.writeCsv
                csvPath = fullfile(runDir, sprintf('%s_%d_%d.csv', ...
                    cfg.acquisition.recordName, runIndex, ch));
                writeTwoColumnCsv(csvPath, entry.time, entry.amplitude, cfg.storage.csvHeaderLines);
                channelData.(chanName).csvPath = csvPath;
            end
        end

        % Manifest
        manifest = struct();
        manifest.timestampUtc = char(datetime('now', 'TimeZone', 'UTC', 'Format', 'yyyy-MM-dd''T''HH:mm:ss''Z'''));
        manifest.runIndex = runIndex;
        manifest.connection = cfg.connection;
        manifest.acquisition = cfg.acquisition;
        manifest.transfer = struct();
        manifest.transfer.mode = "WFALL";
        manifest.transfer.dataQuery = "WF? ALL";
        manifest.transfer.parser = cfg.transfer.parser;
        manifest.storage = cfg.storage;
        manifest.channels = channelLabelsToManifest(cfg);

        % Write MAT
        matPath = "";
        if cfg.storage.writeMat
            matPath = fullfile(runDir, 'acquisition.mat');
            save(matPath, 'channelData', 'manifest', '-v7.3');
        end

        % Optional raw parsed waveform MAT
        if isfield(cfg.storage, 'writeParsedWaveformMat') && cfg.storage.writeParsedWaveformMat
            parsedPath = fullfile(runDir, 'waveforms_parsed.mat');
            save(parsedPath, 'channelData', '-v7.3');
        end

        % Optional manifest JSON
        manifestPath = "";
        if cfg.storage.writeManifestJson
            manifestPath = fullfile(runDir, 'manifest.json');
            fid = fopen(manifestPath, 'w');
            assert(fid >= 0, 'Could not open manifest.json for writing.');
            c = onCleanup(@() fclose(fid));
            fprintf(fid, '%s', jsonencode(manifest, 'PrettyPrint', true));
        end

        % Return
        result = struct();
        result.runDir = runDir;
        result.manifest = manifest;
        result.channelData = channelData;
        result.matPath = matPath;
        result.manifestPath = manifestPath;

        if isfield(cfg.logging, 'verbose') && cfg.logging.verbose
            fprintf('Acquisition complete. Run folder: %s\n', runDir);
        end

    catch ME
        if ~isempty(session)
            try
                clear session %#ok<NASGU>
            catch
            end
        end
        rethrow(ME);
    end

    if ~isempty(session)
        try
            clear session %#ok<NASGU>
        catch
        end
    end
end

function validateConfig(cfg)
    mustHave(cfg, "connection");
    mustHave(cfg, "acquisition");
    mustHave(cfg, "transfer");
    mustHave(cfg.transfer, "parser");
    mustHave(cfg, "storage");
    mustHave(cfg, "logging");

    mustHave(cfg.connection, "resource");
    mustHave(cfg.acquisition, "channels");
    mustHave(cfg.acquisition, "recordName");
    mustHave(cfg.acquisition, "runIndex");
    mustHave(cfg.transfer.parser, "functionName");
    mustHave(cfg.transfer.parser, "acquireSingle");
    mustHave(cfg.transfer.parser, "timeoutSeconds");
    mustHave(cfg.transfer.parser, "commFormat");
    mustHave(cfg.transfer.parser, "commOrder");
    mustHave(cfg.transfer.parser, "waveformSetup");
    mustHave(cfg.transfer.parser, "fallbackInspectTimeScale");
    mustHave(cfg.transfer.parser, "verbose");
    mustHave(cfg.storage, "rootDir");
    mustHave(cfg.storage, "writeCsv");
    mustHave(cfg.storage, "csvHeaderLines");
    mustHave(cfg.storage, "writeMat");
    mustHave(cfg.storage, "writeManifestJson");
end

function mustHave(s, fieldName)
    if ~isfield(s, fieldName)
        error("lecroy.acquireRun:MissingConfigField", ...
            "Missing required config field: %s", fieldName);
    end
end

function runCommandList(session, cmds)
    if isempty(cmds)
        return;
    end
    cmds = string(cmds(:));
    for k = 1:numel(cmds)
        cmd = strtrim(cmds(k));
        if strlength(cmd) == 0
            continue;
        end
        tryWriteLine(session, cmd);
    end
end

function tryWriteLine(session, cmd)
    writeline(session.io, char(cmd));
end

function waitForAcquisitionComplete(session, timeoutSeconds)
    if nargin < 2 || isempty(timeoutSeconds)
        timeoutSeconds = 30;
    end

    io=session.io; % assign to actual object

    oldTimeout = io.Timeout;
    c = onCleanup(@() setTimeout(session, oldTimeout));
    io.Timeout = timeoutSeconds;

    writeline(io, "*OPC?");
    resp = strtrim(readline(io)); %#ok<NASGU>
end

function setTimeout(session, val)
    io=session.io;
    try
        io.Timeout = val;
    catch
    end
end

function runDir = buildRunDir(storageCfg, runIndex)
    rootDir = storageCfg.rootDir;

    if storageCfg.createDateFolder
        dateDir = char(datetime('today', 'Format', 'yyyy-MM-dd'));
        rootDir = fullfile(rootDir, dateDir);
    end

    runDirName = sprintf(char(storageCfg.runFolderPattern), runIndex);
    runDir = fullfile(rootDir, runDirName);
end

function dateDir = buildDateDir(storageCfg)
    rootDir = storageCfg.rootDir;

    if storageCfg.createDateFolder
        % TODO add check if already exist
        dateDir = char(datetime('today', 'Format', 'yyyy-MM-dd'));
        rootDir = fullfile(rootDir, dateDir);
    end

    dateDir = rootDir;
end

function writeTwoColumnCsv(csvPath, t, y, headerLines)
    outDir = fileparts(csvPath);
    if ~isempty(outDir) && ~exist(outDir, 'dir')
        mkdir(outDir);
    end

    fid = fopen(csvPath, 'w');
    assert(fid >= 0, 'Could not open CSV for writing: %s', csvPath);
    c = onCleanup(@() fclose(fid));

    headerLines = string(headerLines(:));
    for k = 1:numel(headerLines)
        fprintf(fid, '%s\n', headerLines(k));
    end

    data = [t(:), y(:)];
    for k = 1:size(data, 1)
        fprintf(fid, '%.12g,%.12g\n', data(k,1), data(k,2));
    end
end

function out = channelLabelsToManifest(cfg)
    out = struct();
    if ~isfield(cfg.acquisition, 'channelLabels')
        return;
    end

    fields = fieldnames(cfg.acquisition.channelLabels);
    for k = 1:numel(fields)
        f = fields{k};
        out.(f) = cfg.acquisition.channelLabels.(f);
    end
end
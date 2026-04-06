function result = acquireRun(cfg)
% lecroy.acquireRun  Acquire configured channels and export CSV/MAT/manifest.
%
% result = lecroy.acquireRun(cfg)
%
% Expected workflow:
%   cfg = lecroy.defaultConfig();
%   cfg.connection.resource = "USB0::...::INSTR";
%   cfg.storage.rootDir = "D:\\experiment_data";
%   result = lecroy.acquireRun(cfg);

arguments
    cfg struct
end

session = lecroy.connect(cfg);
cleaner = onCleanup(@() lecroy.disconnect(session));

if cfg.logging.verbose
    fprintf('Connected to %s\n', cfg.connection.resource);
end

result = struct();
result.idn = lecroy.safeQuery(session, '*IDN?');
result.runTimestamp = datetime('now');
result.runFolder = lecroy.makeRunFolder(cfg, result.runTimestamp, cfg.acquisition.runIndex);

if cfg.logging.verbose
    fprintf('Run folder: %s\n', result.runFolder);
end

lecroy.runSingleAcquisition(session, cfg);

channels = cfg.acquisition.channels(:).';
result.channels = struct([]);
for ch = channels
    if cfg.logging.verbose
        fprintf('Reading C%d ...\n', ch);
    end
    cd1 = lecroy.acquireChannel(session, cfg, ch);
    result.channels = [result.channels; cd1]; %#ok<AGROW>

    if cfg.storage.writeCsv
        baseName = sprintf('%s_%d_%d.csv', cfg.acquisition.recordName, cfg.acquisition.runIndex, ch);
        csvPath = fullfile(result.runFolder, baseName);
        lecroy.writeCsvWaveform(csvPath, cd1, cfg);
        result.channels(end).csvPath = string(csvPath);
    end
end

manifest = lecroy.buildManifest(cfg, result);
result.manifest = manifest;

if cfg.storage.writeManifestJson
    manifestPath = fullfile(result.runFolder, 'manifest.json');
    lecroy.writeJson(manifestPath, manifest);
    result.manifestPath = string(manifestPath);
end

if cfg.storage.writeMat
    save(fullfile(result.runFolder, 'acquisition.mat'), 'result', '-v7.3');
end

if cfg.logging.verbose
    fprintf('Acquisition complete.\n');
end

clear cleaner
end

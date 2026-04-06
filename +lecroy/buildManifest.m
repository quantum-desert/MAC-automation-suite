function manifest = buildManifest(cfg, result)
% lecroy.buildManifest  Build a JSON-serializable acquisition manifest.

manifest = struct();
manifest.created_at = char(result.runTimestamp);
manifest.instrument_idn = char(string(result.idn));
manifest.connection = lecroy.sanitizeStruct(cfg.connection);
manifest.acquisition = lecroy.sanitizeStruct(cfg.acquisition);
manifest.transfer = lecroy.sanitizeStruct(cfg.transfer);
manifest.storage = lecroy.sanitizeStruct(cfg.storage);
manifest.run_folder = char(string(result.runFolder));

channels = struct([]);
for k = 1:numel(result.channels)
    ch = result.channels(k);
    entry = struct();
    entry.source = char(ch.source);
    entry.label = char(ch.label);
    entry.sample_count = ch.sampleCount;
    entry.dt = ch.dt;
    entry.t0 = ch.t0;
    if isfield(ch,'csvPath')
        entry.csv_path = char(ch.csvPath);
    end
    entry.units = lecroy.sanitizeStruct(ch.units);
    entry.meta = lecroy.sanitizeInspectMeta(ch.meta);
    channels = [channels; entry]; %#ok<AGROW>
end
manifest.channels = channels;
end

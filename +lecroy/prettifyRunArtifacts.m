function pretty = prettifyRunArtifacts(runDir, result, cfg)
% lecroy.prettifyRunArtifacts
% Create human-readable companion files for acquisition.mat and manifest.json.
%
% Outputs:
%   pretty_manifest.json   - normalized, indented manifest
%   acquisition_summary.json - compact run summary
%   acquisition_summary.txt  - easy-to-read text summary
%
% Inputs:
%   runDir  - run folder path
%   result  - result struct returned/being built by acquireRun
%   cfg     - suite config
%
% Returns:
%   pretty struct with output paths

    arguments
        runDir (1,1) string
        result struct
        cfg struct
    end

    if ~isfolder(runDir)
        error("lecroy.prettifyRunArtifacts:MissingRunDir", ...
            "Run directory does not exist: %s", runDir);
    end

    pretty = struct();
    pretty.runDir = runDir;

    manifest = struct();
    if isfield(result, "manifest")
        manifest = result.manifest;
    end

    channelData = struct();
    if isfield(result, "channelData")
        channelData = result.channelData;
    end

    % ---------------------------------------------------------------------
    % Build normalized pretty manifest
    % ---------------------------------------------------------------------
    prettyManifest = struct();
    prettyManifest.createdUtc = char(datetime('now', 'TimeZone', 'UTC', ...
        'Format', 'yyyy-MM-dd''T''HH:mm:ss''Z'''));
    prettyManifest.runDir = char(runDir);

    if isfield(manifest, "timestampUtc"); prettyManifest.timestampUtc = manifest.timestampUtc; end
    if isfield(manifest, "runIndex");     prettyManifest.runIndex = manifest.runIndex; end
    if isfield(manifest, "connection");   prettyManifest.connection = manifest.connection; end
    if isfield(manifest, "acquisition");  prettyManifest.acquisition = manifest.acquisition; end
    if isfield(manifest, "transfer");     prettyManifest.transfer = manifest.transfer; end
    if isfield(manifest, "storage");      prettyManifest.storage = manifest.storage; end
    if isfield(manifest, "channels");     prettyManifest.channels = manifest.channels; end

    prettyManifest.channelSummary = buildChannelSummary(channelData);

    prettyManifestPath = fullfile(runDir, "pretty_manifest.json");
    writePrettyJson(prettyManifestPath, prettyManifest);
    pretty.prettyManifestPath = prettyManifestPath;

    % ---------------------------------------------------------------------
    % Build compact summary from acquisition.mat contents
    % ---------------------------------------------------------------------
    acquisitionSummary = struct();
    acquisitionSummary.createdUtc = prettyManifest.createdUtc;

    if isfield(prettyManifest, "timestampUtc")
        acquisitionSummary.timestampUtc = prettyManifest.timestampUtc;
    end
    if isfield(prettyManifest, "runIndex")
        acquisitionSummary.runIndex = prettyManifest.runIndex;
    end

    acquisitionSummary.runDir = char(runDir);
    acquisitionSummary.numChannels = numel(fieldnames(channelData));
    acquisitionSummary.channels = buildChannelSummary(channelData);

    summaryJsonPath = fullfile(runDir, "acquisition_summary.json");
    writePrettyJson(summaryJsonPath, acquisitionSummary);
    pretty.summaryJsonPath = summaryJsonPath;

    % ---------------------------------------------------------------------
    % Human-readable TXT report
    % ---------------------------------------------------------------------
    summaryTxtPath = fullfile(runDir, "acquisition_summary.txt");
    writeSummaryText(summaryTxtPath, acquisitionSummary, manifest);
    pretty.summaryTxtPath = summaryTxtPath;

    % ---------------------------------------------------------------------
    % Optional re-save a trimmed MAT companion with lighter metadata
    % ---------------------------------------------------------------------
    if isfield(cfg, "storage") && isfield(cfg.storage, "writePrettyMat") && cfg.storage.writePrettyMat
        compact = struct();
        compact.manifest = prettyManifest;
        compact.summary = acquisitionSummary;

        compact.channels = struct();
        chNames = fieldnames(channelData);
        for k = 1:numel(chNames)
            ch = chNames{k};
            src = channelData.(ch);

            dst = struct();
            if isfield(src, "channel");         dst.channel = src.channel; end
            if isfield(src, "csvPath");         dst.csvPath = src.csvPath; end
            if isfield(src, "verticalGain");    dst.verticalGain = src.verticalGain; end
            if isfield(src, "verticalOffset");  dst.verticalOffset = src.verticalOffset; end
            if isfield(src, "horizInterval");   dst.horizInterval = src.horizInterval; end
            if isfield(src, "horizOffset");     dst.horizOffset = src.horizOffset; end
            if isfield(src, "waveArrayCount");  dst.waveArrayCount = src.waveArrayCount; end
            if isfield(src, "time")
                dst.numSamples = numel(src.time);
                dst.timeStart = src.time(1);
                dst.timeEnd = src.time(end);
            end
            if isfield(src, "amplitude")
                dst.minAmplitude = min(src.amplitude);
                dst.maxAmplitude = max(src.amplitude);
                dst.meanAmplitude = mean(src.amplitude);
                dst.rmsAmplitude = sqrt(mean(double(src.amplitude).^2));
            end
            compact.channels.(ch) = dst;
        end

        prettyMatPath = fullfile(runDir, "acquisition_pretty.mat");
        save(prettyMatPath, "compact", "-v7.3");
        pretty.prettyMatPath = prettyMatPath;
    end
end

function out = buildChannelSummary(channelData)
    out = struct();
    chNames = fieldnames(channelData);

    for k = 1:numel(chNames)
        ch = chNames{k};
        d = channelData.(ch);

        s = struct();
        if isfield(d, "channel");        s.channel = d.channel; end
        if isfield(d, "csvPath");        s.csvPath = d.csvPath; end
        if isfield(d, "verticalGain");   s.verticalGain = d.verticalGain; end
        if isfield(d, "verticalOffset"); s.verticalOffset = d.verticalOffset; end
        if isfield(d, "horizInterval");  s.horizInterval = d.horizInterval; end
        if isfield(d, "horizOffset");    s.horizOffset = d.horizOffset; end
        if isfield(d, "waveArrayCount"); s.waveArrayCount = d.waveArrayCount; end

        if isfield(d, "time") && ~isempty(d.time)
            s.numSamples = numel(d.time);
            s.timeStart = d.time(1);
            s.timeEnd = d.time(end);
            if numel(d.time) >= 2
                s.dt = d.time(2) - d.time(1);
            end
        end

        if isfield(d, "amplitude") && ~isempty(d.amplitude)
            y = double(d.amplitude(:));
            s.minAmplitude = min(y);
            s.maxAmplitude = max(y);
            s.meanAmplitude = mean(y);
            s.stdAmplitude = std(y);
            s.rmsAmplitude = sqrt(mean(y.^2));
        end

        out.(ch) = s;
    end
end

function writePrettyJson(pathStr, s)
    txt = jsonencode(s, "PrettyPrint", true);
    fid = fopen(pathStr, "w");
    assert(fid >= 0, "Could not open file for writing: %s", pathStr);
    c = onCleanup(@() fclose(fid));
    fprintf(fid, "%s", txt);
end

function writeSummaryText(pathStr, summary, manifest)
    fid = fopen(pathStr, "w");
    assert(fid >= 0, "Could not open file for writing: %s", pathStr);
    c = onCleanup(@() fclose(fid));

    fprintf(fid, "LeCroy Acquisition Summary\n");
    fprintf(fid, "==========================\n\n");

    if isfield(summary, "timestampUtc")
        fprintf(fid, "Timestamp UTC : %s\n", string(summary.timestampUtc));
    end
    if isfield(summary, "runIndex")
        fprintf(fid, "Run Index     : %d\n", summary.runIndex);
    end
    if isfield(summary, "runDir")
        fprintf(fid, "Run Folder    : %s\n", string(summary.runDir));
    end
    if isfield(summary, "numChannels")
        fprintf(fid, "Channels Read : %d\n", summary.numChannels);
    end

    fprintf(fid, "\n");

    if isfield(manifest, "transfer") && isfield(manifest.transfer, "mode")
        fprintf(fid, "Transfer Mode : %s\n", string(manifest.transfer.mode));
    end
    if isfield(manifest, "transfer") && isfield(manifest.transfer, "dataQuery")
        fprintf(fid, "Data Query    : %s\n", string(manifest.transfer.dataQuery));
    end

    fprintf(fid, "\nChannel Details\n");
    fprintf(fid, "---------------\n");

    chNames = fieldnames(summary.channels);
    for k = 1:numel(chNames)
        ch = chNames{k};
        s = summary.channels.(ch);

        fprintf(fid, "\n%s\n", ch);
        fprintf(fid, "%s\n", repmat("-", 1, strlength(ch)));

        printIfPresent(fid, "Samples", s, "numSamples", "%d");
        printIfPresent(fid, "t start (s)", s, "timeStart", "%.12g");
        printIfPresent(fid, "t end (s)", s, "timeEnd", "%.12g");
        printIfPresent(fid, "dt (s)", s, "dt", "%.12g");
        printIfPresent(fid, "min amp (V)", s, "minAmplitude", "%.12g");
        printIfPresent(fid, "max amp (V)", s, "maxAmplitude", "%.12g");
        printIfPresent(fid, "mean amp (V)", s, "meanAmplitude", "%.12g");
        printIfPresent(fid, "std amp (V)", s, "stdAmplitude", "%.12g");
        printIfPresent(fid, "rms amp (V)", s, "rmsAmplitude", "%.12g");
        printIfPresent(fid, "verticalGain", s, "verticalGain", "%.12g");
        printIfPresent(fid, "verticalOffset", s, "verticalOffset", "%.12g");
        printIfPresent(fid, "horizInterval", s, "horizInterval", "%.12g");
        printIfPresent(fid, "horizOffset", s, "horizOffset", "%.12g");

        if isfield(s, "csvPath")
            fprintf(fid, "%-16s: %s\n", "csvPath", string(s.csvPath));
        end
    end
end

function printIfPresent(fid, label, s, fieldName, fmt)
    if isfield(s, fieldName) && ~isempty(s.(fieldName))
        fprintf(fid, "%-16s: ", label);
        fprintf(fid, [fmt newline], s.(fieldName));
    end
end
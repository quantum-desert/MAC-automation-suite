classdef Brain < handle
    properties
        cfg
        session
        history
        startedAt
        finishedAt
        elapsedSeconds double = 0
        brainReport
        sweepSummary
        batchId string = ""
        batchStartedAtUtc string = ""
    end

    methods (Static)
        function rows = tableToStructArray(T)
            if isempty(T)
                rows = struct([]);
                return;
            end
            rows = table2struct(T);
            for i = 1:numel(rows)
                f = fieldnames(rows(i));
                for k = 1:numel(f)
                    val = rows(i).(f{k});
                    if isstring(val) && isscalar(val)
                        rows(i).(f{k}) = char(val);
                    end
                end
            end
        end

        function writeTableAtomic(finalPath, T)
            tmpPath = finalPath + ".tmp";
            outDir = fileparts(finalPath);
            if ~isempty(outDir) && ~exist(outDir, 'dir')
                mkdir(outDir);
            end
            writetable(T, tmpPath, 'FileType', 'text');
            skull.Brain.replaceFileAtomic(tmpPath, finalPath);
        end

        function writeMatAtomic(finalPath, T, S)
            tmpPath = finalPath + ".tmp";
            outDir = fileparts(finalPath);
            if ~isempty(outDir) && ~exist(outDir, 'dir')
                mkdir(outDir);
            end
            brainReport = T; %#ok<NASGU>
            sweepSummary = S; %#ok<NASGU>
            % Prefer -v7 for speed; fall back to -v7.3 only if needed.
            try
                save(tmpPath, 'brainReport', 'sweepSummary', '-v7');
            catch
                save(tmpPath, 'brainReport', 'sweepSummary', '-v7.3');
            end
            skull.Brain.replaceFileAtomic(tmpPath, finalPath);
        end

       function writeJsonAtomic(finalPath, s)
            tmpPath = finalPath + ".tmp";
            outDir = fileparts(finalPath);
            if ~isempty(outDir) && ~exist(outDir, 'dir')
                mkdir(outDir);
            end
        
            txt = jsonencode(s, 'PrettyPrint', true);
        
            fid = fopen(tmpPath, 'w');
            assert(fid >= 0, 'Could not open temp JSON file for writing: %s', tmpPath);
        
            try
                fprintf(fid, '%s', txt);
                fclose(fid);
            catch ME
                if fid >= 0
                    fclose(fid);
                end
                rethrow(ME);
            end
        
            skull.Brain.replaceFileAtomic(tmpPath, finalPath);
        end

        function writeFlaggedTxtAtomic(finalPath, T, S)
            tmpPath = finalPath + ".tmp";
            outDir = fileparts(finalPath);
            if ~isempty(outDir) && ~exist(outDir, 'dir')
                mkdir(outDir);
            end
        
            fid = fopen(tmpPath, 'w');
            assert(fid >= 0, 'Could not open temp TXT file for writing: %s', tmpPath);
        
            try
                fprintf(fid, 'Sweep Flagged Runs Report\n');
                fprintf(fid, '=========================\n\n');
                fprintf(fid, 'Last updated UTC: %s\n', ...
                    char(datetime('now', 'TimeZone', 'UTC', 'Format', 'yyyy-MM-dd HH:mm:ss')));
                fprintf(fid, 'Total runs: %d\n', S.totalRuns);
                fprintf(fid, 'S1 beats classical: %d\n', S.numS1BeatsClassical);
                fprintf(fid, 'S2 beats classical: %d\n', S.numS2BeatsClassical);
                fprintf(fid, 'Either beats classical: %d\n', S.numAnyBeatsClassical);
                fprintf(fid, 'Both beat classical: %d\n\n', S.numBothBeatClassical);
        
                flagged = T(T.anyBeatsClassical, :);
        
                if isempty(flagged)
                    fprintf(fid, 'No runs satisfied SNRe > SNR_C.\n');
                else
                    fprintf(fid, 'Runs where SNRe > SNR_C\n');
                    fprintf(fid, '-----------------------\n');
                    for i = 1:height(flagged)
                        fprintf(fid, ...
                            'Run %-6g | %-7s | S1 margin = %+0.6g | S2 margin = %+0.6g | %s\n', ...
                            flagged.runIndex(i), ...
                            string(flagged.flag(i)), ...
                            flagged.S1_margin(i), ...
                            flagged.S2_margin(i), ...
                            string(flagged.runDir(i)));
                    end
                end
        
                fclose(fid);
            catch ME
                if fid >= 0
                    fclose(fid);
                end
                rethrow(ME);
            end
        
            skull.Brain.replaceFileAtomic(tmpPath, finalPath);
        end

        function out = toJsonSafe(in)
            if isstruct(in)
                out = struct();
                f = fieldnames(in);
                for k = 1:numel(f)
                    out.(f{k}) = skull.Brain.toJsonSafe(in.(f{k}));
                end
                return;
            end

            if iscell(in)
                out = cell(size(in));
                for k = 1:numel(in)
                    out{k} = skull.Brain.toJsonSafe(in{k});
                end
                return;
            end

            if isdatetime(in)
                if isscalar(in)
                    out = char(string(in));
                else
                    out = cellstr(string(in));
                end
                return;
            end

            if isduration(in)
                if isscalar(in)
                    out = char(string(in));
                else
                    out = cellstr(string(in));
                end
                return;
            end

            if isstring(in)
                if isscalar(in)
                    out = char(in);
                else
                    out = cellstr(in);
                end
                return;
            end

            out = in;
        end

        function replaceFileAtomic(tmpPath, finalPath)
            if isfile(finalPath)
                delete(finalPath);
            end
            ok = movefile(tmpPath, finalPath, 'f');
            if ~ok
                error('Could not replace file: %s', finalPath);
            end
        end
    end

    methods
        function obj = Brain(cfg, session)
            obj.cfg = cfg;
            obj.session = session;
            obj.history = struct('runIndex', {}, 'runDir', {}, 'acquisition', {}, 'processing', {}, 'error', {});
            obj.brainReport = table();
            obj.sweepSummary = struct();
            obj.batchId = "";
            obj.batchStartedAtUtc = string(datetime('now', 'TimeZone', 'UTC', 'Format', 'yyyy-MM-dd''T''HH:mm:ss''Z'''));
        end

        function history = run(obj)
            t0 = tic;
            obj.startedAt = datetime('now');
            runIndex = obj.cfg.acquisition.runIndex;

            while toc(t0) < obj.cfg.brain.runDurationSeconds
                cfgIter = obj.cfg;
                cfgIter.acquisition.runIndex = runIndex;

                entry = struct();
                entry.runIndex = runIndex;
                entry.runDir = "";
                entry.acquisition = [];
                entry.processing = [];
                entry.error = char("");

                acq = struct();

                try
                    acq = lecroy.acquireRun(cfgIter, obj.session);
                    entry.acquisition = acq;
                    entry.runDir = string(acq.runDir);

                    if isfield(cfgIter, 'postprocess') && cfgIter.brain.processAfterAcquire
                        ppCfg = cfgIter.postprocess;
                        ppCfg.runIndex = runIndex;
                        ppCfg.runDir = string(acq.runDir);
                        proc = postprocess.processRun(acq.runDir, ppCfg);
                        entry.processing = proc;
                    end
                catch ME
                    entry.error = char(getReport(ME, 'extended', 'hyperlinks', 'off'));
                    obj.history(end+1) = entry; %#ok<AGROW>
                    if obj.cfg.brain.stopOnError
                        rethrow(ME);
                    end
                end

                if isempty(entry.error)
                    obj.history(end+1) = entry; %#ok<AGROW>
                end

                if obj.cfg.brain.processAfterAcquire && ~isempty(entry.processing)
                    obj = obj.recordPostprocess(acq, entry.processing);
                end

                runIndex = runIndex + 1;

                if obj.cfg.brain.pauseBetweenRunsSeconds > 0
                    pause(obj.cfg.brain.pauseBetweenRunsSeconds);
                end
            end

            obj.finishedAt = datetime('now');
            obj.elapsedSeconds = toc(t0);
            obj.writeSweepSummary();
            history = obj.history;
        end

        function history = runSingle(obj)
            runIndex = 1;
            cfgIter = obj.cfg;
            cfgIter.acquisition.runIndex = runIndex;

            entry = struct();
            entry.runIndex = runIndex;
            entry.runDir = "";
            entry.acquisition = [];
            entry.processing = [];
            entry.error = "";

            acq = struct();

            try
                acq = lecroy.acquireRun(cfgIter, obj.session);
                entry.acquisition = acq;
                entry.runDir = string(acq.runDir);

                if isfield(cfgIter, 'postprocess') && cfgIter.brain.processAfterAcquire
                    ppCfg = cfgIter.postprocess;
                    ppCfg.runIndex = runIndex;
                    ppCfg.runDir = string(acq.runDir);
                    proc = postprocess.processRun(acq.runDir, ppCfg);
                    entry.processing = proc;
                end
            catch ME
                entry.error = string(getReport(ME, 'extended', 'hyperlinks', 'off'));
                obj.history(end+1) = entry; %#ok<AGROW>
                if obj.cfg.brain.stopOnError
                    rethrow(ME);
                end
            end

            if isempty(entry.error)
                obj.history(end+1) = entry; %#ok<AGROW>
            end

            if isempty(entry.error) && obj.cfg.brain.processAfterAcquire && ~isempty(entry.processing)
                obj = obj.recordPostprocess(acq, entry.processing);
            end

            if obj.cfg.brain.pauseBetweenRunsSeconds > 0
                pause(obj.cfg.brain.pauseBetweenRunsSeconds);
            end

            history = obj.history;
        end

        function writeSweepTrackingFilesAtomic(obj)
            if ~isfield(obj.cfg, 'storage') || ~isfield(obj.cfg.storage, 'rootDir')
                warning('Brain:writeSweepTrackingFilesAtomic:MissingRootDir', 'cfg.storage.rootDir is missing. Sweep summary not written.');
                return;
            end

            rootDir = string(obj.cfg.storage.rootDir);
            if strlength(rootDir) == 0
                warning('Brain:writeSweepTrackingFilesAtomic:EmptyRootDir', 'cfg.storage.rootDir is empty. Sweep summary not written.');
                return;
            end

            if ~exist(rootDir, 'dir')
                mkdir(rootDir);
            end

            T = obj.brainReport;
            S = obj.sweepSummary;
            batchInfo = obj.buildBatchInfo(T);
            writeOpts = obj.getSweepWriteOptions();
            TTracking = T;
            if any(strcmp('runDir', TTracking.Properties.VariableNames))
                TTracking.runDir = [];
            end

            sweepBaseDir = obj.resolveSweepBaseDir(T, rootDir);
            if ~exist(sweepBaseDir, 'dir')
                mkdir(sweepBaseDir);
            end

            sweepRootDir = fullfile(sweepBaseDir, 'sweep_state');
            if ~exist(sweepRootDir, 'dir')
                mkdir(sweepRootDir);
            end

            if strlength(obj.batchId) == 0
                obj.batchId = obj.allocateNextBatchId(sweepRootDir);
            end

            sweepDir = fullfile(sweepRootDir, char(obj.batchId));
            if ~exist(sweepDir, 'dir')
                mkdir(sweepDir);
            end

            if writeOpts.writeCsvEveryRun
                skull.Brain.writeTableAtomic(fullfile(sweepDir, 'sweep_tracking.csv'), TTracking);
            end

            if writeOpts.writeMatEveryRun
                skull.Brain.writeMatAtomic(fullfile(sweepDir, 'sweep_tracking.mat'), TTracking, S);
            end

            jsonStruct = struct();
            jsonStruct.lastUpdatedUtc = char(datetime('now', 'TimeZone', 'UTC', 'Format', 'yyyy-MM-dd''T''HH:mm:ss''Z'''));
            jsonStruct.summary = S;
            jsonStruct.batch = batchInfo;
            jsonStruct.rows = skull.Brain.tableToStructArray(TTracking);
            skull.Brain.writeJsonAtomic(fullfile(sweepDir, 'sweep_tracking.json'), jsonStruct);
            skull.Brain.writeJsonAtomic(fullfile(sweepDir, 'batch_info.json'), batchInfo);
            % Mirror a per-batch tracker at sweep_state root so each batch has
            % its own persistent tracking JSON (updated every run in this batch).
            skull.Brain.writeJsonAtomic( ...
                fullfile(sweepRootDir, sprintf('sweep_tracking_%s.json', char(obj.batchId))), ...
                jsonStruct);

            if writeOpts.writeFlaggedEveryRun
                skull.Brain.writeFlaggedTxtAtomic(fullfile(sweepDir, 'sweep_flagged_runs.txt'), T, S);
            end

            status = struct();
            status.lastUpdatedUtc = jsonStruct.lastUpdatedUtc;
            status.batchId = char(obj.batchId);
            status.batchDir = char(string(sweepDir));
            status.totalRuns = S.totalRuns;
            if ~isempty(T)
                status.lastRunIndex = T.runIndex(end);
                status.lastFlag = char(string(T.flag(end)));
            else
                status.lastRunIndex = NaN;
                status.lastFlag = '';
            end
            skull.Brain.writeJsonAtomic(fullfile(sweepDir, 'latest_status.json'), status);

            latestBatch = struct();
            latestBatch.lastUpdatedUtc = jsonStruct.lastUpdatedUtc;
            latestBatch.batchId = char(obj.batchId);
            latestBatch.batchDir = char(string(sweepDir));
            latestBatch.batch = batchInfo;
            skull.Brain.writeJsonAtomic(fullfile(sweepRootDir, 'latest_batch.json'), latestBatch);

            physicsCfg = obj.extractPhysicsCfg();
            if ~isempty(physicsCfg)
                physicsPath = fullfile(sweepDir, 'physics_cfg.json');
                if ~writeOpts.staticBatchFilesOnce || ~isfile(physicsPath)
                    skull.Brain.writeJsonAtomic(physicsPath, physicsCfg);
                end
            end

            ppRecord = obj.extractDefaultConfigPPRecord();
            if ~isempty(ppRecord)
                cfgRecordPath = fullfile(sweepDir, 'defaultConfigPP_record.json');
                if ~writeOpts.staticBatchFilesOnce || ~isfile(cfgRecordPath)
                    skull.Brain.writeJsonAtomic(cfgRecordPath, ppRecord);
                end
            end
        end

        function writeSweepSummary(obj)
            if ~obj.cfg.brain.saveSweepSummary
                return;
            end

            summary = struct();
            summary.startedAt = obj.startedAt;
            summary.finishedAt = obj.finishedAt;
            summary.elapsedSeconds = obj.elapsedSeconds;
            summary.numRuns = numel(obj.history);
            summary.runIndices = arrayfun(@(x) x.runIndex, obj.history);
            summary.runDirs = arrayfun(@(x) string(x.runDir), obj.history, 'UniformOutput', false);

            outDir = obj.resolveSweepBaseDirFromHistory();
            outDir = fullfile(outDir, 'sweep_state');
            if ~exist(outDir, 'dir')
                mkdir(outDir);
            end

            stamp = datestr(now, 'yyyymmdd_HHMMSS');
            save(fullfile(outDir, sprintf('brain_sweep_%s.mat', stamp)), 'summary', '-v7.3');
            lecroy.writeJson(fullfile(outDir, sprintf('brain_sweep_%s.json', stamp)), summary);
        end

        function obj = recordPostprocess(obj, acq, pp)
            if ~isfield(pp, 'summary')
                error('Brain:recordPostprocess:MissingSummary', 'pp must contain a summary field.');
            end

            s = pp.summary;
            required = {'S1.SNRe','S1.SNR_C','S2.SNRe','S2.SNR_C'};
            for k = 1:numel(required)
                parts = strsplit(required{k}, '.');
                node = s;
                for p = 1:numel(parts)
                    if ~isstruct(node) || ~isfield(node, parts{p})
                        error('Brain:recordPostprocess:MissingSummaryField', 'pp.summary is missing required field: %s', required{k});
                    end
                    node = node.(parts{p});
                end
            end

            runIndex = NaN;
            timestampUtc = "";
            runDir = "";

            if isfield(acq, 'manifest')
                if isfield(acq.manifest, 'runIndex')
                    runIndex = acq.manifest.runIndex;
                end
                if isfield(acq.manifest, 'timestampUtc')
                    timestampUtc = string(acq.manifest.timestampUtc);
                end
            end
            if isfield(acq, 'runDir')
                runDir = string(acq.runDir);
            end

            S1_margin = s.S1.SNRe - s.S1.SNR_C;
            S2_margin = s.S2.SNRe - s.S2.SNR_C;
            S1_beatsClassical = S1_margin > 0;
            S2_beatsClassical = S2_margin > 0;
            anyBeatsClassical = S1_beatsClassical || S2_beatsClassical;
            bothBeatClassical = S1_beatsClassical && S2_beatsClassical;

            if bothBeatClassical
                flag = "strong";
            elseif anyBeatsClassical
                flag = "partial";
            else
                flag = "none";
            end

            newRow = table( ...
                runIndex, timestampUtc, runDir, ...
                s.S1.SNRe, s.S1.SNR_C, S1_margin, S1_beatsClassical, ...
                s.S2.SNRe, s.S2.SNR_C, S2_margin, S2_beatsClassical, ...
                anyBeatsClassical, bothBeatClassical, flag, ...
                'VariableNames', { ...
                    'runIndex', 'timestampUtc', 'runDir', ...
                    'S1_SNRe', 'S1_SNR_C', 'S1_margin', 'S1_beatsClassical', ...
                    'S2_SNRe', 'S2_SNR_C', 'S2_margin', 'S2_beatsClassical', ...
                    'anyBeatsClassical', 'bothBeatClassical', 'flag'});

            obj.brainReport = [obj.brainReport; newRow];

            summary = struct();
            summary.totalRuns = height(obj.brainReport);
            summary.numS1BeatsClassical = sum(obj.brainReport.S1_beatsClassical);
            summary.numS2BeatsClassical = sum(obj.brainReport.S2_beatsClassical);
            summary.numAnyBeatsClassical = sum(obj.brainReport.anyBeatsClassical);
            summary.numBothBeatClassical = sum(obj.brainReport.bothBeatClassical);

            [~, idxBestS1] = max(obj.brainReport.S1_margin);
            [~, idxBestS2] = max(obj.brainReport.S2_margin);
            [~, idxBestAny] = max(max([obj.brainReport.S1_margin obj.brainReport.S2_margin], [], 2));

            summary.bestS1RunIndex = obj.brainReport.runIndex(idxBestS1);
            summary.bestS1Margin = obj.brainReport.S1_margin(idxBestS1);
            summary.bestS2RunIndex = obj.brainReport.runIndex(idxBestS2);
            summary.bestS2Margin = obj.brainReport.S2_margin(idxBestS2);
            summary.bestAnyRunIndex = obj.brainReport.runIndex(idxBestAny);
            summary.bestAnyFlag = obj.brainReport.flag(idxBestAny);

            obj.sweepSummary = summary;

            shouldSave = true;
            if isfield(obj.cfg, 'brain') && isfield(obj.cfg.brain, 'saveSweepSummary')
                shouldSave = logical(obj.cfg.brain.saveSweepSummary);
            end
            % if shouldSave
                obj.writeSweepTrackingFilesAtomic();
            % end
        end

        function batchInfo = buildBatchInfo(obj, T)
            batchInfo = struct();
            batchInfo.batchId = char(obj.batchId);
            batchInfo.startedAtUtc = char(obj.batchStartedAtUtc);
            batchInfo.updatedAtUtc = char(datetime('now', 'TimeZone', 'UTC', 'Format', 'yyyy-MM-dd''T''HH:mm:ss''Z'''));
            batchInfo.numRunsInBatch = height(T);

            if isempty(T)
                defaultStart = NaN;
                if isfield(obj.cfg, 'acquisition') && isfield(obj.cfg.acquisition, 'runIndex')
                    defaultStart = obj.cfg.acquisition.runIndex;
                end
                batchInfo.runIndexStart = defaultStart;
                batchInfo.runIndexEnd = defaultStart;
                batchInfo.runIndices = [];
                return;
            end

            runIdx = T.runIndex;
            runIdx = runIdx(~isnan(runIdx));
            if isempty(runIdx)
                batchInfo.runIndexStart = NaN;
                batchInfo.runIndexEnd = NaN;
                batchInfo.runIndices = [];
                return;
            end

            batchInfo.runIndexStart = min(runIdx);
            batchInfo.runIndexEnd = max(runIdx);
            batchInfo.runIndices = runIdx(:)';
        end

        function physicsCfg = extractPhysicsCfg(obj)
            physicsCfg = struct();

            if isfield(obj.cfg, 'postprocess') && isfield(obj.cfg.postprocess, 'physics')
                physicsCfg = obj.cfg.postprocess.physics;
            elseif isfield(obj.cfg, 'physics')
                physicsCfg = obj.cfg.physics;
            else
                physicsCfg = [];
                return;
            end

            physicsCfg = skull.Brain.toJsonSafe(physicsCfg);
        end

        function ppRecord = extractDefaultConfigPPRecord(obj)
            if ~isfield(obj.cfg, 'postprocess') || ~isstruct(obj.cfg.postprocess)
                ppRecord = [];
                return;
            end

            pp = obj.cfg.postprocess;
            ppRecord = struct();
            ppRecord.recordType = 'defaultConfigPP_snapshot';
            ppRecord.capturedAtUtc = char(datetime('now', 'TimeZone', 'UTC', 'Format', 'yyyy-MM-dd''T''HH:mm:ss''Z'''));
            ppRecord.batchId = char(obj.batchId);

            if isfield(pp, 'runFolder')
                ppRecord.runFolder = char(string(pp.runFolder));
            end
            if isfield(pp, 'runIndex')
                ppRecord.runIndex = pp.runIndex;
            end
            if isfield(pp, 'recordName')
                ppRecord.recordName = char(string(pp.recordName));
            end
            if isfield(pp, 'constants')
                ppRecord.constants = skull.Brain.toJsonSafe(pp.constants);
            end
            if isfield(pp, 'constantsByChannel')
                ppRecord.constantsByChannel = skull.Brain.toJsonSafe(pp.constantsByChannel);
            end
            if isfield(pp, 'phys_constants')
                ppRecord.phys_constants = skull.Brain.toJsonSafe(pp.phys_constants);
            end
            if isfield(pp, 'processing')
                ppRecord.processing = skull.Brain.toJsonSafe(pp.processing);
            end
            if isfield(pp, 'processingByChannel')
                ppRecord.processingByChannel = skull.Brain.toJsonSafe(pp.processingByChannel);
            end
            if isfield(pp, 'theory')
                ppRecord.theory = skull.Brain.toJsonSafe(pp.theory);
            end
            if isfield(pp, 'channels')
                ppRecord.channels = skull.Brain.toJsonSafe(pp.channels);
            end
            if isfield(pp, 'physics')
                ppRecord.physics = skull.Brain.toJsonSafe(pp.physics);
            end
        end

        function sweepBaseDir = resolveSweepBaseDir(obj, T, rootDir)
            % Prefer the date-folder parent of the current run directory.
            if ~isempty(T) && any(strcmp('runDir', T.Properties.VariableNames))
                lastRunDir = char(string(T.runDir(end)));
                if ~isempty(lastRunDir)
                    candidate = fileparts(lastRunDir);
                    if ~isempty(candidate)
                        sweepBaseDir = string(candidate);
                        return;
                    end
                end
            end

            % Fallback: mirror acquisition folder strategy if enabled.
            if isfield(obj.cfg, 'storage') && isfield(obj.cfg.storage, 'createDateFolder') && ...
                    logical(obj.cfg.storage.createDateFolder)
                dateDir = string(datetime('today', 'Format', 'yyyy-MM-dd'));
                sweepBaseDir = fullfile(rootDir, dateDir);
            else
                sweepBaseDir = rootDir;
            end
        end

        function sweepBaseDir = resolveSweepBaseDirFromHistory(obj)
            rootDir = string(obj.cfg.storage.rootDir);
            if strlength(rootDir) == 0
                sweepBaseDir = rootDir;
                return;
            end

            % Prefer the parent (date folder) of the most recent run directory.
            if ~isempty(obj.history)
                lastRunDir = string(obj.history(end).runDir);
                if strlength(lastRunDir) > 0
                    parentDir = fileparts(char(lastRunDir));
                    if ~isempty(parentDir)
                        sweepBaseDir = string(parentDir);
                        return;
                    end
                end
            end

            % Fallback mirrors acquisition folder strategy.
            if isfield(obj.cfg, 'storage') && isfield(obj.cfg.storage, 'createDateFolder') && ...
                    logical(obj.cfg.storage.createDateFolder)
                dateDir = string(datetime('today', 'Format', 'yyyy-MM-dd'));
                sweepBaseDir = fullfile(rootDir, dateDir);
            else
                sweepBaseDir = rootDir;
            end
        end

        function batchId = allocateNextBatchId(~, sweepRootDir)
            d = dir(fullfile(sweepRootDir, 'batch_*'));
            maxIdx = 0;
            for i = 1:numel(d)
                if ~d(i).isdir
                    continue;
                end
                tok = regexp(d(i).name, '^batch_(\d+)$', 'tokens', 'once');
                if isempty(tok)
                    continue;
                end
                idx = str2double(tok{1});
                if isfinite(idx) && idx > maxIdx
                    maxIdx = idx;
                end
            end
            batchId = "batch_" + string(maxIdx + 1);
        end

        function opts = getSweepWriteOptions(obj)
            % Fast defaults: JSON/status each run; heavy artifacts optional.
            opts = struct();
            opts.writeCsvEveryRun = false;
            opts.writeMatEveryRun = false;
            opts.writeFlaggedEveryRun = false;
            opts.staticBatchFilesOnce = true;

            if ~isfield(obj.cfg, 'brain') || ~isstruct(obj.cfg.brain)
                return;
            end
            b = obj.cfg.brain;

            if isfield(b, 'writeSweepTrackingCsv')
                opts.writeCsvEveryRun = logical(b.writeSweepTrackingCsv);
            end
            if isfield(b, 'writeSweepTrackingMat')
                opts.writeMatEveryRun = logical(b.writeSweepTrackingMat);
            end
            if isfield(b, 'writeSweepFlaggedTxt')
                opts.writeFlaggedEveryRun = logical(b.writeSweepFlaggedTxt);
            end
            if isfield(b, 'writeStaticBatchFilesOnce')
                opts.staticBatchFilesOnce = logical(b.writeStaticBatchFilesOnce);
            end
        end
    end
end

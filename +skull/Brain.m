classdef Brain < handle
    % lecroy.Brain  Simple sweep controller for acquisition + post-processing.
    %
    % The Brain object runs repeated single acquisitions until the configured
    % runDurationSeconds expires. It updates runIndex each pass and can call
    % the refactored post-processing function after each acquisition.

    properties
        cfg
        session
        history
        startedAt
        finishedAt
        elapsedSeconds double = 0
        brainReport
        sweepSummary
    end
    methods (Static)
        function rows = tableToStructArray(T)
            % Convert table rows to JSON-friendly struct array.
    
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
    end
    methods
        function obj = Brain(cfg,session)
            obj.cfg = cfg;
            obj.session = session;
            obj.history = struct('runIndex', {}, 'runDir', {}, 'acquisition', {}, 'processing', {}, 'error', {});
            obj.brainReport = table();
            obj.sweepSummary = table();
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
                entry.error = "";

                try
                    acq = lecroy.acquireRun(cfgIter,obj.session);
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

                runIndex = runIndex + 1;

                % scoreboard
                if obj.cfg.brain.processAfterAcquire
                    obj = obj.recordPostprocess(acq, entry.processing);
                end

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

            runIndex = 1; % only
            
            cfgIter = obj.cfg;
            cfgIter.acquisition.runIndex = runIndex;

            entry = struct();
            entry.runIndex = runIndex;
            entry.runDir = "";
            entry.acquisition = [];
            entry.processing = [];
            entry.error = "";

            try
                acq = lecroy.acquireRun(cfgIter,obj.session);
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


            % scoreboard
            if obj.cfg.brain.processAfterAcquire
                obj = obj.recordPostprocess(acq, entry.processing);
            end

            if obj.cfg.brain.pauseBetweenRunsSeconds > 0
                pause(obj.cfg.brain.pauseBetweenRunsSeconds);
            end
            history = obj.history;
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

            outDir = obj.cfg.storage.rootDir;
            if ~exist(outDir, 'dir')
                mkdir(outDir);
            end
            stamp = datestr(now, 'yyyymmdd_HHMMSS');
            save(fullfile(outDir, sprintf('brain_sweep_%s.mat', stamp)), 'summary', '-v7.3');
            lecroy.writeJson(fullfile(outDir, sprintf('brain_sweep_%s.json', stamp)), summary);
        end

        function obj = recordPostprocess(obj, acq, pp)
        % Brain.recordPostprocess
        % Append one processed run to the sweep ledger and persist rolling reports.
        %
        % INPUTS
        %   obj  - Brain object
        %   acq  - acquisition result from lecroy.acquireRun
        %   pp   - postprocess result struct with pp.summary fields
        %
        % REQUIRED pp.summary FIELDS
        %   S1.SNRe, S1.SNR_C, S2.SNRe, S2.SNR_C
        %
        % EFFECTS
        %   - updates obj.brainReport
        %   - updates obj.sweepSummary
        %   - writes rolling sweep report files if configured
        
            arguments
                obj
                acq (1,1) struct
                pp (1,1) struct
            end
        
            % ------------------------------------------------------------
            % Validate inputs
            % ------------------------------------------------------------
            if ~isfield(pp, 'summary')
                error('Brain:recordPostprocess:MissingSummary', ...
                    'pp must contain a summary field.');
            end
        
            s = pp.summary;
            required = {'S1.SNRe','S1.SNR_C','S2.SNRe','S2.SNR_C'};
            for k = 1:numel(required)
                parts = strsplit(required{k}, '.');
                node  = s;
                for p = 1:numel(parts)
                    if ~isstruct(node) || ~isfield(node, parts{p})
                        error('Brain:recordPostprocess:MissingSummaryField', ...
                            'pp.summary is missing required field: %s', required{k});
                    end
                    node = node.(parts{p});  % dynamic field access, walk deeper
                end
            end
            % ------------------------------------------------------------
            % Extract run metadata
            % ------------------------------------------------------------
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
        
            % ------------------------------------------------------------
            % Compute comparisons
            % ------------------------------------------------------------
            S1_margin = s.S1.SNRe - s.S1.SNR_C;
            S2_margin = s.S2.SNRe - s.S2.SNR_C;
        
            S1_beatsClassical = S1_margin > 0;
            S2_beatsClassical = S2_margin > 0;
        
            anyBeatsClassical  = S1_beatsClassical || S2_beatsClassical;
            bothBeatClassical  = S1_beatsClassical && S2_beatsClassical;
        
            if bothBeatClassical
                flag = "strong";
            elseif anyBeatsClassical
                flag = "partial";
            else
                flag = "none";
            end
        
            % ------------------------------------------------------------
            % Initialize sweep table if needed
            % ------------------------------------------------------------
            if ~isprop(obj, 'brainReport') || isempty(obj.brainReport)
                obj.brainReport = table();
            end
        
            % ------------------------------------------------------------
            % Append one row
            % ------------------------------------------------------------
            newRow = table( ...
                runIndex, ...
                timestampUtc, ...
                runDir, ...
                s.S1.SNRe, ...
                s.S1.SNR_C, ...
                S1_margin, ...
                S1_beatsClassical, ...
                s.S2.SNRe, ...
                s.S2.SNR_C, ...
                S2_margin, ...
                S2_beatsClassical, ...
                anyBeatsClassical, ...
                bothBeatClassical, ...
                flag, ...
                'VariableNames', { ...
                    'runIndex', ...
                    'timestampUtc', ...
                    'runDir', ...
                    'S1.SNRe', ...
                    'S1.SNR_C', ...
                    'S1_margin', ...
                    'S1_beatsClassical', ...
                    'S2.SNRe', ...
                    'S2.SNR_C', ...
                    'S2_margin', ...
                    'S2_beatsClassical', ...
                    'anyBeatsClassical', ...
                    'bothBeatClassical', ...
                    'flag'} ...
                );
        
            obj.brainReport = [obj.brainReport; newRow];
        
            % ------------------------------------------------------------
            % Update summary counters
            % ------------------------------------------------------------
            summary = struct();
            summary.totalRuns = height(obj.brainReport)
            summary.numS1BeatsClassical = sum(obj.brainReport.S1_beatsClassical);
            summary.numS2BeatsClassical = sum(obj.brainReport.S2_beatsClassical);
            summary.numAnyBeatsClassical = sum(obj.brainReport.anyBeatsClassical);
            summary.numBothBeatClassical = sum(obj.brainReport.bothBeatClassical);
        
            if ~isempty(obj.brainReport)
                [~, idxBestS1] = max(obj.brainReport.S1_margin);
                [~, idxBestS2] = max(obj.brainReport.S2_margin);
                [~, idxBestAny] = max(max([obj.brainReport.S1_margin obj.brainReport.S2_margin], [], 2));
        
                summary.bestS1RunIndex = obj.brainReport.runIndex(idxBestS1);
                summary.bestS1Margin = obj.brainReport.S1_margin(idxBestS1);
        
                summary.bestS2RunIndex = obj.brainReport.runIndex(idxBestS2);
                summary.bestS2Margin = obj.brainReport.S2_margin(idxBestS2);
        
                summary.bestAnyRunIndex = obj.brainReport.runIndex(idxBestAny);
                summary.bestAnyFlag = obj.brainReport.flag(idxBestAny);
            else
                summary.bestS1RunIndex = NaN;
                summary.bestS1Margin = NaN;
                summary.bestS2RunIndex = NaN;
                summary.bestS2Margin = NaN;
                summary.bestAnyRunIndex = NaN;
                summary.bestAnyFlag = "";
            end
        
            obj.sweepSummary = summary;
        
            % ------------------------------------------------------------
            % Persist rolling reports
            % ------------------------------------------------------------
            shouldSave = true;
            if isprop(obj, 'cfg') && isfield(obj.cfg, 'brain') && isfield(obj.cfg.brain, 'saveSweepSummary')
                shouldSave = logical(obj.cfg.brain.saveSweepSummary);
            end
        
            if shouldSave
                writeSweepTrackingFiles(obj);
            end
        end

        function writeSweepTrackingFiles(obj)
        % Write rolling sweep tracking artifacts to disk.
        
            if ~isprop(obj, 'cfg') || ~isfield(obj.cfg, 'storage') || ~isfield(obj.cfg.storage, 'rootDir')
                warning('Brain:writeSweepTrackingFiles:MissingRootDir', ...
                    'Could not save sweep tracking files because cfg.storage.rootDir is missing.');
                return;
            end
        
            rootDir = string(obj.cfg.storage.rootDir);
            if strlength(rootDir) == 0
                warning('Brain:writeSweepTrackingFiles:EmptyRootDir', ...
                    'Could not save sweep tracking files because cfg.storage.rootDir is empty.');
                return;
            end
        
            if ~exist(rootDir, 'dir')
                mkdir(rootDir);
            end
        
            T = obj.brainReport;
            S = obj.sweepSummary;
        
            % CSV
            csvPath = fullfile(rootDir, 'sweep_tracking.csv');
            writetable(T, csvPath);
        
            % MAT
            matPath = fullfile(rootDir, 'sweep_tracking.mat');
            brainReport = T; %#ok<NASGU>
            sweepSummary = S; %#ok<NASGU>
            save(matPath, 'brainReport', 'sweepSummary', '-v7.3');
        
            % JSON
            jsonPath = fullfile(rootDir, 'sweep_tracking.json');
            jsonStruct = struct();
            jsonStruct.summary = S;
            jsonStruct.rows = skull.Brain.tableToStructArray(T);
        
            fid = fopen(jsonPath, 'w');
            assert(fid >= 0, 'Could not open JSON file for writing: %s', jsonPath);
            c = onCleanup(@() fclose(fid));
            fprintf(fid, '%s', jsonencode(jsonStruct, 'PrettyPrint', true));
        
            % TXT flagged-runs report
            txtPath = fullfile(rootDir, 'sweep_flagged_runs.txt');
            fid = fopen(txtPath, 'w');
            assert(fid >= 0, 'Could not open TXT file for writing: %s', txtPath);
            c2 = onCleanup(@() fclose(fid));
        
            fprintf(fid, 'Sweep Flagged Runs Report\n');
            fprintf(fid, '=========================\n\n');
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
                    fprintf(fid, 'Run %-6g | %-7s | S1 margin = %+0.6g | S2 margin = %+0.6g | %s\n', ...
                        flagged.runIndex(i), ...
                        flagged.flag(i), ...
                        flagged.S1_margin(i), ...
                        flagged.S2_margin(i), ...
                        flagged.runDir(i));
                end
            end
        end


    end
end

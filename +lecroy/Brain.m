classdef Brain < handle
    % lecroy.Brain  Simple sweep controller for acquisition + post-processing.
    %
    % The Brain object runs repeated single acquisitions until the configured
    % runDurationSeconds expires. It updates runIndex each pass and can call
    % the refactored post-processing function after each acquisition.

    properties
        cfg
        history
        startedAt
        finishedAt
        elapsedSeconds double = 0
    end

    methods
        function obj = Brain(cfg)
            obj.cfg = cfg;
            obj.history = struct('runIndex', {}, 'runFolder', {}, 'acquisition', {}, 'processing', {}, 'error', {});
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
                entry.runFolder = "";
                entry.acquisition = [];
                entry.processing = [];
                entry.error = "";

                try
                    acq = lecroy.acquireRun(cfgIter);
                    entry.acquisition = acq;
                    entry.runFolder = string(acq.runFolder);

                    if isfield(cfgIter, 'postprocess') && cfgIter.brain.processAfterAcquire
                        ppCfg = cfgIter.postprocess;
                        ppCfg.runIndex = runIndex;
                        ppCfg.runFolder = string(acq.runFolder);
                        proc = postprocess.processRun(acq.runFolder, ppCfg);
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
                if obj.cfg.brain.pauseBetweenRunsSeconds > 0
                    pause(obj.cfg.brain.pauseBetweenRunsSeconds);
                end
            end

            obj.finishedAt = datetime('now');
            obj.elapsedSeconds = toc(t0);
            obj.writeSweepSummary();
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
            summary.runFolders = arrayfun(@(x) string(x.runFolder), obj.history, 'UniformOutput', false);

            outDir = obj.cfg.storage.rootDir;
            if ~exist(outDir, 'dir')
                mkdir(outDir);
            end
            stamp = datestr(now, 'yyyymmdd_HHMMSS');
            save(fullfile(outDir, sprintf('brain_sweep_%s.mat', stamp)), 'summary', '-v7.3');
            lecroy.writeJson(fullfile(outDir, sprintf('brain_sweep_%s.json', stamp)), summary);
        end
    end
end

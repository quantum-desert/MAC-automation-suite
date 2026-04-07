% clear old visadev objects
clear all;

addpath(fileparts(fileparts(mfilename('fullpath'))));


cfg = lecroy.defaultConfig();
cfg.storage.rootDir = fullfile(pwd, 'captures');
cfg = lecroy.updateConfig(cfg);


% ---- establish session
session = [];
try
    session = lecroy.connect(cfg);
    
    if cfg.acquisition.stopBeforeSetup
        lecroy.tryWriteLine(session, "STOP");
    end
    
    if cfg.acquisition.clearSweeps
        lecroy.tryWriteLine(session, "CLSW");
    end
    
    % Optional user setup commands before arming
    lecroy.runCommandList(session, cfg.acquisition.setupCommands);
    
    % Arm acquisition if requested
    switch lower(string(cfg.acquisition.acquireMode))
        case "single"
            lecroy.tryWriteLine(session, "TRMD SINGLE");
            lecroy.waitForAcquisitionComplete(session, cfg.acquisition.waitTimeoutSeconds);
        otherwise
            error("lecroy.acquireRun:UnsupportedAcquireMode", ...
                "Unsupported acquireMode: %s", cfg.acquisition.acquireMode);
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


% Configure the sweep timer here.
minutes=1;
cfg.brain.runDurationSeconds = floor(60*minutes);
cfg.brain.pauseBetweenRunsSeconds = 1;
cfg.brain.processAfterAcquire = true;

% Keep the refactored post-processing behavior close to the original script.
cfg.postprocess = postprocess.defaultConfig(cfg.storage.rootDir);
cfg.postprocess.processing.makePlots = false;
cfg.postprocess.processing.shorten = 1;

history = lecroy.runSweep(cfg,session); %#ok<NASGU>

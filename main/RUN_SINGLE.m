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

    % arm
    lecroy.setupTrigger(cfg,session);
    
catch ME
        if ~isempty(session)
            try
                clear session %#ok<NASGU>
            catch
            end
        end
        rethrow(ME);
end



cfg.brain.pauseBetweenRunsSeconds = 1;
cfg.brain.processAfterAcquire = true;

% Keep the refactored post-processing behavior close to the original script.
cfg.postprocess = postprocess.defaultConfig(cfg.storage.rootDir);
% cfg.postprocess.processing.makePlots = false;
cfg.postprocess.processing.shorten = 1;

history = lecroy.runSingle(cfg,session); %#ok<NASGU>

% clear old visadev objects
clear all;

addpath(fileparts(fileparts(mfilename('fullpath'))));


cfg = lecroy.defaultConfigLC();
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



% Configure the sweep timer here
hours=5;
minutes=60*hours;
cfg.brain.runDurationSeconds = floor(60*minutes);
cfg.brain.pauseBetweenRunsSeconds = 1;
cfg.brain.processAfterAcquire = true;

% Keep the refactored post-processing behavior close to the original script.
cfg.postprocess = postprocess.defaultConfigPP(cfg.storage.rootDir);
cfg.postprocess.processing.makePlots = false;
cfg.postprocess.processing.show_SNR = false;
cfg.postprocess.processing.shorten = 1;

% 1010 versus PN15 mod selection here
cfg.postprocess.processing.deterministic = true;
% ----

% Optional per-channel overrides:
% bit rate:
% cfg.postprocess.constantsByChannel.S1.Rb = 16e3;
% cfg.postprocess.constantsByChannel.S2.Rb = 12e3;
% theory mode-count basis for SNR_C/SNR_Q (shared across channels):
% cfg.postprocess.theory.baseRbHz = 4e3;
%
% processing knobs:
% cfg.postprocess.processingByChannel.S1.deterministic = true;
% cfg.postprocess.processingByChannel.S2.deterministic = true;
% cfg.postprocess.processingByChannel.S1.show_SNR = false;
% cfg.postprocess.processingByChannel.S2.show_SNR = false;
% cfg.postprocess.processingByChannel.S1.shorten = 1;
% cfg.postprocess.processingByChannel.S2.shorten = 1;

history = lecroy.runSweep(cfg,session); %#ok<NASGU>

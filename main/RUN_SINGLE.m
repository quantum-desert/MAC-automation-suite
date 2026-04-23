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



cfg.brain.pauseBetweenRunsSeconds = 0;
cfg.brain.processAfterAcquire = true;

% Fast acquisition/storage settings
cfg.acquisition.waitAfterIdleSeconds = 0;
cfg.storage.writeMat = false;
cfg.storage.writeParsedWaveformMat = false;
cfg.storage.writePrettyArtifacts = false;
cfg.storage.writeManifestJson = true;
cfg.transfer.parser.verbose = false;
cfg.transfer.parser.configureEachChannel = false;
cfg.transfer.parser.stopBeforeSetupEachChannel = false;

% Keep the refactored post-processing behavior close to the original script.
cfg.postprocess = postprocess.defaultConfigPP(cfg.storage.rootDir);

% control plot output
cfg.postprocess.processing.makePlots = true;
cfg.postprocess.processing.show_SNR = true;
cfg.postprocess.processing.saveProcessedMat = false;
cfg.postprocess.processing.saveSummaryJson = true;


% 1010 versus PN15 mod selection here
cfg.postprocess.processing.deterministic = true;
% ----

% Optional per-channel overrides:
% bit rate:
cfg.postprocess.theory.useSharedRbForModes = false; % use channel-specific mode counts
cfg.postprocess.constantsByChannel.S1.Rb = 8e3;
cfg.postprocess.constantsByChannel.S2.Rb = 16e3;
%
% processing knobs:
cfg.postprocess.processingByChannel.S1.deterministic = true;
cfg.postprocess.processingByChannel.S2.deterministic = true;
cfg.postprocess.processingByChannel.S1.show_SNR = true;
cfg.postprocess.processingByChannel.S2.show_SNR = true;

history = lecroy.runSingle(cfg,session); %#ok<NASGU>

% --- indicate finish
% load gong;
% sound(y,Fs);
% system('powershell -c (New-Object Media.SoundPlayer ''C:\Windows\Media\notify.wav'').PlaySync()');

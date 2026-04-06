% Example: time-bounded automated sweep controlled by lecroy.Brain
addpath(genpath(fileparts(mfilename('fullpath'))));

cfg = lecroy.defaultConfig();
cfg.connection.resource = "USB0::0x0000::0x0000::INSTR"; % replace me
cfg.storage.rootDir = fullfile(pwd, 'data');

% Configure the sweep timer here.
cfg.brain.runDurationSeconds = 300;
cfg.brain.pauseBetweenRunsSeconds = 1;
cfg.brain.processAfterAcquire = true;

% Keep the refactored post-processing behavior close to the original script.
cfg.postprocess = postprocess.defaultConfig(cfg.storage.rootDir);
cfg.postprocess.processing.makePlots = false;
cfg.postprocess.processing.shorten = 1;

history = lecroy.runSweep(cfg); %#ok<NASGU>

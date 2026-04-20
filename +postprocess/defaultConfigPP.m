function cfg = defaultConfigPP(runFolder)
% postprocess.defaultConfig  Minimal config for refactored post-processing.

if nargin < 1
    runFolder = pwd;
end

cfg = struct();
cfg.runFolder = string(runFolder);
cfg.runIndex = 0;
cfg.recordName = "scope";

cfg.constants = postprocess.defaultConstants();
cfg.phys_constants = postprocess.defaultPhysConstants();

cfg.processing = struct();
cfg.processing.shorten = 1;
cfg.processing.makePlots = 1;
cfg.processing.saveProcessedMat = true;
cfg.processing.saveSummaryJson = true;

% 1010 versus PN15 mod selection here
cfg.processing.deterministic = false;
% ----

cfg.processing.show_SNR=false;

cfg.physics = struct();

cfg.physics.S1 = struct( ...
    'date', datetime("today"), ...
    'kappa', 2.6E-2, ...
    'kappa_I', 0.94, ...
    'eta_signal_col_CWDM', 0.62, ...
    'P_SPDC', 117E-12, ...
    'NE', 806, ...
    'P_b', 2451e-6, ...
    'comments', "Channel 1 physics package");

cfg.physics.S2 = struct( ...
    'date', datetime("today"), ...
    'kappa', 2.2E-2, ...
    'kappa_I', 0.94, ...
    'eta_signal_col_CWDM', 0.4748, ...
    'P_SPDC', 90E-12, ...
    'NE', 806, ...
    'P_b',2451e-6, ...
    'comments', "Channel 2 physics package");




cfg.channels = struct();
cfg.channels.S1 = struct('label', "S1", 'homodyneChannel', 2, 'modChannel', 1);
cfg.channels.S2 = struct('label', "S2", 'homodyneChannel', 3, 'modChannel', 4);
end

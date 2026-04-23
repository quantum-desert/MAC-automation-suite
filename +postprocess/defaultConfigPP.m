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

% Optional per-channel constant overrides (applied on top of cfg.constants).
% Primary use: independent bit-rate per channel via .Rb.
cfg.constantsByChannel = struct();
cfg.constantsByChannel.S1 = struct('Rb', cfg.constants.Rb);
cfg.constantsByChannel.S2 = struct('Rb', cfg.constants.Rb);

% Theoretical SNR mode-count basis.
% This Rb is used for classical/theory mode counting in build_physics,
% independent of channel-specific processing bit rates.
cfg.theory = struct();
cfg.theory.baseRbHz = 16e3;

cfg.processing = struct();
cfg.processing.makePlots = 1;
cfg.processing.saveProcessedMat = true;
cfg.processing.saveSummaryJson = true;

% 1010 versus PN15 mod selection here
cfg.processing.deterministic = true;
% ----

cfg.processing.show_SNR=false;

% Optional per-channel processing overrides (applied on top of cfg.processing).
% Leave empty to use shared/global processing settings.
cfg.processingByChannel = struct();
cfg.processingByChannel.S1 = struct();
cfg.processingByChannel.S2 = struct();

cfg.physics = struct();
P_b =2523e-6; % noise power (W)

cfg.physics.S1 = struct( ...
    'date', datetime("today"), ...
    'kappa', 2.6E-2, ...
    'kappa_I', 0.94, ...
    'eta_signal_col_CWDM', 0.62, ...
    'P_SPDC', 105E-12, ...
    'NE', 806, ...
    'P_b', P_b, ...
    'comments', "Channel 1 physics package");

cfg.physics.S2 = struct( ...
    'date', datetime("today"), ...
    'kappa', 2.2E-2, ...
    'kappa_I', 0.94, ...
    'eta_signal_col_CWDM', 0.4748, ...
    'P_SPDC', 88E-12, ...
    'NE', 806, ...
    'P_b',P_b, ...
    'comments', "Channel 2 physics package");




cfg.channels = struct();
cfg.channels.S1 = struct('label', "S1", 'homodyneChannel', 2, 'modChannel', 1);
cfg.channels.S2 = struct('label', "S2", 'homodyneChannel', 3, 'modChannel', 4);
end

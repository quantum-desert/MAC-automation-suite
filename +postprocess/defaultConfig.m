function cfg = defaultConfig(runFolder)
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
cfg.processing.makePlots = false;
cfg.processing.saveProcessedMat = true;
cfg.processing.saveSummaryJson = true;

cfg.physics = struct();
cfg.physics.file1 = string(fullfile(runFolder, '..', 'PHYS_1.txt'));
cfg.physics.file2 = string(fullfile(runFolder, '..', 'PHYS_2.txt'));

cfg.channels = struct();
cfg.channels.S1 = struct('label', "S1", 'homodyneChannel', 2, 'modChannel', 1);
cfg.channels.S2 = struct('label', "S2", 'homodyneChannel', 3, 'modChannel', 4);
end

function result = processRun(runFolder, cfg)
% postprocess.processRun  Minimal refactor of the original script into a callable function.
%
% The processing order and helper logic are intentionally kept close to the
% uploaded code: build filenames -> preprocess_data -> matched_downsample ->
% optional visualize -> build_physics -> display report.

if nargin < 2 || isempty(cfg)
    cfg = postprocess.defaultConfig(runFolder);
else
    cfg.runFolder = string(runFolder);
end

[fnames_S1, fnames_S2] = postprocess.buildRunFilenames(cfg);

shorten = cfg.processing.shorten;
tank_S1 = postprocess.preprocess_data(fnames_S1,cfg.constants,shorten);
tank_S2 = postprocess.preprocess_data(fnames_S2,cfg.constants,shorten);

tank_S1 = postprocess.matched_downsample(cfg.constants,tank_S1);
tank_S2 = postprocess.matched_downsample(cfg.constants,tank_S2);

if cfg.processing.makePlots
    postprocess.visualize_v2(tank_S1,cfg.constants);
    postprocess.visualize_v2(tank_S2,cfg.constants);
end

phys1 = postprocess.build_physics(cfg.physics.file1,cfg.phys_constants,cfg.constants);
phys2 = postprocess.build_physics(cfg.physics.file2,cfg.phys_constants,cfg.constants);
summary = postprocess.displayReport(tank_S1, tank_S2, phys1, phys2);

result = struct();
result.runFolder = string(runFolder);
result.cfg = cfg;
result.tank_S1 = tank_S1;
result.tank_S2 = tank_S2;
result.phys1 = phys1;
result.phys2 = phys2;
result.summary = summary;

if cfg.processing.saveProcessedMat
    save(fullfile(runFolder, 'processed.mat'), 'result', '-v7.3');
end

if cfg.processing.saveSummaryJson
    postprocess.writeSummaryJson(fullfile(runFolder, 'processed_summary.json'), summary);
end
end

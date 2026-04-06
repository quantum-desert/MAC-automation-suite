function [fnames_S1, fnames_S2] = buildRunFilenames(cfg)
% postprocess.buildRunFilenames  Preserve the original scope_<iter>_<ch>.csv naming.

iter = num2str(cfg.runIndex);
runFolder = char(cfg.runFolder);
recordName = char(cfg.recordName);

fnames_S1 = struct;
fnames_S1.label = char(cfg.channels.S1.label);
fnames_S1.homodyne = fullfile(runFolder, sprintf('%s_%s_%d.csv', recordName, iter, cfg.channels.S1.homodyneChannel));
fnames_S1.mod = fullfile(runFolder, sprintf('%s_%s_%d.csv', recordName, iter, cfg.channels.S1.modChannel));

fnames_S2 = struct;
fnames_S2.label = char(cfg.channels.S2.label);
fnames_S2.homodyne = fullfile(runFolder, sprintf('%s_%s_%d.csv', recordName, iter, cfg.channels.S2.homodyneChannel));
fnames_S2.mod = fullfile(runFolder, sprintf('%s_%s_%d.csv', recordName, iter, cfg.channels.S2.modChannel));
end

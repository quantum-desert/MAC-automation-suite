function result = processRun(runFolder, cfg)
% postprocess.processRun  Minimal refactor of the original script into a callable function.
%
% The processing order and helper logic are intentionally kept close to the
% uploaded code: build filenames -> preprocess_data -> matched_downsample ->
% optional visualize -> build_physics -> display report.

if nargin < 2 || isempty(cfg)
    cfg = postprocess.defaultConfigPP(runFolder);
else
    cfg.runFolder = string(runFolder);
end

[fnames_S1, fnames_S2] = postprocess.buildRunFilenames(cfg);

procGlobal = normalizeProcessingStruct(cfg.processing);

constants_S1 = applyChannelOverrides(cfg.constants, cfg, 'constantsByChannel', 'S1');
constants_S2 = applyChannelOverrides(cfg.constants, cfg, 'constantsByChannel', 'S2');

processing_S1 = normalizeProcessingStruct(applyChannelOverrides(procGlobal, cfg, 'processingByChannel', 'S1'));
processing_S2 = normalizeProcessingStruct(applyChannelOverrides(procGlobal, cfg, 'processingByChannel', 'S2'));

constants_theory_S1 = constants_S1;
constants_theory_S2 = constants_S2;
theoryUseSharedRb = false;
theoryRbHz = NaN;
if isfield(cfg, 'theory') && isstruct(cfg.theory)
    if isfield(cfg.theory, 'useSharedRbForModes') && logical(cfg.theory.useSharedRbForModes)
        theoryUseSharedRb = true;
    end
    if isfield(cfg.theory, 'baseRbHz') && ~isempty(cfg.theory.baseRbHz)
        theoryRbHz = cfg.theory.baseRbHz;
    end
end

if theoryUseSharedRb
    if ~isfinite(theoryRbHz)
        theoryRbHz = cfg.constants.Rb;
    end
    constants_theory_S1.Rb = theoryRbHz;
    constants_theory_S2.Rb = theoryRbHz;
else
    theoryRbHz = NaN;
end

tank_S1 = postprocess.preprocess_data(fnames_S1, constants_S1);
tank_S2 = postprocess.preprocess_data(fnames_S2, constants_S2);

tank_S1 = postprocess.matched_downsample(constants_S1, tank_S1, processing_S1.deterministic, processing_S1.show_SNR);
tank_S2 = postprocess.matched_downsample(constants_S2, tank_S2, processing_S2.deterministic, processing_S2.show_SNR);

if processing_S1.makePlots
    postprocess.visualize_v2(tank_S1, constants_S1);
end
if processing_S2.makePlots
    postprocess.visualize_v2(tank_S2, constants_S2);
end

phys1 = postprocess.build_physics(cfg.physics.S1, cfg.phys_constants, constants_theory_S1);
phys2 = postprocess.build_physics(cfg.physics.S2, cfg.phys_constants, constants_theory_S2);
summary = postprocess.displayReport(tank_S1, tank_S2, phys1, phys2);

pp = struct();
pp.runIndex = cfg.runIndex;
pp.S1.SNRe = tank_S1.fit.SNRe;
pp.S1.SNR_C = phys1.SNR_C;
pp.S1.beatsClassical = tank_S1.fit.SNRe > phys1.SNR_C;

pp.S2.SNRe = tank_S2.fit.SNRe;
pp.S2.SNR_C = phys2.SNR_C;
pp.S2.beatsClassical = tank_S2.fit.SNRe > phys2.SNR_C;

pp.anyBeatsClassical = pp.S1.beatsClassical || pp.S2.beatsClassical;
pp.bothBeatClassical = pp.S1.beatsClassical && pp.S2.beatsClassical;

result = struct();
result.runFolder = string(runFolder);
result.cfg = cfg;
result.tank_S1 = tank_S1;
result.tank_S2 = tank_S2;
result.phys1 = phys1;
result.phys2 = phys2;
result.summary = summary;
result.pp = pp;
result.channelConfig = struct('S1', struct('constants', constants_S1, 'processing', processing_S1), ...
                              'S2', struct('constants', constants_S2, 'processing', processing_S2));
result.theoryConfig = struct( ...
    'useSharedRbForModes', theoryUseSharedRb, ...
    'baseRbHz', theoryRbHz, ...
    'constants_S1', constants_theory_S1, ...
    'constants_S2', constants_theory_S2);

if procGlobal.saveProcessedMat
    save(fullfile(runFolder, 'processed.mat'), 'result', '-v7.3');
end

if procGlobal.saveSummaryJson
    postprocess.writeSummaryJson(fullfile(runFolder, 'processed_summary.json'), summary);
end
end

function out = applyChannelOverrides(baseStruct, cfg, overrideFieldName, channelName)
out = baseStruct;
if ~isfield(cfg, overrideFieldName)
    return;
end

channelOverrides = cfg.(overrideFieldName);
if ~isstruct(channelOverrides) || ~isfield(channelOverrides, channelName)
    return;
end

ov = channelOverrides.(channelName);
if ~isstruct(ov)
    return;
end

fields = fieldnames(ov);
for k = 1:numel(fields)
    out.(fields{k}) = ov.(fields{k});
end
end

function p = normalizeProcessingStruct(p)
% Backward-compatibility alias: allow showSNR or show_SNR.
if isfield(p, 'showSNR') && ~isfield(p, 'show_SNR')
    p.show_SNR = p.showSNR;
end

if ~isfield(p, 'show_SNR')
    p.show_SNR = false;
end
if ~isfield(p, 'deterministic')
    p.deterministic = false;
end
if ~isfield(p, 'makePlots')
    p.makePlots = false;
end
if ~isfield(p, 'saveProcessedMat')
    p.saveProcessedMat = true;
end
if ~isfield(p, 'saveSummaryJson')
    p.saveSummaryJson = true;
end
end

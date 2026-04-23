function summary = rate_region_normalized_tool(opts)
% rate_region_normalized_tool
% Compute per-channel and joint soft-decoding rates, then plot rate regions
% normalized by coherent-state bits/use (Eq. 8 individual bounds).
%
% Key features:
% - Selector for S1 and S2 run choice.
% - Default selector mode pulls BEST index from dated batch result JSON files.
% - Supports explicit manual run selection when needed.
% - Optional Fig. 8-style receiver overlays (PCR/OPAR proxy curves).
%
% Example:
%   addpath('/Users/agentatom/Library/CloudStorage/OneDrive-Umich/GraduateSchool/UM/QE_LAB/MAC/codes/MAC-automation-suite/tools');
%   summary = rate_region_normalized_tool;
%
%   opts = struct();
%   opts.date = '4-20-26';
%   opts.batchIds = [1 4];
%   opts.selector.S1 = struct('mode','best_in_batch','batchId',1,'runIndex',NaN);
%   opts.selector.S2 = struct('mode','best_in_batch','batchId',4,'runIndex',NaN);
%   opts.outputDir = pwd;
%   summary = rate_region_normalized_tool(opts);

if nargin < 1 || isempty(opts)
    opts = struct();
end
opts = applyDefaults(opts);

batchDefs = resolveBatchDefs(opts);
allCandidates = collectChannelCandidates(batchDefs);

selS1 = pickChannelCandidate(allCandidates, 'S1', opts.selector.S1, opts);
selS2 = pickChannelCandidate(allCandidates, 'S2', opts.selector.S2, opts);
cmpS1 = compareSelectionToSnreReference(allCandidates, selS1, opts.selector.S1, 'S1');
cmpS2 = compareSelectionToSnreReference(allCandidates, selS2, opts.selector.S2, 'S2');

obs1 = extractChannelObservations(selS1);
obs2 = extractChannelObservations(selS2);

commonDuration = min(obs1.nSymbols/obs1.Rb, obs2.nSymbols/obs2.Rb);
n1 = min(obs1.nSymbols, floor(commonDuration*obs1.Rb));
n2 = min(obs2.nSymbols, floor(commonDuration*obs2.Rb));
if n1 < 100 || n2 < 100
    error('Too few aligned symbols after synchronization windowing.');
end
obs1 = trimObservations(obs1, n1);
obs2 = trimObservations(obs2, n2);

rep1 = evaluateChannel(obs1, opts);
rep2 = evaluateChannel(obs2, opts);
joint = evaluateJointChannel(obs1, obs2, commonDuration, opts);

phys1 = loadChannelPhysics(selS1, 'S1');
phys2 = loadChannelPhysics(selS2, 'S2');
model = mergePhysicsModel(phys1, phys2, opts);
bounds = computePaperBounds(model, rep1.Rb_uses_per_sec, rep2.Rb_uses_per_sec, joint.Rb_uses_per_sec);

normRef = struct( ...
    'S1_coherent_bits_per_use', bounds.eq8.individual.S1.bits_per_use, ...
    'S2_coherent_bits_per_use', bounds.eq8.individual.S2.bits_per_use ...
);

rep1.normalized = struct( ...
    'I_over_coherent_bits_per_use', rep1.mutual_information_bits_per_use / max(normRef.S1_coherent_bits_per_use, eps), ...
    'rate_over_coherent_rate', rep1.rate_bits_per_sec / max(bounds.eq8.individual.S1.rate_bits_per_sec, eps) ...
);
rep2.normalized = struct( ...
    'I_over_coherent_bits_per_use', rep2.mutual_information_bits_per_use / max(normRef.S2_coherent_bits_per_use, eps), ...
    'rate_over_coherent_rate', rep2.rate_bits_per_sec / max(bounds.eq8.individual.S2.rate_bits_per_sec, eps) ...
);

secondary = struct('enabled', false);
if opts.secondaryOverlay.enable
    secondary = computeScenarioOverlay(opts, opts.secondaryOverlay);
end

plotInfo = plotNormalizedRateRegion(bounds, rep1, rep2, joint, opts, secondary);

summary = struct();
summary.generated_utc = char(datetime('now', 'TimeZone', 'UTC', 'Format', "yyyy-MM-dd'T'HH:mm:ss'Z'"));
summary.date = opts.date;
summary.batch_ids = opts.batchIds;
summary.results_mode = opts.resultsMode;
summary.selector = opts.selector;
summary.sync = struct('common_duration_sec', commonDuration, 'n_symbols_S1', n1, 'n_symbols_S2', n2);
summary.selected = struct('S1', selS1, 'S2', selS2);
summary.selection_comparison = struct('S1', cmpS1, 'S2', cmpS2);
summary.physics_model = model;
summary.bounds = bounds;
summary.normalization_reference = normRef;
summary.channels = struct('S1', rep1, 'S2', rep2);
summary.joint = joint;
summary.secondary_overlay = secondary;
summary.normalized_rate_region_plot = plotInfo;
summary.notes = 'Axes use R1/C1_coh and R2/C2_coh. Best/best_in_batch selector uses maximum HW MI margin per channel. Joint MI uses opts.jointMiEstimator.';

writeJson(opts.outputJsonPath, summary);

fprintf('\nNormalized rate-region summary\n');
fprintf('Date: %s | Batches: %s\n', opts.date, mat2str(opts.batchIds));
fprintf('S1 selected: %s run_%05d\n', selS1.batchTag, selS1.run_index);
fprintf('S2 selected: %s run_%05d\n', selS2.batchTag, selS2.run_index);
if cmpS1.index_differs_from_snre
    fprintf('S1 differs from SNRe-best: selected %s run_%05d vs SNRe-best %s run_%05d\n', ...
        selS1.batchTag, selS1.run_index, cmpS1.snre_best.batchTag, cmpS1.snre_best.run_index);
end
if cmpS2.index_differs_from_snre
    fprintf('S2 differs from SNRe-best: selected %s run_%05d vs SNRe-best %s run_%05d\n', ...
        selS2.batchTag, selS2.run_index, cmpS2.snre_best.batchTag, cmpS2.snre_best.run_index);
end
if isfinite(selS1.hw_margin_bits_per_use) && isfinite(selS2.hw_margin_bits_per_use)
    fprintf('HW selection margins (bits/use): S1=%.6f | S2=%.6f\n', selS1.hw_margin_bits_per_use, selS2.hw_margin_bits_per_use);
end
fprintf('I1/C1_coh = %.4f | I2/C2_coh = %.4f\n', rep1.normalized.I_over_coherent_bits_per_use, rep2.normalized.I_over_coherent_bits_per_use);
fprintf('Joint I(X1,X2;Y1,Y2) = %.6f bits/use\n', joint.mutual_information_bits_per_use);
fprintf('Estimators: per-channel=%s | joint=%s\n', rep1.mi_estimator, joint.mi_estimator);
fprintf('Eq.8 coherent bounds (bits/use): C1=%.6f | C2=%.6f | Csum=%.6f\n', ...
    bounds.eq8.individual.S1.bits_per_use, bounds.eq8.individual.S2.bits_per_use, bounds.eq8.sum.bits_per_use);
fprintf('Saved plot: %s\n', opts.plotPngPath);
fprintf('Saved summary: %s\n\n', opts.outputJsonPath);
end

function opts = applyDefaults(opts)
if ~isfield(opts, 'root') || strlength(string(opts.root)) == 0
    opts.root = '/Users/agentatom/Library/CloudStorage/OneDrive-Umich/GraduateSchool/UM/QE_LAB/MAC/data/codex_processing';
end
if ~isfield(opts, 'date') || strlength(string(opts.date)) == 0
    opts.date = '4-20-26';
end
if ~isfield(opts, 'batchIds') || isempty(opts.batchIds)
    opts.batchIds = [1 4];
end
if ~isfield(opts, 'resultsMode') || strlength(string(opts.resultsMode)) == 0
    opts.resultsMode = 'nontrim'; % auto|trim|nontrim
end
if ~isfield(opts, 'selector') || ~isstruct(opts.selector)
    opts.selector = struct();
end
if ~isfield(opts.selector, 'S1') || ~isstruct(opts.selector.S1)
    opts.selector.S1 = struct('mode','best','batchId',NaN,'runIndex',NaN);
end
if ~isfield(opts.selector, 'S2') || ~isstruct(opts.selector.S2)
    opts.selector.S2 = struct('mode','best','batchId',NaN,'runIndex',NaN);
end
opts.selector.S1 = normalizeSelector(opts.selector.S1);
opts.selector.S2 = normalizeSelector(opts.selector.S2);

if ~isfield(opts, 'receiverOverlay') || ~isstruct(opts.receiverOverlay)
    opts.receiverOverlay = struct();
end
opts.receiverOverlay = normalizeReceiverOverlay(opts.receiverOverlay);

if ~isfield(opts, 'secondaryOverlay') || ~isstruct(opts.secondaryOverlay)
    opts.secondaryOverlay = struct();
end
opts.secondaryOverlay = normalizeSecondaryOverlay(opts.secondaryOverlay);

if ~isfield(opts, 'showEAOuterBound') || isempty(opts.showEAOuterBound)
    opts.showEAOuterBound = true;
end
if ~isfield(opts, 'showExperimentalJointRegion') || isempty(opts.showExperimentalJointRegion)
    opts.showExperimentalJointRegion = true;
end
if ~isfield(opts, 'showCoherentConstraintLines') || isempty(opts.showCoherentConstraintLines)
    opts.showCoherentConstraintLines = true;
end
if ~isfield(opts, 'showPolygonClosureLines') || isempty(opts.showPolygonClosureLines)
    opts.showPolygonClosureLines = true;
end
if ~isfield(opts, 'showFigure') || isempty(opts.showFigure)
    opts.showFigure = true;
end

if ~isfield(opts, 'outputDir') || strlength(string(opts.outputDir)) == 0
    opts.outputDir = pwd;
end
if ~isfield(opts, 'outputJsonPath') || strlength(string(opts.outputJsonPath)) == 0
    opts.outputJsonPath = fullfile(char(string(opts.outputDir)), sprintf('normalized_rate_region_summary_%s.json', char(string(opts.date))));
end
if ~isfield(opts, 'plotPngPath') || strlength(string(opts.plotPngPath)) == 0
    opts.plotPngPath = fullfile(char(string(opts.outputDir)), sprintf('normalized_rate_region_%s.png', char(string(opts.date))));
end
if ~isfield(opts, 'plotFigPath') || strlength(string(opts.plotFigPath)) == 0
    opts.plotFigPath = fullfile(char(string(opts.outputDir)), sprintf('normalized_rate_region_%s.fig', char(string(opts.date))));
end

if ~isfield(opts, 'nbMergeMode') || strlength(string(opts.nbMergeMode)) == 0
    opts.nbMergeMode = 'average';
end
if ~isfield(opts, 'tauMode') || strlength(string(opts.tauMode)) == 0
    opts.tauMode = 'sum_kappa';
end
if ~isfield(opts, 'tauOverride') || isempty(opts.tauOverride)
    opts.tauOverride = NaN;
end
if ~isfield(opts, 'miEstimator') || strlength(string(opts.miEstimator)) == 0
    opts.miEstimator = 'hw_hist'; % default going forward
end
if ~isfield(opts, 'hwHistBins') || isempty(opts.hwHistBins)
    opts.hwHistBins = 500;
end
if ~isfield(opts, 'jointMiEstimator') || strlength(string(opts.jointMiEstimator)) == 0
    opts.jointMiEstimator = 'hw_hist_2d'; % default: consistent with HW-style approach
end
if ~isfield(opts, 'hwJointHistBins') || isempty(opts.hwJointHistBins)
    opts.hwJointHistBins = 80;
end

opts.root = char(string(opts.root));
opts.date = char(string(opts.date));
opts.batchIds = unique(double(opts.batchIds), 'stable');
opts.resultsMode = char(lower(string(opts.resultsMode)));
opts.outputJsonPath = char(string(opts.outputJsonPath));
opts.plotPngPath = char(string(opts.plotPngPath));
opts.plotFigPath = char(string(opts.plotFigPath));
opts.nbMergeMode = char(lower(string(opts.nbMergeMode)));
opts.tauMode = char(lower(string(opts.tauMode)));
opts.miEstimator = char(lower(string(opts.miEstimator))); % llr_soft | hw_hist
opts.hwHistBins = double(opts.hwHistBins);
opts.jointMiEstimator = char(lower(string(opts.jointMiEstimator))); % hw_hist_2d | gaussian_soft
opts.hwJointHistBins = max(8, round(double(opts.hwJointHistBins)));
opts.showEAOuterBound = logical(opts.showEAOuterBound);
opts.showExperimentalJointRegion = logical(opts.showExperimentalJointRegion);
opts.showCoherentConstraintLines = logical(opts.showCoherentConstraintLines);
opts.showPolygonClosureLines = logical(opts.showPolygonClosureLines);
opts.showFigure = logical(opts.showFigure);
if opts.showFigure && ~usejava('desktop')
    opts.showFigure = false;
end
end

function so = normalizeSecondaryOverlay(so)
if ~isfield(so, 'enable') || isempty(so.enable)
    so.enable = true;
end
if ~isfield(so, 'date') || strlength(string(so.date)) == 0
    so.date = '4-22-26';
end
if ~isfield(so, 'batchIds') || isempty(so.batchIds)
    so.batchIds = 2;
end
if ~isfield(so, 'resultsMode') || strlength(string(so.resultsMode)) == 0
    so.resultsMode = 'auto';
end
if ~isfield(so, 'label') || strlength(string(so.label)) == 0
    so.label = '4-22 batch 2';
end
if ~isfield(so, 'selector') || ~isstruct(so.selector)
    so.selector = struct();
end
if ~isfield(so.selector, 'S1') || ~isstruct(so.selector.S1)
    so.selector.S1 = struct('mode','best','batchId',NaN,'runIndex',NaN);
end
if ~isfield(so.selector, 'S2') || ~isstruct(so.selector.S2)
    so.selector.S2 = struct('mode','best','batchId',NaN,'runIndex',NaN);
end
so.selector.S1 = normalizeSelector(so.selector.S1);
so.selector.S2 = normalizeSelector(so.selector.S2);

so.enable = logical(so.enable);
so.date = char(string(so.date));
so.batchIds = unique(double(so.batchIds), 'stable');
so.resultsMode = char(lower(string(so.resultsMode)));
so.label = char(string(so.label));
end

function ro = normalizeReceiverOverlay(ro)
if ~isfield(ro, 'enable') || isempty(ro.enable)
    ro.enable = true;
end
if ~isfield(ro, 'showPCR') || isempty(ro.showPCR)
    ro.showPCR = true;
end
if ~isfield(ro, 'showOPAR') || isempty(ro.showOPAR)
    ro.showOPAR = true;
end
if ~isfield(ro, 'method') || strlength(string(ro.method)) == 0
    ro.method = 'ea_gap_interp'; % currently supported: ea_gap_interp
end
if ~isfield(ro, 'alphaSource') || strlength(string(ro.alphaSource)) == 0
    ro.alphaSource = 'auto_from_data'; % auto_from_data | manual
end
if ~isfield(ro, 'alphaBase') || isempty(ro.alphaBase)
    ro.alphaBase = 0.08; % used when alphaSource=manual or auto has no finite estimate
end
if ~isfield(ro, 'alphaOPARFactor') || isempty(ro.alphaOPARFactor)
    ro.alphaOPARFactor = 0.75; % OPAR below PCR
end
if ~isfield(ro, 'alphaPCRFactor') || isempty(ro.alphaPCRFactor)
    ro.alphaPCRFactor = 1.10;
end

ro.enable = logical(ro.enable);
ro.showPCR = logical(ro.showPCR);
ro.showOPAR = logical(ro.showOPAR);
ro.method = char(lower(string(ro.method)));
ro.alphaSource = char(lower(string(ro.alphaSource)));
ro.alphaBase = double(ro.alphaBase);
ro.alphaOPARFactor = double(ro.alphaOPARFactor);
ro.alphaPCRFactor = double(ro.alphaPCRFactor);
end

function s = normalizeSelector(s)
if ~isfield(s, 'mode') || strlength(string(s.mode)) == 0
    s.mode = 'best';
end
if ~isfield(s, 'batchId') || isempty(s.batchId)
    s.batchId = NaN;
end
if ~isfield(s, 'runIndex') || isempty(s.runIndex)
    s.runIndex = NaN;
end
s.mode = char(lower(string(s.mode))); % best|best_in_batch|manual
s.batchId = double(s.batchId);
s.runIndex = double(s.runIndex);
end

function batchDefs = resolveBatchDefs(opts)
dateDir = fullfile(opts.root, opts.date);
if exist(dateDir, 'dir') ~= 7
    error('Date directory not found: %s', dateDir);
end

batchDefs = repmat(struct('id',NaN,'tag','','batchDir','','resultsJson',''), 0, 1);
for i = 1:numel(opts.batchIds)
    bid = opts.batchIds(i);
    bdir = fullfile(dateDir, sprintf('batch_%d', bid));
    if exist(bdir, 'dir') ~= 7
        error('Batch directory not found: %s', bdir);
    end
    rj = resolveResultsJsonInBatch(bdir, opts.resultsMode);
    if strlength(string(rj)) == 0
        error('No results JSON found in %s (mode=%s).', bdir, opts.resultsMode);
    end
    rec = struct('id',bid,'tag',sprintf('B%d',bid),'batchDir',bdir,'resultsJson',rj);
    batchDefs(end+1,1) = rec; %#ok<AGROW>
end
end

function p = resolveResultsJsonInBatch(batchDir, mode)
trim = dir(fullfile(batchDir, 'snr_trim_optimization_results_*.json'));
nontrim = dir(fullfile(batchDir, 'snr_optimization_results_*.json'));
nontrim = nontrim(~contains({nontrim.name}, 'trim'));

switch mode
    case 'trim'
        p = newestFromDir(batchDir, trim);
    case 'nontrim'
        p = newestFromDir(batchDir, nontrim);
    otherwise
        % auto mode: prefer nontrim, then fallback to trim.
        p = newestFromDir(batchDir, nontrim);
        if strlength(string(p)) == 0
            p = newestFromDir(batchDir, trim);
        end
end
end

function p = newestFromDir(baseDir, listing)
if isempty(listing)
    p = '';
    return;
end
[~,k] = max([listing.datenum]);
p = fullfile(baseDir, listing(k).name);
end

function candidates = collectChannelCandidates(batchDefs)
candidates = repmat(emptyCandidate(), 0, 1);
for i = 1:numel(batchDefs)
    res = loadJson(batchDefs(i).resultsJson);
    rootPath = fieldOrChar(res, 'root', '');
    hasPerRun = isfield(res, 'per_run') && isstruct(res.per_run) && ~isempty(res.per_run) ...
        && isfield(res, 'fixed_channel_configs') && isstruct(res.fixed_channel_configs);

    if hasPerRun
        for r = 1:numel(res.per_run)
            runRec = res.per_run(r);
            runIndex = getNumericField(runRec, 'run_index', NaN);
            for ch = {'S1','S2'}
                cname = ch{1};
                if ~isfield(runRec, cname) || ~isfield(res.fixed_channel_configs, cname)
                    continue;
                end
                perCh = runRec.(cname);
                cfg = res.fixed_channel_configs.(cname);
                c = emptyCandidate();
                c.batchId = batchDefs(i).id;
                c.batchTag = batchDefs(i).tag;
                c.batchDir = batchDefs(i).batchDir;
                c.results_json = batchDefs(i).resultsJson;
                c.channel = cname;
                c.root = rootPath;
                c.run_index = runIndex;
                c.snre = getNumericField(perCh, 'snre', NaN);
                c.filter = fieldOrChar(cfg, 'filter', 'none');
                c.detrend = fieldOrChar(cfg, 'detrend', 'none');
                c.clip = fieldOrChar(cfg, 'clip', 'none');
                c.threshold = fieldOrChar(cfg, 'threshold', 'mean');
                c.invert = logical(getNumericField(cfg, 'invert', 0));
                c.metric = fieldOrChar(cfg, 'metric', 'asym_xp');
                c.M = getNumericField(cfg, 'M', NaN);
                c.phase = getNumericField(cfg, 'phase', NaN);
                c.lag = getNumericField(cfg, 'lag', 0);
                c.trim_mode = fieldOrChar(perCh, 'trim_mode', 'none');
                c.trim_points = getNumericField(perCh, 'trim_points', 0);
                c.method = fieldOrChar(perCh, 'method', '');
                candidates(end+1,1) = c; %#ok<AGROW>
            end
        end
    else
        % Fallback for legacy JSONs with only best_by_channel.
        for ch = {'S1','S2'}
            cname = ch{1};
            if ~isfield(res, 'best_by_channel') || ~isfield(res.best_by_channel, cname)
                continue;
            end
            b = res.best_by_channel.(cname);
            c = emptyCandidate();
            c.batchId = batchDefs(i).id;
            c.batchTag = batchDefs(i).tag;
            c.batchDir = batchDefs(i).batchDir;
            c.results_json = batchDefs(i).resultsJson;
            c.channel = cname;
            c.root = rootPath;
            c.run_index = getNumericField(b, 'run_index', NaN);
            c.snre = getNumericField(b, 'snre', NaN);
            c.filter = fieldOrChar(b, 'filter', 'none');
            c.detrend = fieldOrChar(b, 'detrend', 'none');
            c.clip = fieldOrChar(b, 'clip', 'none');
            c.threshold = fieldOrChar(b, 'threshold', 'mean');
            c.invert = logical(getNumericField(b, 'invert', 0));
            c.metric = fieldOrChar(b, 'metric', 'asym_xp');
            c.M = getNumericField(b, 'M', NaN);
            c.phase = getNumericField(b, 'phase', NaN);
            c.lag = getNumericField(b, 'lag', 0);
            c.homo_file = fieldOrChar(b, 'homo_file', '');
            c.mod_file = fieldOrChar(b, 'mod_file', '');
            c.trim_mode = fieldOrChar(b, 'trim_mode', 'none');
            c.trim_points = getNumericField(b, 'trim_points', 0);
            c.method = fieldOrChar(b, 'method', '');
            candidates(end+1,1) = c; %#ok<AGROW>
        end
    end
end

% Deduplicate exact channel+batch+run entries, keeping the first.
if ~isempty(candidates)
    key = arrayfun(@(c) sprintf('%s|%d|%d', c.channel, c.batchId, c.run_index), candidates, 'UniformOutput', false);
    [~, ia] = unique(key, 'stable');
    candidates = candidates(ia);
end
end

function c = emptyCandidate()
c = struct('batchId',NaN,'batchTag','','batchDir','','results_json','','channel','','root','', ...
    'run_index',NaN,'snre',NaN,'filter','','detrend','','clip','','threshold','', ...
    'invert',false,'metric','','M',NaN,'phase',NaN,'lag',NaN,'homo_file','','mod_file','', ...
    'trim_mode','none','trim_points',0,'method','', ...
    'hw_mi_bits_per_use',NaN,'hw_coherent_bits_per_use',NaN,'hw_margin_bits_per_use',NaN);
end

function sel = pickChannelCandidate(candidates, channelName, selector, opts)
mask = arrayfun(@(x) strcmp(x.channel, channelName), candidates);
pool = candidates(mask);
if isempty(pool)
    error('No candidates available for channel %s.', channelName);
end

switch selector.mode
    case 'best'
        if isfinite(selector.batchId)
            pool = pool([pool.batchId] == selector.batchId);
            if isempty(pool)
                error('No %s candidates in batch %d.', channelName, selector.batchId);
            end
        end
        sel = selectBestByHwMargin(pool, channelName, opts);

    case 'best_in_batch'
        if ~isfinite(selector.batchId)
            error('selector.mode=best_in_batch requires selector.batchId for %s.', channelName);
        end
        pool = pool([pool.batchId] == selector.batchId);
        if isempty(pool)
            error('No %s candidates in batch %d.', channelName, selector.batchId);
        end
        sel = selectBestByHwMargin(pool, channelName, opts);

    case 'manual'
        if ~isfinite(selector.batchId) || ~isfinite(selector.runIndex)
            error('selector.mode=manual requires batchId and runIndex for %s.', channelName);
        end
        m = arrayfun(@(x) x.batchId == selector.batchId && x.run_index == selector.runIndex, pool);
        if any(m)
            sel = pool(find(m,1,'first'));
        else
            % fallback: use batch settings from any candidate in this batch and infer files by channel
            bpool = pool([pool.batchId] == selector.batchId);
            if isempty(bpool)
                error('Manual selection failed: no %s candidate in batch %d.', channelName, selector.batchId);
            end
            sel = bpool(1);
            sel.run_index = selector.runIndex;
        end

    otherwise
        error('Unknown selector mode for %s: %s', channelName, selector.mode);
end
end

function cmp = compareSelectionToSnreReference(candidates, selected, selector, channelName)
mask = arrayfun(@(x) strcmp(x.channel, channelName), candidates);
pool = candidates(mask);
if isempty(pool)
    error('No candidates available for SNRe reference of channel %s.', channelName);
end

switch selector.mode
    case 'best'
        if isfinite(selector.batchId)
            pool = pool([pool.batchId] == selector.batchId);
        end
    case 'best_in_batch'
        pool = pool([pool.batchId] == selector.batchId);
    case 'manual'
        if isfinite(selector.batchId)
            pool = pool([pool.batchId] == selector.batchId);
        end
end
if isempty(pool)
    error('No candidates in comparison pool for channel %s.', channelName);
end

[~,k] = max([pool.snre]);
sn = pool(k);
cmp = struct();
cmp.index_differs_from_snre = ~(sn.batchId == selected.batchId && sn.run_index == selected.run_index);
cmp.snre_best = struct( ...
    'batchId', sn.batchId, ...
    'batchTag', sn.batchTag, ...
    'run_index', sn.run_index, ...
    'snre', sn.snre, ...
    'trim_mode', sn.trim_mode, ...
    'trim_points', sn.trim_points ...
);
cmp.selected = struct( ...
    'batchId', selected.batchId, ...
    'batchTag', selected.batchTag, ...
    'run_index', selected.run_index, ...
    'hw_margin_bits_per_use', selected.hw_margin_bits_per_use, ...
    'trim_mode', selected.trim_mode, ...
    'trim_points', selected.trim_points ...
);
end

function ov = computeScenarioOverlay(opts, so)
ovOpts = opts;
ovOpts.date = so.date;
ovOpts.batchIds = so.batchIds;
ovOpts.resultsMode = so.resultsMode;
ovOpts.selector = so.selector;

batchDefs = resolveBatchDefs(ovOpts);
allCandidates = collectChannelCandidates(batchDefs);

selS1 = pickChannelCandidate(allCandidates, 'S1', ovOpts.selector.S1, ovOpts);
selS2 = pickChannelCandidate(allCandidates, 'S2', ovOpts.selector.S2, ovOpts);
cmpS1 = compareSelectionToSnreReference(allCandidates, selS1, ovOpts.selector.S1, 'S1');
cmpS2 = compareSelectionToSnreReference(allCandidates, selS2, ovOpts.selector.S2, 'S2');

obs1 = extractChannelObservations(selS1);
obs2 = extractChannelObservations(selS2);

commonDuration = min(obs1.nSymbols/obs1.Rb, obs2.nSymbols/obs2.Rb);
n1 = min(obs1.nSymbols, floor(commonDuration*obs1.Rb));
n2 = min(obs2.nSymbols, floor(commonDuration*obs2.Rb));
if n1 < 100 || n2 < 100
    error('Secondary overlay has too few aligned symbols after synchronization windowing.');
end
obs1 = trimObservations(obs1, n1);
obs2 = trimObservations(obs2, n2);

rep1 = evaluateChannel(obs1, ovOpts);
rep2 = evaluateChannel(obs2, ovOpts);
joint = evaluateJointChannel(obs1, obs2, commonDuration, ovOpts);

phys1 = loadChannelPhysics(selS1, 'S1');
phys2 = loadChannelPhysics(selS2, 'S2');
model = mergePhysicsModel(phys1, phys2, ovOpts);
bounds = computePaperBounds(model, rep1.Rb_uses_per_sec, rep2.Rb_uses_per_sec, joint.Rb_uses_per_sec);

rep1.normalized = struct( ...
    'I_over_coherent_bits_per_use', rep1.mutual_information_bits_per_use / max(bounds.eq8.individual.S1.bits_per_use, eps), ...
    'rate_over_coherent_rate', rep1.rate_bits_per_sec / max(bounds.eq8.individual.S1.rate_bits_per_sec, eps) ...
);
rep2.normalized = struct( ...
    'I_over_coherent_bits_per_use', rep2.mutual_information_bits_per_use / max(bounds.eq8.individual.S2.bits_per_use, eps), ...
    'rate_over_coherent_rate', rep2.rate_bits_per_sec / max(bounds.eq8.individual.S2.rate_bits_per_sec, eps) ...
);

ov = struct();
ov.enabled = true;
ov.label = so.label;
ov.date = ovOpts.date;
ov.batch_ids = ovOpts.batchIds;
ov.results_mode = ovOpts.resultsMode;
ov.selector = ovOpts.selector;
ov.sync = struct('common_duration_sec', commonDuration, 'n_symbols_S1', n1, 'n_symbols_S2', n2);
ov.selected = struct('S1', selS1, 'S2', selS2);
ov.selection_comparison = struct('S1', cmpS1, 'S2', cmpS2);
ov.physics_model = model;
ov.bounds = bounds;
ov.channels = struct('S1', rep1, 'S2', rep2);
ov.joint = joint;
end

function sel = selectBestByHwMargin(pool, channelName, opts)
bestIdx = NaN;
bestMargin = -inf;
for i = 1:numel(pool)
    [mi, coh, margin] = scoreCandidateHwMargin(pool(i), channelName, opts);
    pool(i).hw_mi_bits_per_use = mi;
    pool(i).hw_coherent_bits_per_use = coh;
    pool(i).hw_margin_bits_per_use = margin;
    if margin > bestMargin
        bestMargin = margin;
        bestIdx = i;
    end
end
if ~isfinite(bestIdx)
    error('Failed to select %s candidate by HW-MI margin.', channelName);
end
sel = pool(bestIdx);
end

function [miBitsUse, cohBitsUse, marginBitsUse] = scoreCandidateHwMargin(cand, channelName, opts)
obs = extractChannelObservations(cand);
miBitsUse = hwStyleMutualInformation(obs.y(:), obs.bits(:), opts.hwHistBins);
phys = loadChannelPhysics(cand, channelName);
cohBitsUse = coherentSingleEq8BitsUse(phys.kappa, phys.NS, phys.NB, phys.Modes);
marginBitsUse = miBitsUse - cohBitsUse;
end

function c = coherentSingleEq8BitsUse(kappa, NS, NB, modesPerUse)
c = (bosonicEntropy(kappa*NS + NB) - bosonicEntropy(NB)) * modesPerUse;
end

function obs = extractChannelObservations(cand)
runDir = resolveRunDir(cand);
homoPath = resolveScopePath(runDir, cand.homo_file, cand.channel, true);
modPath = resolveScopePath(runDir, cand.mod_file, cand.channel, false);

[tH, yRaw] = readScopeCsv(homoPath);
[tM, mRaw] = readScopeCsv(modPath);
L = min([numel(tH), numel(tM), numel(yRaw), numel(mRaw)]);

if L < 200
    error('Insufficient raw points for %s run_%05d.', cand.channel, cand.run_index);
end

t = tH(1:L);
y = yRaw(1:L);
m = mRaw(1:L);

[t, y, m] = applyRawTrim(t, y, m, cand.trim_mode, cand.trim_points);
L2 = min([numel(t), numel(y), numel(m)]);
if L2 < 200
    error('Insufficient points after trim for %s run_%05d.', cand.channel, cand.run_index);
end
t = t(1:L2);
y = y(1:L2);
m = m(1:L2);

fs = 1.0 / mean(diff(t));
Rb = fs / cand.M;

y = y - mean(y);
y = applyFilterByName(y, fs, Rb, cand.filter);
y = applyDetrendByName(y, cand.detrend, cand.M);
y = applyClipByName(y, cand.clip);

[yLag, mLag] = applyLag(y, m, cand.lag);
startIdx = cand.phase + 1;
if startIdx < 1 || startIdx > cand.M
    error('Invalid phase for %s run_%05d.', cand.channel, cand.run_index);
end

yS = yLag(startIdx:cand.M:end);
mS = mLag(startIdx:cand.M:end);
n = min(numel(yS), numel(mS));
yS = yS(1:n);
mS = mS(1:n);

if strcmp(cand.threshold, 'median')
    th = median(mS);
else
    th = mean(mS);
end
bits = mS > th;
if cand.invert
    bits = ~bits;
end

obs = struct();
obs.channel = cand.channel;
obs.batchId = cand.batchId;
obs.batchTag = cand.batchTag;
obs.run_index = cand.run_index;
obs.run_dir = runDir;
obs.fs = fs;
obs.Rb = Rb;
obs.nSymbols = n;
obs.y = yS(:);
obs.bits = logical(bits(:));
obs.class_balance = mean(bits);
obs.settings = struct('M',cand.M,'phase',cand.phase,'lag',cand.lag,'filter',cand.filter, ...
    'detrend',cand.detrend,'clip',cand.clip,'threshold',cand.threshold,'invert',cand.invert, ...
    'trim_mode',cand.trim_mode,'trim_points',cand.trim_points);
end

function out = trimObservations(in, nUse)
out = in;
out.y = in.y(1:nUse);
out.bits = in.bits(1:nUse);
out.nSymbols = nUse;
out.class_balance = mean(out.bits);
end

function rep = evaluateChannel(obs, opts)
y = obs.y(:);
bits = obs.bits(:);

x1 = y(bits);
x0 = y(~bits);
mu0 = mean(x0); mu1 = mean(x1);
s0 = std(x0, 0); s1 = std(x1, 0);

switch opts.miEstimator
    case 'llr_soft'
        [I, rate] = llrMutualInformation(y, bits, mu0, s0, mu1, s1, obs.Rb);
        estimator = 'llr_soft';
    case 'hw_hist'
        I = hwStyleMutualInformation(y, bits, opts.hwHistBins);
        rate = I * obs.Rb;
        estimator = 'hw_hist';
    otherwise
        error('Unknown miEstimator: %s', opts.miEstimator);
end

rep = struct();
rep.channel = obs.channel;
rep.batchTag = obs.batchTag;
rep.run_index = obs.run_index;
rep.Rb_uses_per_sec = obs.Rb;
rep.n_symbols = obs.nSymbols;
rep.class_balance = obs.class_balance;
rep.fit = struct('mu0',mu0,'sigma0',s0,'mu1',mu1,'sigma1',s1);
rep.mutual_information_bits_per_use = I;
rep.rate_bits_per_sec = rate;
rep.mi_estimator = estimator;
if strcmp(estimator, 'hw_hist')
    rep.hw_hist_bins = opts.hwHistBins;
end
end

function rep = evaluateJointChannel(obs1, obs2, commonDuration, opts)
n = min(obs1.nSymbols, obs2.nSymbols);
Y = [obs1.y(1:n), obs2.y(1:n)];
X1 = obs1.bits(1:n);
X2 = obs2.bits(1:n);

state = double(X1) + 2*double(X2) + 1;
pri = zeros(4,1);
for k = 1:4
    pri(k) = sum(state==k)/n;
end

switch opts.jointMiEstimator
    case 'hw_hist_2d'
        I = hwStyleJointMutualInformation(Y, state, opts.hwJointHistBins);
        jointEstimator = 'hw_hist_2d';
    case 'gaussian_soft'
        I = gaussianJointMutualInformation(Y, state);
        jointEstimator = 'gaussian_soft';
    otherwise
        error('Unknown jointMiEstimator: %s', opts.jointMiEstimator);
end

if commonDuration <= 0
    Rb = min(obs1.Rb, obs2.Rb);
else
    Rb = n/commonDuration;
end

rep = struct();
rep.n_symbols = n;
rep.Rb_uses_per_sec = Rb;
rep.mutual_information_bits_per_use = I;
rep.rate_bits_per_sec = I*Rb;
rep.state_priors = struct('m00',pri(1),'m10',pri(2),'m01',pri(3),'m11',pri(4));
rep.mi_estimator = jointEstimator;
if strcmp(jointEstimator, 'hw_hist_2d')
    rep.hw_joint_hist_bins = opts.hwJointHistBins;
end
end

function I = gaussianJointMutualInformation(Y, state)
n = size(Y,1);
pri = zeros(4,1);
mu = zeros(4,2);
S = zeros(2,2,4);
for k = 1:4
    Yk = Y(state==k,:);
    pri(k) = size(Yk,1)/n;
    if size(Yk,1) < 8
        error('Joint class %d too small for gaussian estimator.', k);
    end
    mu(k,:) = mean(Yk,1);
    C = cov(Yk,1);
    reg = 1e-9 + 1e-6*max(trace(C),1);
    S(:,:,k) = C + reg*eye(2);
end

ll = zeros(n,4);
for k = 1:4
    ll(:,k) = logGaussianPdf(Y, mu(k,:), S(:,:,k));
end
idx = sub2ind([n,4], (1:n)', state);
logTrue = ll(idx);
logMix = logsumexp(ll + log(max(pri',eps)), 2);
I = mean((logTrue - logMix)/log(2));
I = min(max(I,0),2);
end

function I = hwStyleJointMutualInformation(Y, state, nBins)
if size(Y,2) ~= 2
    error('hwStyleJointMutualInformation expects Nx2 observations.');
end
if numel(state) ~= size(Y,1)
    error('State length mismatch in joint MI.');
end
state = state(:);
n = size(Y,1);
if n < 40
    error('Too few symbols for joint histogram MI.');
end

e1 = makeHistEdges(Y(:,1), nBins);
e2 = makeHistEdges(Y(:,2), nBins);

pri = zeros(4,1);
Hcond = zeros(4,1);
for k = 1:4
    mask = (state == k);
    pri(k) = sum(mask) / n;
    if sum(mask) < 8
        error('Joint class %d too small for HW histogram estimator.', k);
    end
    nk = histcounts2(Y(mask,1), Y(mask,2), e1, e2, 'Normalization', 'count');
    pk = nk + eps;
    pk = pk / sum(pk(:));
    Hcond(k) = -sum(pk(:).*log2(pk(:)));
end

nAll = histcounts2(Y(:,1), Y(:,2), e1, e2, 'Normalization', 'count');
pAll = nAll + eps;
pAll = pAll / sum(pAll(:));
H = -sum(pAll(:).*log2(pAll(:)));

I = H - sum(pri .* Hcond);
I = min(max(I,0),2);
end

function phys = loadChannelPhysics(cand, channel)
runDir = resolveRunDir(cand);
matPath = fullfile(runDir, 'processed.mat');
if exist(matPath,'file') ~= 2
    error('Missing processed.mat: %s', matPath);
end
S = load(matPath);
if strcmp(channel, 'S1')
    p = S.result.phys1;
else
    p = S.result.phys2;
end
phys = struct('kappa',double(p.kappa),'NS',double(p.NS),'NB',double(p.NB),'Modes',double(p.Modes));
end

function model = mergePhysicsModel(p1, p2, opts)
model = struct();
model.kappa1 = p1.kappa;
model.kappa2 = p2.kappa;
model.NS1 = p1.NS;
model.NS2 = p2.NS;
model.Modes_per_use = mean([p1.Modes p2.Modes]);

switch opts.nbMergeMode
    case 'average', model.NB = mean([p1.NB p2.NB]);
    case 's1', model.NB = p1.NB;
    case 's2', model.NB = p2.NB;
    case 'min', model.NB = min([p1.NB p2.NB]);
    case 'max', model.NB = max([p1.NB p2.NB]);
    otherwise, error('Unknown nbMergeMode: %s', opts.nbMergeMode);
end

switch opts.tauMode
    case 'sum_kappa'
        model.tau = model.kappa1 + model.kappa2;
    case 'explicit'
        if ~isfinite(opts.tauOverride) || opts.tauOverride <= 0
            error('tauMode=explicit requires positive tauOverride.');
        end
        model.tau = opts.tauOverride;
    otherwise
        error('Unknown tauMode: %s', opts.tauMode);
end

model.eta1 = model.kappa1 / model.tau;
model.eta2 = model.kappa2 / model.tau;
model.NS_mix = model.eta1*model.NS1 + model.eta2*model.NS2;
end

function bounds = computePaperBounds(model, Rb1, Rb2, Rbj)
g = @(x) bosonicEntropy(x);

% Eq. 8
C8_1 = g(model.tau*model.eta1*model.NS1 + model.NB) - g(model.NB);
C8_2 = g(model.tau*model.eta2*model.NS2 + model.NB) - g(model.NB);
C8_s = g(model.tau*model.eta1*model.NS1 + model.tau*model.eta2*model.NS2 + model.NB) - g(model.NB);

% Eq. 9
C9_1 = g(model.tau*model.NS1 + model.NB) - g(model.NB);
C9_2 = g(model.tau*model.NS2 + model.NB) - g(model.NB);

% Eq. 10 and 11 via Eq.18
C10_1 = eaCapacityThermal(model.NS1, model.tau, model.NB);
C10_2 = eaCapacityThermal(model.NS2, model.tau, model.NB);
C11_s = eaCapacityThermal(model.NS_mix, model.tau, model.NB);

bounds = struct();
bounds.eq8 = struct('individual', struct('S1',makeBound(C8_1, model.Modes_per_use, Rb1), 'S2',makeBound(C8_2, model.Modes_per_use, Rb2)), ...
                    'sum', makeBound(C8_s, model.Modes_per_use, Rbj));
bounds.eq9 = struct('individual', struct('S1',makeBound(C9_1, model.Modes_per_use, Rb1), 'S2',makeBound(C9_2, model.Modes_per_use, Rb2)), ...
                    'sum_energetic', makeBound(C8_s, model.Modes_per_use, Rbj));
bounds.eq10 = struct('individual', struct('S1',makeBound(C10_1, model.Modes_per_use, Rb1), 'S2',makeBound(C10_2, model.Modes_per_use, Rb2)));
bounds.eq11 = struct('sum', makeBound(C11_s, model.Modes_per_use, Rbj));
end

function b = makeBound(bitsPerMode, modesPerUse, Rb)
b = struct('bits_per_mode', bitsPerMode, 'bits_per_use', bitsPerMode*modesPerUse, 'rate_bits_per_sec', bitsPerMode*modesPerUse*Rb);
end

function out = plotNormalizedRateRegion(bounds, rep1, rep2, joint, opts, secondary)
if nargin < 6 || isempty(secondary)
    secondary = struct('enabled', false);
end

coh1 = bounds.eq8.individual.S1.bits_per_use;
coh2 = bounds.eq8.individual.S2.bits_per_use;

[e8x, e8y] = normalizedCurve(bounds.eq8.individual.S1.bits_per_use, bounds.eq8.individual.S2.bits_per_use, bounds.eq8.sum.bits_per_use, coh1, coh2);
[ejx, ejy] = normalizedCurve(rep1.mutual_information_bits_per_use, rep2.mutual_information_bits_per_use, ...
    joint.mutual_information_bits_per_use, coh1, coh2);

p1 = rep1.mutual_information_bits_per_use / max(coh1, eps);
p2 = rep2.mutual_information_bits_per_use / max(coh2, eps);

hasSecondary = isfield(secondary, 'enabled') && logical(secondary.enabled);
if hasSecondary
    sc1 = secondary.bounds.eq8.individual.S1.bits_per_use;
    sc2 = secondary.bounds.eq8.individual.S2.bits_per_use;
    [se8x, se8y] = normalizedCurve(secondary.bounds.eq8.individual.S1.bits_per_use, secondary.bounds.eq8.individual.S2.bits_per_use, secondary.bounds.eq8.sum.bits_per_use, sc1, sc2);
    [sejx, sejy] = normalizedCurve(secondary.channels.S1.mutual_information_bits_per_use, secondary.channels.S2.mutual_information_bits_per_use, ...
        secondary.joint.mutual_information_bits_per_use, sc1, sc2);
    sp1 = secondary.channels.S1.mutual_information_bits_per_use / max(sc1, eps);
    sp2 = secondary.channels.S2.mutual_information_bits_per_use / max(sc2, eps);
else
    sc1 = NaN; sc2 = NaN;
    se8x = []; se8y = [];
    sejx = []; sejy = [];
    sp1 = NaN; sp2 = NaN;
end

figVisible = 'off';
if opts.showFigure
    figVisible = 'on';
end
fig = figure('Visible',figVisible,'Color','w','Name','Normalized Rate Region');
ax = axes(fig); hold(ax,'on'); box(ax,'on'); grid(ax,'on');

fill(ax, [e8x fliplr(e8x)], [e8y zeros(size(e8y))], [0.7 0.7 0.7], 'FaceAlpha',0.22, 'EdgeColor','none', 'DisplayName','Eq.8 coherent (normalized)');
plot(ax, e8x, e8y, 'k-', 'LineWidth',1.8, 'DisplayName','Eq.8 boundary');
if opts.showPolygonClosureLines
    drawClosureToOrigin(ax, e8x, e8y, [0 0 0], 1.2);
end
fill(ax, [ejx fliplr(ejx)], [ejy zeros(size(ejy))], [0.00 0.67 0.47], ...
    'FaceAlpha', 0.16, 'EdgeColor', 'none', 'DisplayName', sprintf('Measured joint region (%s)', opts.date));
plot(ax, ejx, ejy, '-', 'Color', [0.00 0.62 0.45], 'LineWidth', 1.6, ...
    'DisplayName', sprintf('Measured joint boundary (%s)', opts.date));
if opts.showPolygonClosureLines
    drawClosureToOrigin(ax, ejx, ejy, [0.00 0.62 0.45], 1.1);
end

scatter(ax, p1, p2, 64, 'filled', 'MarkerFaceColor',[0.49 0.18 0.56], ...
    'DisplayName', sprintf('Measured singles point (%s)', opts.date));

if hasSecondary
    fill(ax, [se8x fliplr(se8x)], [se8y zeros(size(se8y))], [0.96 0.86 0.78], ...
        'FaceAlpha',0.18, 'EdgeColor','none', 'DisplayName', sprintf('Eq.8 coherent (%s)', secondary.label));
    plot(ax, se8x, se8y, '-', 'Color',[0.78 0.33 0.12], 'LineWidth',1.7, ...
        'DisplayName', sprintf('Eq.8 boundary (%s)', secondary.label));
    if opts.showPolygonClosureLines
        drawClosureToOrigin(ax, se8x, se8y, [0.78 0.33 0.12], 1.1);
    end

    fill(ax, [sejx fliplr(sejx)], [sejy zeros(size(sejy))], [0.25 0.55 0.95], ...
        'FaceAlpha', 0.14, 'EdgeColor', 'none', 'DisplayName', sprintf('Measured joint region (%s)', secondary.label));
    plot(ax, sejx, sejy, '-', 'Color', [0.10 0.40 0.86], 'LineWidth', 1.5, ...
        'DisplayName', sprintf('Measured joint boundary (%s)', secondary.label));
    if opts.showPolygonClosureLines
        drawClosureToOrigin(ax, sejx, sejy, [0.10 0.40 0.86], 1.0);
    end

    scatter(ax, sp1, sp2, 64, 'filled', 'MarkerFaceColor',[0.07 0.34 0.72], ...
        'DisplayName', sprintf('Measured singles point (%s)', secondary.label));
end

if opts.showCoherentConstraintLines
    xIntDiag = bounds.eq8.sum.bits_per_use / max(coh1, eps);
    yIntDiag = bounds.eq8.sum.bits_per_use / max(coh2, eps);
    xDiag = linspace(0, xIntDiag, 1200);
    yDiag = (bounds.eq8.sum.bits_per_use - coh1*xDiag) ./ max(coh2, eps);
    yDiag = max(yDiag, 0);
    plot(ax, xDiag, yDiag, '--', 'Color', [0.85 0.33 0.10], 'LineWidth', 1.5, ...
        'DisplayName', 'Coherent outer bound: R_1+R_2 <= C_{sum}');
else
    xIntDiag = bounds.eq8.sum.bits_per_use / max(coh1, eps);
    yIntDiag = bounds.eq8.sum.bits_per_use / max(coh2, eps);
end

if hasSecondary
    sxIntDiag = secondary.bounds.eq8.sum.bits_per_use / max(sc1, eps);
    syIntDiag = secondary.bounds.eq8.sum.bits_per_use / max(sc2, eps);
    se8xMax = max(se8x);
    se8yMax = max(se8y);
    sejxMax = max(sejx);
    sejyMax = max(sejy);
    sp1v = sp1;
    sp2v = sp2;
    if opts.showCoherentConstraintLines
        sxDiag = linspace(0, sxIntDiag, 1200);
        syDiag = (secondary.bounds.eq8.sum.bits_per_use - sc1*sxDiag) ./ max(sc2, eps);
        syDiag = max(syDiag, 0);
        plot(ax, sxDiag, syDiag, '--', 'Color', [0.93 0.58 0.20], 'LineWidth', 1.4, ...
            'DisplayName', sprintf('Coherent outer bound (%s)', secondary.label));
    end
else
    sxIntDiag = 0;
    syIntDiag = 0;
    se8xMax = 0;
    se8yMax = 0;
    sejxMax = 0;
    sejyMax = 0;
    sp1v = 0;
    sp2v = 0;
end

ejX = max(ejx);
ejY = max(ejy);
xMax = 1.06*max([max(e8x), ejX, p1, xIntDiag, se8xMax, sejxMax, sp1v, sxIntDiag, 1]);
yMax = 1.06*max([max(e8y), ejY, p2, yIntDiag, se8yMax, sejyMax, sp2v, syIntDiag, 1]);
xlim(ax,[0 xMax]); ylim(ax,[0 yMax]);
xlabel(ax, 'R_1 / C_1^{coh} (bits/use normalized)');
ylabel(ax, 'R_2 / C_2^{coh} (bits/use normalized)');
title(ax, sprintf('Normalized Rate Region (%s)', opts.date));
legend(ax,'Location','northeastoutside');

[pdir,~,~] = fileparts(opts.plotPngPath);
if strlength(string(pdir)) > 0 && exist(pdir,'dir') ~= 7
    mkdir(pdir);
end
[fdir,~,~] = fileparts(opts.plotFigPath);
if strlength(string(fdir)) > 0 && exist(fdir,'dir') ~= 7
    mkdir(fdir);
end

exportgraphics(fig, opts.plotPngPath, 'Resolution', 220);
savefig(fig, opts.plotFigPath);
if ~opts.showFigure
    close(fig);
end

out = struct();
out.png_path = opts.plotPngPath;
out.fig_path = opts.plotFigPath;
out.experimental_normalized_point = struct('R1_over_C1coh', p1, 'R2_over_C2coh', p2);
out.joint_projected_normalized_point = struct('R1_over_C1coh', NaN, 'R2_over_C2coh', NaN);
out.joint_bits_per_use = joint.mutual_information_bits_per_use;
out.eq8_sum_normalized = bounds.eq8.sum.bits_per_use / max(coh1 + coh2, eps);
out.show_ea_outer_bound = false;
out.show_experimental_joint_region = true;
out.show_coherent_constraint_lines = opts.showCoherentConstraintLines;
out.show_polygon_closure_lines = opts.showPolygonClosureLines;
out.show_figure = opts.showFigure;
out.eq8_coherent_bounds_bits_per_use = struct( ...
    'C1', coh1, ...
    'C2', coh2, ...
    'Csum', bounds.eq8.sum.bits_per_use ...
);
out.experimental_joint_region = struct( ...
    'R1_max_over_C1coh', rep1.mutual_information_bits_per_use / max(coh1, eps), ...
    'R2_max_over_C2coh', rep2.mutual_information_bits_per_use / max(coh2, eps), ...
    'sum_bits_per_use', joint.mutual_information_bits_per_use ...
);
out.receiver_overlay = struct('enabled', false, 'note', 'Disabled in minimal coherent-vs-measured view.');
if hasSecondary
    out.secondary_overlay = struct( ...
        'enabled', true, ...
        'label', secondary.label, ...
        'date', secondary.date, ...
        'selected', secondary.selected, ...
        'eq8_coherent_bounds_bits_per_use', struct( ...
            'C1', secondary.bounds.eq8.individual.S1.bits_per_use, ...
            'C2', secondary.bounds.eq8.individual.S2.bits_per_use, ...
            'Csum', secondary.bounds.eq8.sum.bits_per_use ...
        ), ...
        'experimental_normalized_point', struct('R1_over_C1coh', sp1, 'R2_over_C2coh', sp2), ...
        'experimental_joint_region', struct( ...
            'R1_max_over_C1coh', secondary.channels.S1.mutual_information_bits_per_use / max(sc1, eps), ...
            'R2_max_over_C2coh', secondary.channels.S2.mutual_information_bits_per_use / max(sc2, eps), ...
            'sum_bits_per_use', secondary.joint.mutual_information_bits_per_use ...
        ) ...
    );
else
    out.secondary_overlay = struct('enabled', false);
end
end

function [xn, yn] = normalizedCurve(r1, r2, rsum, coh1, coh2)
x = linspace(0, max(min(r1, rsum),0), 1200);
y = max(min(r2, rsum - x),0);
xn = x / max(coh1, eps);
yn = y / max(coh2, eps);
end

function drawClosureToOrigin(ax, x, y, col, lw)
if isempty(x) || isempty(y)
    return;
end
x0 = x(1); y0 = y(1);
x1 = x(end); y1 = y(end);
tol = 1e-12;
plotRoute(ax, x0, y0, col, lw, tol);
plotRoute(ax, x1, y1, col, lw, tol);
end

function plotRoute(ax, x, y, col, lw, tol)
if abs(x) < tol && abs(y) < tol
    return;
end
if abs(x) < tol || abs(y) < tol
    plot(ax, [x 0], [y 0], '-', 'Color', col, 'LineWidth', lw, 'HandleVisibility', 'off');
else
    % Prefer vertical closure first, then horizontal when needed.
    plot(ax, [x x], [y 0], '-', 'Color', col, 'LineWidth', lw, 'HandleVisibility', 'off');
    plot(ax, [x 0], [0 0], '-', 'Color', col, 'LineWidth', lw, 'HandleVisibility', 'off');
end
end

function recv = receiverOverlayCurves(bounds, rep1, rep2, joint, ro, coh1, coh2)
recv = struct();
recv.enable = logical(ro.enable);
recv.hasOPAR = false;
recv.hasPCR = false;
recv.alpha_base = NaN;
recv.alpha_opar = NaN;
recv.alpha_pcr = NaN;
recv.opar = struct('x',[],'y',[]);
recv.pcr = struct('x',[],'y',[]);
recv.xall = 0;
recv.yall = 0;
recv.summary = struct('enabled',logical(ro.enable), ...
    'method',char(string(ro.method)), ...
    'alpha_source',char(string(ro.alphaSource)), ...
    'alpha_base',NaN, ...
    'alpha_opar',NaN, ...
    'alpha_pcr',NaN, ...
    'show_opar',logical(ro.showOPAR), ...
    'show_pcr',logical(ro.showPCR));

if ~ro.enable
    return;
end
if ~strcmp(ro.method, 'ea_gap_interp')
    error('Unknown receiverOverlay.method: %s', ro.method);
end

alphaBase = estimateReceiverAlphaBase(bounds, rep1, rep2, joint, ro);
alphaOPAR = clamp01(alphaBase * ro.alphaOPARFactor);
alphaPCR = clamp01(alphaBase * ro.alphaPCRFactor);

recv.alpha_base = alphaBase;
recv.alpha_opar = alphaOPAR;
recv.alpha_pcr = alphaPCR;

if ro.showOPAR
    r1 = interpolateEaGap(bounds.eq8.individual.S1.bits_per_use, bounds.eq10.individual.S1.bits_per_use, alphaOPAR);
    r2 = interpolateEaGap(bounds.eq8.individual.S2.bits_per_use, bounds.eq10.individual.S2.bits_per_use, alphaOPAR);
    rs = interpolateEaGap(bounds.eq8.sum.bits_per_use, bounds.eq11.sum.bits_per_use, alphaOPAR);
    [xo, yo] = normalizedCurve(r1, r2, rs, coh1, coh2);
    recv.opar = struct('x',xo,'y',yo);
    recv.hasOPAR = true;
end

if ro.showPCR
    r1 = interpolateEaGap(bounds.eq8.individual.S1.bits_per_use, bounds.eq10.individual.S1.bits_per_use, alphaPCR);
    r2 = interpolateEaGap(bounds.eq8.individual.S2.bits_per_use, bounds.eq10.individual.S2.bits_per_use, alphaPCR);
    rs = interpolateEaGap(bounds.eq8.sum.bits_per_use, bounds.eq11.sum.bits_per_use, alphaPCR);
    [xp, yp] = normalizedCurve(r1, r2, rs, coh1, coh2);
    recv.pcr = struct('x',xp,'y',yp);
    recv.hasPCR = true;
end

xall = [];
yall = [];
if recv.hasOPAR
    xall = [xall, recv.opar.x]; %#ok<AGROW>
    yall = [yall, recv.opar.y]; %#ok<AGROW>
end
if recv.hasPCR
    xall = [xall, recv.pcr.x]; %#ok<AGROW>
    yall = [yall, recv.pcr.y]; %#ok<AGROW>
end
if isempty(xall), xall = 0; end
if isempty(yall), yall = 0; end
recv.xall = xall;
recv.yall = yall;

recv.summary.alpha_base = alphaBase;
recv.summary.alpha_opar = alphaOPAR;
recv.summary.alpha_pcr = alphaPCR;
end

function alpha = estimateReceiverAlphaBase(bounds, rep1, rep2, joint, ro)
if strcmp(ro.alphaSource, 'manual')
    alpha = clamp01(ro.alphaBase);
    return;
end
if ~strcmp(ro.alphaSource, 'auto_from_data')
    error('Unknown receiverOverlay.alphaSource: %s', ro.alphaSource);
end

vals = [];
vals(end+1) = normalizedGap(rep1.mutual_information_bits_per_use, bounds.eq8.individual.S1.bits_per_use, bounds.eq10.individual.S1.bits_per_use); %#ok<AGROW>
vals(end+1) = normalizedGap(rep2.mutual_information_bits_per_use, bounds.eq8.individual.S2.bits_per_use, bounds.eq10.individual.S2.bits_per_use); %#ok<AGROW>
vals(end+1) = normalizedGap(joint.mutual_information_bits_per_use, bounds.eq8.sum.bits_per_use, bounds.eq11.sum.bits_per_use); %#ok<AGROW>
vals = vals(isfinite(vals));

if isempty(vals)
    alpha = clamp01(ro.alphaBase);
else
    alpha = clamp01(max(median(vals), ro.alphaBase));
end
end

function g = normalizedGap(x, lo, hi)
d = hi - lo;
if ~isfinite(x) || ~isfinite(lo) || ~isfinite(hi) || d <= 0
    g = NaN;
    return;
end
g = (x - lo) / d;
g = clamp01(g);
end

function y = interpolateEaGap(cohVal, eaVal, alpha)
y = cohVal + clamp01(alpha) * (eaVal - cohVal);
end

function y = clamp01(x)
y = min(max(double(x), 0.0), 1.0);
end

function val = bosonicEntropy(x)
if x < 0
    error('bosonicEntropy input must be non-negative.');
elseif x == 0
    val = 0;
else
    val = (x+1)*log2(x+1) - x*log2(x);
end
end

function ce = eaCapacityThermal(NS, tau, NB)
NSp = tau*NS + NB;
D = sqrt((NS + NSp + 1)^2 - 4*tau*NS*(NS+1));
Aplus = (D - 1 + (NSp - NS))/2;
Aminus = (D - 1 - (NSp - NS))/2;
ce = bosonicEntropy(NS) + bosonicEntropy(NSp) - bosonicEntropy(max(Aplus,0)) - bosonicEntropy(max(Aminus,0));
end

function [I, rate] = llrMutualInformation(y, bits, mu0, sig0, mu1, sig1, Rb)
b = double(bits(:));
t = 2*b - 1;
L = log(sig0/sig1) - (y(:)-mu1).^2/(2*sig1^2) + (y(:)-mu0).^2/(2*sig0^2);
penalty = log1p(exp(-t.*L))/log(2);
I = 1 - mean(penalty);
I = min(max(I,0),1);
rate = I*Rb;
end

function I = hwStyleMutualInformation(y, bits, nBins)
% Adapted from MAC_rate_region_HW.m histogram/entropy approach to I(X;Y).
y = y(:);
bits = logical(bits(:));
if numel(y) ~= numel(bits)
    error('hwStyleMutualInformation size mismatch');
end
if sum(bits) < 4 || sum(~bits) < 4
    I = NaN;
    return;
end
edges = makeHistEdges(y, nBins);
c0 = histcounts(y(~bits), edges);
c1 = histcounts(y(bits), edges);

p0 = mean(~bits);
p1 = mean(bits);

q0 = c0 / max(sum(c0), 1);
q1 = c1 / max(sum(c1), 1);
q0 = q0 + 1e-15;
q1 = q1 + 1e-15;
q0 = q0 / sum(q0);
q1 = q1 / sum(q1);

py = p0*q0 + p1*q1;
py = py + 1e-15;
py = py / sum(py);

Hy = entropyBits(py);
Hyx = p0*entropyBits(q0) + p1*entropyBits(q1);
I = Hy - Hyx;
I = min(max(I,0),1);
end

function edges = makeHistEdges(v, nBins)
v = v(:);
v = v(isfinite(v));
if isempty(v)
    edges = linspace(0, 1, nBins+1);
    return;
end
vmin = min(v);
vmax = max(v);
if vmax <= vmin
    pad = max(1e-9, abs(vmin)*1e-9);
    vmin = vmin - pad;
    vmax = vmax + pad;
end
edges = linspace(vmin, vmax, nBins+1);
end

function H = entropyBits(p)
p = p(:);
p = p(p > 0);
if isempty(p)
    H = 0;
else
    H = -sum(p.*log2(p));
end
end

function y = applyFilterByName(y, fs, Rb, filterName)
if strcmp(filterName, 'none'); return; end
ratio = parseLowpassRatio(filterName);
if ~isfinite(ratio) || ratio <= 0; return; end
cutoff = ratio*Rb;
Y = fft(y); N = numel(y);
f = (0:N-1).'*(fs/N);
mask = (f <= cutoff) | (f >= fs-cutoff);
y = real(ifft(Y.*mask));
end

function ratio = parseLowpassRatio(filterName)
ratio = NaN;
tok = regexp(filterName, '^fft_lp_([0-9p]+)Rb$', 'tokens', 'once');
if ~isempty(tok)
    ratio = str2double(strrep(tok{1}, 'p', '.'));
end
end

function y = applyDetrendByName(y, detrendName, M)
if strcmp(detrendName,'movmean_2M')
    y = y - movmean(y, max(3, round(2*M)));
end
end

function y = applyClipByName(y, clipName)
if strcmp(clipName, 'none'); return; end
q = NaN;
tok = regexp(clipName, '^winsor_q([0-9p]+)$', 'tokens', 'once');
if ~isempty(tok)
    q = str2double(strrep(tok{1}, 'p', '.'));
end
if ~isfinite(q) || q <= 0 || q >= 0.5; return; end
xs = sort(y(:)); n = numel(xs);
lo = interp1(1:n, xs, 1 + (n-1)*q, 'linear');
hi = interp1(1:n, xs, 1 + (n-1)*(1-q), 'linear');
y = min(max(y, lo), hi);
end

function [sigLag, modLag] = applyLag(sig, mod, lag)
if lag > 0
    sigLag = sig(1:end-lag);
    modLag = mod(1+lag:end);
elseif lag < 0
    k = -lag;
    sigLag = sig(1+k:end);
    modLag = mod(1:end-k);
else
    sigLag = sig;
    modLag = mod;
end
end

function [tOut, yOut, mOut] = applyRawTrim(t, y, m, trimMode, trimPoints)
tOut = t; yOut = y; mOut = m;
n = min([numel(tOut), numel(yOut), numel(mOut)]);
tOut = tOut(1:n);
yOut = yOut(1:n);
mOut = mOut(1:n);

mode = char(lower(string(trimMode)));
k = max(0, round(double(trimPoints)));
if k <= 0 || strcmp(mode, 'none')
    return;
end

switch mode
    case 'trim_start'
        idx0 = min(k, n);
        if idx0 >= n
            tOut = tOut(1:0);
            yOut = yOut(1:0);
            mOut = mOut(1:0);
        else
            tOut = tOut(idx0+1:end);
            yOut = yOut(idx0+1:end);
            mOut = mOut(idx0+1:end);
        end
    case 'trim_end'
        idx1 = max(1, n-k);
        tOut = tOut(1:idx1);
        yOut = yOut(1:idx1);
        mOut = mOut(1:idx1);
    otherwise
        % unknown trim mode; keep data unchanged for robustness
end
end

function runDir = resolveRunDir(cand)
runName = sprintf('run_%05d', cand.run_index);
roots = {cand.root, fileparts(cand.root), cand.batchDir};
if strlength(string(cand.results_json)) > 0
    bdir = fileparts(cand.results_json);
    roots{end+1} = bdir; %#ok<AGROW>
    d = dir(bdir);
    for i = 1:numel(d)
        if d(i).isdir && ~strcmp(d(i).name,'.') && ~strcmp(d(i).name,'..')
            roots{end+1} = fullfile(d(i).folder, d(i).name); %#ok<AGROW>
        end
    end
end
for i = 1:numel(roots)
    r = roots{i};
    if strlength(string(r)) == 0; continue; end
    p = fullfile(r, runName);
    if exist(p, 'dir') == 7
        runDir = p;
        return;
    end
end
error('Could not locate %s for %s', runName, cand.channel);
end

function p = resolveScopePath(runDir, fileHint, channelName, isHomodyne)
if strlength(string(fileHint)) > 0
    p = fullfile(runDir, char(string(fileHint)));
    if exist(p, 'file') == 2
        return;
    end
end
if isHomodyne
    chMap = struct('S1',2,'S2',3);
else
    chMap = struct('S1',1,'S2',4);
end
idx = chMap.(channelName);
d = dir(fullfile(runDir, sprintf('scope_*_%d.csv', idx)));
if isempty(d)
    error('Scope CSV not found for %s in %s', channelName, runDir);
end
p = fullfile(d(1).folder, d(1).name);
end

function [t, y] = readScopeCsv(path)
data = readmatrix(path, 'NumHeaderLines', 4);
t = data(:,1);
y = data(:,2);
end

function obj = loadJson(path)
obj = jsondecode(fileread(path));
end

function writeJson(path, obj)
[parent,~,~] = fileparts(path);
if strlength(string(parent)) > 0 && exist(parent,'dir') ~= 7
    mkdir(parent);
end
try
    txt = jsonencode(obj, PrettyPrint=true);
catch
    txt = jsonencode(obj);
end
fid = fopen(path, 'w');
if fid < 0
    error('Could not open for write: %s', path);
end
c = onCleanup(@() fclose(fid)); %#ok<NASGU>
fwrite(fid, txt, 'char');
fwrite(fid, sprintf('\n'), 'char');
end

function val = getNumericField(s, name, defaultVal)
if isfield(s, name)
    val = double(s.(name));
else
    val = defaultVal;
end
end

function txt = fieldOrChar(s, name, defaultVal)
if isfield(s, name)
    txt = char(string(s.(name)));
else
    txt = char(string(defaultVal));
end
end

function logp = logGaussianPdf(Y, mu, Sigma)
[N,D] = size(Y);
Yc = Y - mu;
[L,p] = chol(Sigma, 'lower');
if p ~= 0
    reg = 1e-9 + 1e-6*max(trace(Sigma),1);
    [L,p] = chol(Sigma + reg*eye(D), 'lower');
    if p ~= 0
        error('Covariance not PD');
    end
end
alpha = L \ Yc';
quad = sum(alpha.^2,1)';
logdet = 2*sum(log(diag(L)));
logp = -0.5*(D*log(2*pi) + logdet + quad);
if numel(logp) ~= N
    error('Unexpected Gaussian PDF size mismatch.');
end
end

function out = logsumexp(A, dim)
if nargin < 2
    dim = 1;
end
m = max(A, [], dim);
out = m + log(sum(exp(A-m), dim));
end

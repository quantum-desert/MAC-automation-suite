function tank_r = matched_downsample(constants,tank,deterministic,show_SNR)
% postprocess.matched_downsample
% Deterministic modulation path: optimized sweep over downsample phase and
% related post-processing knobs (M, threshold, inversion, lag, clipping).
% Random modulation path: legacy method retained; optimization hook is
% scaffolded but intentionally not implemented yet.

% assign local
tank_r = tank;

if deterministic
    tank_r = runDeterministicOptimized(constants, tank_r, show_SNR);
else
    tank_r = runRandomLegacy(constants, tank_r, show_SNR);
end

tank_r = finalizeFits(constants, tank_r);
end

function tank_r = runDeterministicOptimized(constants, tank_r, show_SNR)
M_base = max(8, round(tank_r.report.M));
M_est = estimateSymbolSamplesFromMod(tank_r.A_mod_d, M_base);

M_candidates = unique([ ...
    M_base, ...
    round(0.70*M_base), round(0.85*M_base), ...
    round(1.15*M_base), round(1.30*M_base), ...
    M_est]);
M_candidates = M_candidates(M_candidates >= 8 & M_candidates <= 180);
if isempty(M_candidates)
    M_candidates = M_base;
end

best = struct();
best.valid = false;
best.SNR = -inf;
best.signal = [];
best.mod_d = [];
best.phase = 1;
best.M = M_base;
best.lag = 0;
best.invert = false;
best.thresholdMode = 'mean';
best.clipEnabled = false;
best.phaseSNR = [];
best.classBalance = 0;

A_mod_raw = tank_r.A_mod;
for M = M_candidates
    % Core deterministic baseline from previous method.
    x = tank_r.A_homo - movmean(tank_r.A_homo, 2*M);

    for clipEnabled = [false true]
        if clipEnabled
            x_use = winsorizeArray(x, 0.005);
        else
            x_use = x;
        end

        Wn = 0.6*constants.Rb/tank_r.report.Fn;
        Wn = max(min(Wn, 0.999), 1e-6);
        [b,a] = butter(5, Wn, 'low');
        x_filt = filtfilt(b, a, x_use);

        lag_arr = unique(round([-0.50, -0.25, 0, 0.25, 0.50] * M));
        end_idx = min(floor(M/2 + M*tank_r.report.N), length(x_filt));
        if end_idx < M
            continue;
        end

        for thresholdMode = {'mean', 'median'}
            mod_d_base = buildModLabels(A_mod_raw, thresholdMode{1});
            for invert = [false true]
                for lag = lag_arr
                    phase_arr = 1:M;
                    phaseSNR = nan(size(phase_arr));

                    for phase = phase_arr
                        sample_idx = phase:M:end_idx;
                        label_idx = sample_idx + lag;
                        valid = label_idx >= 1 & label_idx <= length(mod_d_base);
                        if nnz(valid) < 120
                            continue;
                        end

                        sample_idx = sample_idx(valid);
                        label_idx = label_idx(valid);

                        dsA = x_filt(sample_idx);
                        labels = mod_d_base(label_idx);
                        if invert
                            labels = ~labels;
                        end

                        Xp = dsA(labels);
                        Xm = dsA(~labels);

                        if numel(Xp) < 50 || numel(Xm) < 50
                            continue;
                        end

                        classBalance = min(numel(Xp), numel(Xm)) / (numel(Xp) + numel(Xm));
                        if classBalance < 0.15
                            continue;
                        end

                        thisSNR = computeSNReAsymmetric(Xp, Xm);
                        phaseSNR(phase) = thisSNR;

                        if thisSNR > best.SNR
                            best.valid = true;
                            best.SNR = thisSNR;
                            best.signal = x_filt;
                            best.mod_d = mod_d_base;
                            best.phase = phase;
                            best.M = M;
                            best.lag = lag;
                            best.invert = invert;
                            best.thresholdMode = thresholdMode{1};
                            best.clipEnabled = clipEnabled;
                            best.phaseSNR = phaseSNR;
                            best.classBalance = classBalance;
                        end
                    end
                end
            end
        end
    end
end

if ~best.valid
    warning('Deterministic optimization did not find a valid configuration. Falling back to legacy deterministic path.');
    tank_r = runLegacyDeterministic(constants, tank_r, show_SNR);
    return;
end

end_idx = min(floor(best.M/2 + best.M*tank_r.report.N), length(best.signal));
sample_idx = best.phase:best.M:end_idx;
label_idx = sample_idx + best.lag;
valid = label_idx >= 1 & label_idx <= length(best.mod_d);
sample_idx = sample_idx(valid);
label_idx = label_idx(valid);

tank_r.A_homo_filt = best.signal;
tank_r.dst = tank_r.t_homo(sample_idx);
tank_r.dsA = tank_r.A_homo_filt(sample_idx);
tank_r.ds_mod_A = best.mod_d(label_idx);
if best.invert
    tank_r.ds_mod_A = ~tank_r.ds_mod_A;
end

tank_r.report.M_effective = best.M;
tank_r.report.det_optimization = struct();
tank_r.report.det_optimization.enabled = true;
tank_r.report.det_optimization.thresholdMode = best.thresholdMode;
tank_r.report.det_optimization.invertMod = best.invert;
tank_r.report.det_optimization.modLagSamples = best.lag;
tank_r.report.det_optimization.clipEnabled = best.clipEnabled;
tank_r.report.det_optimization.classBalance = best.classBalance;
tank_r.report.det_optimization.phase = best.phase;
tank_r.report.det_optimization.M = best.M;
tank_r.report.det_optimization.bestSNRe = best.SNR;

if show_SNR && ~isempty(best.phaseSNR)
    figure; hold on;
    stem(best.phaseSNR);
    xlabel('Start \phi');
    ylabel('SNR');
    title(strcat('Deterministic \phi Optimization: ', tank_r.label));
end
end

function tank_r = runLegacyDeterministic(constants, tank_r, show_SNR)
% Original deterministic behavior retained as fallback.
tank_r.A_homo = tank_r.A_homo - movmean(tank_r.A_homo,2*tank_r.report.M);
[b,a] = butter(5, 0.6*constants.Rb/tank_r.report.Fn,'low');
tank_r.A_homo_filt = filtfilt(b,a,tank_r.A_homo);

[phase, ~] = legacyPhaseSearch( ...
    tank_r.A_homo_filt, ...
    tank_r.A_mod_d, ...
    tank_r.report.M, ...
    tank_r.report.N, ...
    show_SNR, ...
    strcat('Sampling \phi Optimization (Legacy Deterministic): ', tank_r.label));

end_idx = min(floor(tank_r.report.M/2+tank_r.report.M*tank_r.report.N), floor(length(tank_r.A_homo_filt)));
sample_idx = phase:tank_r.report.M:end_idx;
tank_r.dst = tank_r.t_homo(sample_idx);
tank_r.dsA = tank_r.A_homo_filt(sample_idx);
tank_r.ds_mod_A = tank_r.A_mod_d(sample_idx);

tank_r.report.det_optimization = struct();
tank_r.report.det_optimization.enabled = false;
tank_r.report.det_optimization.mode = 'legacy_fallback';
end

function tank_r = runRandomLegacy(constants, tank_r, show_SNR)
% Existing random-modulation-compatible flow retained.
haf = ones(1, tank_r.report.M) / tank_r.report.M;
tank_r.A_homo_filt = filtfilt(haf,1,tank_r.A_homo);

[phase, phaseSNR] = legacyPhaseSearch( ...
    tank_r.A_homo_filt, ...
    tank_r.A_mod_d, ...
    tank_r.report.M, ...
    tank_r.report.N, ...
    show_SNR, ...
    strcat('Sampling \phi Optimization: ', tank_r.label));

end_idx = min(floor(tank_r.report.M/2+tank_r.report.M*tank_r.report.N), floor(length(tank_r.A_homo_filt)));
sample_idx = phase:tank_r.report.M:end_idx;
tank_r.dst = tank_r.t_homo(sample_idx);
tank_r.dsA = tank_r.A_homo_filt(sample_idx);
tank_r.ds_mod_A = tank_r.A_mod_d(sample_idx);

tank_r.report.random_optimization = struct();
tank_r.report.random_optimization.available = true;
tank_r.report.random_optimization.implemented = false;
tank_r.report.random_optimization.enabled = false;
tank_r.report.random_optimization.note = 'Skeleton only. Legacy random-modulation path is active.';
tank_r.report.random_optimization.legacyBestPhase = phase;
tank_r.report.random_optimization.legacyPhaseSNR = phaseSNR;

% Future integration hook (intentionally not implemented yet).
if isstruct(constants) && isfield(constants, 'randomModulationOptimizer') && ...
        isstruct(constants.randomModulationOptimizer) && ...
        isfield(constants.randomModulationOptimizer, 'enable') && ...
        logical(constants.randomModulationOptimizer.enable)
    tank_r.report.random_optimization.enabled = true;
    warning('Random modulation optimizer is not implemented yet. Using legacy path.');
end
end

function [bestPhase, SNR] = legacyPhaseSearch(signal, mod_d, M, N, show_SNR, plotTitle)
end_idx = min(floor(M/2 + M*N), floor(length(signal)));
N_phase = max(1, 4*M);
W = 1:N_phase;
SNR = nan(size(W));

for w = 1:length(W)
    sample_idx = W(w):M:end_idx;
    if isempty(sample_idx)
        continue;
    end
    dsA = signal(sample_idx);
    ds_mod_A = mod_d(sample_idx);

    Xp = dsA(ds_mod_A);
    Xm = dsA(~ds_mod_A);
    if numel(Xp) < 2 || numel(Xm) < 2
        continue;
    end
    SNR(w) = computeSNReAsymmetric(Xp, Xm);
end

[~, bestPhaseIdx] = max(SNR);
bestPhase = W(bestPhaseIdx);

if show_SNR
    figure; hold on;
    stem(SNR);
    xlabel('Start \phi');
    ylabel('SNR');
    title(plotTitle);
end
end

function tank_r = finalizeFits(constants, tank_r)
if ~isfield(tank_r, 'fit') || ~isstruct(tank_r.fit)
    tank_r.fit = struct();
end

if ~isfield(tank_r, 'dsA') || ~isfield(tank_r, 'ds_mod_A') || isempty(tank_r.dsA)
    warning('No downsampled data found; fit outputs set to NaN.');
    tank_r.fit.Xp = [];
    tank_r.fit.Xm = [];
    tank_r.fit.SNRe = NaN;
    tank_r.fit.SNRf = NaN;
    tank_r.report.ds_len = 0;
    return;
end

dsA = tank_r.dsA(:);
labels = logical(tank_r.ds_mod_A(:));
L = min(numel(dsA), numel(labels));
dsA = dsA(1:L);
labels = labels(1:L);

tank_r.fit.Xp = dsA(labels).';
tank_r.fit.Xm = dsA(~labels).';

if numel(tank_r.fit.Xp) < 2 || numel(tank_r.fit.Xm) < 2
    tank_r.fit.SNRe = NaN;
else
    tank_r.fit.SNRe = computeSNReAsymmetric(tank_r.fit.Xp, tank_r.fit.Xm);
end

if isstruct(constants) && isfield(constants, 'BW_t') && isfield(constants, 'RBW') && constants.RBW > 0
    tank_r.fit.SNRf = tank_r.fit.SNRe*sqrt(constants.BW_t/constants.RBW);
else
    tank_r.fit.SNRf = NaN;
end

bw = 1e-5;
try
    [counts_p, edges_p] = histcounts(tank_r.fit.Xp, 'BinWidth', bw);
    binCenters_p = (edges_p(1:end-1) + edges_p(2:end)) / 2;
    [tank_r.fit.f_p, ~] = fit(binCenters_p', counts_p', 'gauss1');

    [counts_m, edges_m] = histcounts(tank_r.fit.Xm, 'BinWidth', bw);
    binCenters_m = (edges_m(1:end-1) + edges_m(2:end)) / 2;
    [tank_r.fit.f_m, ~] = fit(binCenters_m', counts_m', 'gauss1');
catch
    warning('Fitting failed');
end

tank_r.report.ds_len = numel(dsA);
end

function snr = computeSNReAsymmetric(Xp, Xm)
if isempty(Xp) || isempty(Xm) || numel(Xp) < 2 || numel(Xm) < 2
    snr = NaN;
    return;
end
denom = 4*(std(Xp)^2);
if denom <= 0
    snr = NaN;
    return;
end
snr = (abs(mean(Xp) - mean(Xm)))^2 / denom;
end

function mod_d = buildModLabels(A_mod, thresholdMode)
A_mod = A_mod(:);
maxAmp = max(abs(A_mod));
if maxAmp <= 0
    A_mod_n = A_mod;
else
    A_mod_n = A_mod / maxAmp;
end

switch lower(thresholdMode)
    case 'median'
        th = median(A_mod_n);
    otherwise
        th = mean(A_mod_n);
end
mod_d = A_mod_n > th;
end

function x_w = winsorizeArray(x, frac)
x = x(:);
n = numel(x);
if n == 0
    x_w = x;
    return;
end
frac = max(0, min(frac, 0.49));
xs = sort(x);
i1 = max(1, floor(frac*n));
i2 = min(n, ceil((1-frac)*n));
lo = xs(i1);
hi = xs(i2);
x_w = min(max(x, lo), hi);
end

function M_est = estimateSymbolSamplesFromMod(mod_d, M_base)
M_est = M_base;
edges = find(diff(double(mod_d)) ~= 0) + 1;
if numel(edges) < 8
    return;
end

d = diff(edges);
d = d(d > 1);
if numel(d) < 6
    return;
end

m_lo = max(8, round(0.6*M_base));
m_hi = min(180, round(1.4*M_base));
if m_hi <= m_lo
    return;
end

bestScore = inf;
bestM = M_base;
for m = m_lo:m_hi
    ratio = d / m;
    score = mean(abs(ratio - round(ratio))) + 0.002*abs(m - M_base);
    if score < bestScore
        bestScore = score;
        bestM = m;
    end
end
M_est = bestM;
end

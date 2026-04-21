function visualize_best_dataset_tool(dataRoot, resultsJson)
% visualize_best_dataset_tool
% Standalone interactive visualization for deterministic post-processing.
% - Defaults to the best run per channel from results JSON (if present)
% - Allows selecting any run index
% - Includes time-domain, histogram, FFT, and phase-SNR scan visualizations
%
% Example:
%   visualize_best_dataset_tool
%   visualize_best_dataset_tool('C:\path\to\runs', 'C:\path\to\snr_optimization_results.json')

if nargin < 1 || strlength(string(dataRoot)) == 0
    dataRoot = '/Users/agentatom/Library/CloudStorage/OneDrive-Umich/GraduateSchool/UM/QE_LAB/MAC/data/codex_processing/4-20-26/2026-04-20_pre_opt_det';
end
if nargin < 2 || strlength(string(resultsJson)) == 0
    resultsJson = '/Users/agentatom/Library/CloudStorage/OneDrive-Umich/GraduateSchool/UM/QE_LAB/MAC/data/codex_processing/4-20-26/snr_optimization_results_4-20-26.json';
end

dataRoot = char(string(dataRoot));
resultsJson = char(string(resultsJson));

runInfo = discoverRuns(dataRoot);
if isempty(runInfo.indices)
    error('No run_* folders found in %s', dataRoot);
end

resultsInfo = loadResultsInfo(resultsJson);
bestRuns = resultsInfo.bestRuns;

constants = defaultConstantsLocal();
channelMap = defaultChannelMap();

initialPos = computeInitialFigurePosition([1600 920]);
fig = figure('Name', 'Best Dataset Visualizer (Standalone)', ...
             'Color', 'w', ...
             'NumberTitle', 'off', ...
             'Units', 'pixels', ...
             'Position', initialPos, ...
             'Resize', 'on');
set(fig, 'SizeChangedFcn', @(~,~)enforceFigureBounds(fig));
enforceFigureBounds(fig);

tg = uitabgroup(fig, 'Position', [0 0 1 1]);
app = struct();
app.dataRoot = dataRoot;
app.resultsJson = resultsJson;
app.constants = constants;
app.channelMap = channelMap;
app.runInfo = runInfo;
app.bestRuns = bestRuns;
app.resultsInfo = resultsInfo;
app.tabs = struct();

app.tabs.S1 = buildChannelTab(tg, app, 'S1');
app.tabs.S2 = buildChannelTab(tg, app, 'S2');

refreshChannel('S1');
refreshChannel('S2');

    function tabState = buildChannelTab(tabGroup, appState, channelName)
        tab = uitab(tabGroup, 'Title', sprintf('%s View', channelName));

        uicontrol(tab, 'Style', 'text', ...
            'String', sprintf('%s run index:', channelName), ...
            'Units', 'normalized', ...
            'BackgroundColor', 'w', ...
            'HorizontalAlignment', 'left', ...
            'FontWeight', 'bold', ...
            'Position', [0.015 0.945 0.10 0.032]);

        popup = uicontrol(tab, 'Style', 'popupmenu', ...
            'String', appState.runInfo.labels, ...
            'Units', 'normalized', ...
            'Position', [0.115 0.948 0.15 0.034], ...
            'Callback', @(~,~)refreshChannel(channelName));

        uicontrol(tab, 'Style', 'pushbutton', ...
            'String', 'Refresh', ...
            'Units', 'normalized', ...
            'Position', [0.275 0.948 0.08 0.034], ...
            'Callback', @(~,~)refreshChannel(channelName));

        uicontrol(tab, 'Style', 'pushbutton', ...
            'String', 'Jump To Best', ...
            'Units', 'normalized', ...
            'Position', [0.362 0.948 0.10 0.034], ...
            'Callback', @(~,~)jumpToBest(channelName));

        statsText = uicontrol(tab, 'Style', 'text', ...
            'String', 'Loading...', ...
            'Units', 'normalized', ...
            'BackgroundColor', 'w', ...
            'HorizontalAlignment', 'left', ...
            'Position', [0.475 0.942 0.51 0.042]);

        tl = tiledlayout(tab, 2, 2, ...
            'Units', 'normalized', ...
            'Position', [0.02 0.105 0.96 0.80], ...
            'Padding', 'compact', ...
            'TileSpacing', 'compact');

        axTime = nexttile(tl, 1);
        axHist = nexttile(tl, 2);
        axFFT = nexttile(tl, 3);
        axScan = nexttile(tl, 4);

        set(axTime, 'Box', 'on');
        set(axHist, 'Box', 'on');
        set(axFFT, 'Box', 'on');
        set(axScan, 'Box', 'on');

        tabState = struct();
        tabState.tab = tab;
        tabState.popup = popup;
        tabState.statsText = statsText;
        tabState.axTime = axTime;
        tabState.axHist = axHist;
        tabState.axFFT = axFFT;
        tabState.axScan = axScan;

        defaultRun = appState.bestRuns.(channelName);
        runPos = find(appState.runInfo.indices == defaultRun, 1, 'first');
        if isempty(runPos)
            runPos = 1;
        end
        tabState.popup.Value = runPos;
    end

    function jumpToBest(channelName)
        tabState = app.tabs.(channelName);
        defaultRun = app.bestRuns.(channelName);
        runPos = find(app.runInfo.indices == defaultRun, 1, 'first');
        if ~isempty(runPos)
            tabState.popup.Value = runPos;
        end
        refreshChannel(channelName);
    end

    function refreshChannel(channelName)
        tabState = app.tabs.(channelName);

        runPos = tabState.popup.Value;
        runIdx = app.runInfo.indices(runPos);
        runDir = app.runInfo.folders{runPos};
        resultMeta = lookupRunChannelMeta(app.resultsInfo, runIdx, channelName);

        try
            info = computeChannelView(runDir, runIdx, channelName, app.channelMap.(channelName), app.constants, resultMeta);
            renderChannel(tabState, info, runIdx, channelName, app.bestRuns.(channelName));
        catch ME
            cla(tabState.axTime); cla(tabState.axHist); cla(tabState.axFFT); cla(tabState.axScan);
            tabState.statsText.String = sprintf('%s run %d failed: %s', channelName, runIdx, ME.message);
            title(tabState.axTime, sprintf('%s run %d (error)', channelName, runIdx));
        end
    end
end

function runInfo = discoverRuns(dataRoot)
d = dir(fullfile(dataRoot, 'run_*'));
indices = [];
folders = {};
for k = 1:numel(d)
    if ~d(k).isdir
        continue;
    end
    tok = regexp(d(k).name, '^run_(\d+)$', 'tokens', 'once');
    if isempty(tok)
        continue;
    end
    idx = str2double(tok{1});
    indices(end+1) = idx; %#ok<AGROW>
    folders{end+1} = fullfile(d(k).folder, d(k).name); %#ok<AGROW>
end

[indices, order] = sort(indices);
folders = folders(order);
labels = arrayfun(@(x) sprintf('run_%05d', x), indices, 'UniformOutput', false);

runInfo = struct('indices', indices, 'folders', {folders}, 'labels', {labels});
end

function info = computeChannelView(runDir, runIdx, channelName, map, constants, resultMeta)
if nargin < 6 || isempty(resultMeta)
    resultMeta = defaultResultMeta();
end

if resultMeta.hasSettings
    try
        info = computeChannelViewOptimized(runDir, runIdx, channelName, map, constants, resultMeta.settings, resultMeta);
        info.computeMode = 'optimized';
        info.computeReason = 'replayed optimizer method from JSON';
    catch ME
        warning('Optimized replay failed for run %d %s (%s). Falling back to legacy compute.', runIdx, channelName, ME.message);
        info = computeChannelViewLegacy(runDir, runIdx, channelName, map, constants, resultMeta);
        info.computeMode = 'legacy_fallback';
        info.computeReason = sprintf('optimized replay failed: %s', ME.message);
    end
else
    info = computeChannelViewLegacy(runDir, runIdx, channelName, map, constants, resultMeta);
    info.computeMode = 'legacy';
    info.computeReason = 'missing optimizer method metadata in JSON';
end

info.jsonSNRe = resultMeta.jsonSNRe;
info.jsonSNR_C = resultMeta.jsonSNR_C;
info.jsonMargin = resultMeta.jsonMargin;
info.hasJsonReference = resultMeta.hasJsonReference;
info.jsonTolerance = 1e-4;
info.computedSNRe = info.SNRe;
if isfinite(info.computedSNRe) && isfinite(info.SNR_C)
    info.computedMargin = info.computedSNRe - info.SNR_C;
else
    info.computedMargin = NaN;
end

% Use JSON as canonical display reference when available.
if isfinite(info.jsonSNRe)
    info.SNRe = info.jsonSNRe;
end
if isfinite(info.jsonSNR_C)
    info.SNR_C = info.jsonSNR_C;
end

if isfinite(info.jsonSNRe) && isfinite(info.computedSNRe)
    info.jsonDeltaSNRe = info.computedSNRe - info.jsonSNRe;
else
    info.jsonDeltaSNRe = NaN;
end

if isfinite(info.jsonMargin) && isfinite(info.computedMargin)
    info.jsonDeltaMargin = info.computedMargin - info.jsonMargin;
else
    info.jsonDeltaMargin = NaN;
end
end

function info = computeChannelViewLegacy(runDir, runIdx, channelName, map, constants, resultMeta)
[t_homo, A_homo] = loadScopeCsv(runDir, runIdx, map.homodyneChannel);
[t_mod, A_mod] = loadScopeCsv(runDir, runIdx, map.modChannel);

L = min([numel(t_homo), numel(A_homo), numel(t_mod), numel(A_mod)]);
t_homo = t_homo(1:L);
A_homo = A_homo(1:L);
t_mod = t_mod(1:L);
A_mod = A_mod(1:L);

A_mod_d = normalizeModForPlot(A_mod);
A_homo_centered = A_homo - mean(A_homo);

delta_t = t_homo(2) - t_homo(1);
Fs = 1 / delta_t;
Fn = Fs / 2;
M = round(Fs / constants.Rb);
N = floor((t_homo(end)-t_homo(1)) * constants.Rb);

A_homo_dt = A_homo_centered - movmean(A_homo_centered, 2 * M);
[b, a] = butter(5, 0.6 * constants.Rb / Fn, 'low');
A_homo_filt = filtfilt(b, a, A_homo_dt);

end_idx = min(floor(M/2 + M*N), numel(A_homo_filt));
N_phase = 4 * M;
W = 1:N_phase;
scanSNR = nan(size(W));

for w = 1:numel(W)
    idx = W(w):M:end_idx;
    if numel(idx) < 4
        continue;
    end
    dsA = A_homo_filt(idx);
    ds_mod = A_mod_d(idx) > mean(A_mod_d(idx));

    Xp = dsA(ds_mod);
    Xm = dsA(~ds_mod);

    if isempty(Xp) || isempty(Xm) || std(Xp) == 0
        continue;
    end
    scanSNR(w) = (abs(mean(Xp)-mean(Xm)))^2 / (4 * std(Xp)^2);
end

[bestSNRe, bestIdx] = max(scanSNR);
if isempty(bestIdx) || ~isfinite(bestSNRe)
    error('Could not compute valid SNR scan for run %d channel %s', runIdx, channelName);
end
bestPhase = W(bestIdx);

sample_idx = bestPhase:M:end_idx;
dst = t_homo(sample_idx);
dsA = A_homo_filt(sample_idx);
local_mod = A_mod_d(sample_idx);
ds_mod = local_mod > mean(local_mod);

Xp = dsA(ds_mod);
Xm = dsA(~ds_mod);
if isempty(Xp) || std(Xp) == 0
    SNRe = NaN;
else
    SNRe = (abs(mean(Xp)-mean(Xm)))^2 / (4 * std(Xp)^2);
end

SNR_C = resolveClassicalLimit(resultMeta, runDir, channelName);

fft_mod = fftCalc(A_mod, Fs);
fft_filt = fftCalc(A_homo_filt, Fs);

info = struct();
info.runDir = runDir;
info.runIdx = runIdx;
info.channelName = channelName;
info.constants = constants;
info.methodMetric = 'asym_xp';
info.methodSummary = 'legacy internal method';
info.report = struct('Fs', Fs, 'Fn', Fn, 'M', M, 'N', N, 'delta_t', delta_t, 'lag', 0, 'phaseZeroBased', bestPhase - 1);

info.t_homo = t_homo;
info.A_homo = A_homo_centered;
info.t_mod = t_mod;
info.A_mod_d = A_mod_d;
info.A_homo_filt = A_homo_filt;

info.dst = dst;
info.dsA = dsA;
info.ds_mod = ds_mod;
info.Xp = Xp;
info.Xm = Xm;

info.scanPhase = W;
info.scanSNR = scanSNR;
info.bestPhase = bestPhase;
info.SNRe = SNRe;
info.SNR_C = SNR_C;

info.fft_mod = fft_mod;
info.fft_filt = fft_filt;
end

function info = computeChannelViewOptimized(runDir, runIdx, channelName, map, constants, settings, resultMeta)
[t_homo, A_homo] = loadScopeCsv(runDir, runIdx, map.homodyneChannel);
[t_mod, A_mod] = loadScopeCsv(runDir, runIdx, map.modChannel);

L = min([numel(t_homo), numel(A_homo), numel(t_mod), numel(A_mod)]);
t_homo = t_homo(1:L);
A_homo = A_homo(1:L);
t_mod = t_mod(1:L);
A_mod = A_mod(1:L);

delta_t = t_homo(2) - t_homo(1);
Fs = 1 / delta_t;
Fn = Fs / 2;

M = max(4, round(settings.M));
Rb = Fs / M;
N = floor((t_homo(end)-t_homo(1)) * Rb);

base_sig = A_homo;
sig_filt = applyOptimizerFilter(base_sig, Fs, Rb, settings.filter);
sig_dt = applyOptimizerDetrend(sig_filt, settings.detrend, M);
sig_proc = applyOptimizerClip(sig_dt, settings.clip);

[sig_lag, mod_lag, lagOffset] = applyLagOptimizer(sig_proc, A_mod, settings.lag);
n_raw = min(numel(sig_lag), numel(mod_lag));
if n_raw < 8 * M
    error('Not enough lag-aligned samples (%d) for M=%d', n_raw, M);
end

sig_lag = sig_lag(1:n_raw);
mod_lag = mod_lag(1:n_raw);
base_time = t_homo(1+lagOffset : lagOffset+n_raw);

scanPhase = 0:(M-1);
scanMetric = nan(size(scanPhase));
for k = 1:numel(scanPhase)
    ev = evaluateOptimizerPhase(sig_lag, mod_lag, scanPhase(k), settings.threshold, settings.invert, M);
    if ~ev.valid
        continue;
    end
    if strcmpi(settings.metric, 'asym_sym')
        scanMetric(k) = ev.snre_asym_sym;
    else
        scanMetric(k) = ev.snre_asym_xp;
    end
end

selectedPhase = mod(round(settings.phase), M);
evSelected = evaluateOptimizerPhase(sig_lag, mod_lag, selectedPhase, settings.threshold, settings.invert, M);
if ~evSelected.valid
    error('Saved method phase %d produced invalid class split for run %d %s', selectedPhase, runIdx, channelName);
end

SNRe = evSelected.snre_asym_xp;
SNR_C = resolveClassicalLimit(resultMeta, runDir, channelName);

sample_idx = (selectedPhase+1):M:n_raw;
dst = base_time(sample_idx);
dsA = sig_lag(sample_idx);
ds_mod = evSelected.bits;

fft_mod = fftCalc(A_mod, Fs);
fft_filt = fftCalc(sig_proc, Fs);

info = struct();
info.runDir = runDir;
info.runIdx = runIdx;
info.channelName = channelName;
info.constants = constants;
info.methodMetric = settings.metric;
info.methodSummary = settings.methodString;
info.report = struct('Fs', Fs, 'Fn', Fn, 'M', M, 'N', N, 'delta_t', delta_t, 'lag', settings.lag, 'phaseZeroBased', selectedPhase);

info.t_homo = t_homo;
info.A_homo = A_homo - mean(A_homo);
info.t_mod = t_mod;
info.A_mod_d = normalizeModForPlot(A_mod);
info.A_homo_filt = sig_proc;

info.dst = dst;
info.dsA = dsA;
info.ds_mod = ds_mod;
info.Xp = evSelected.xp;
info.Xm = evSelected.xm;

info.scanPhase = scanPhase;
info.scanSNR = scanMetric;
info.bestPhase = selectedPhase;
info.SNRe = SNRe;
info.SNR_C = SNR_C;

info.fft_mod = fft_mod;
info.fft_filt = fft_filt;
end

function renderChannel(tabState, info, runIdx, channelName, bestRun)
axTime = tabState.axTime;
axHist = tabState.axHist;
axFFT = tabState.axFFT;
axScan = tabState.axScan;

cla(axTime); cla(axHist); cla(axFFT); cla(axScan);

lim = min(1000, numel(info.t_homo));
lim_ds = min(max(1, floor(lim / max(1, info.report.M))), numel(info.dst));

plot(axTime, info.t_homo(1:lim), info.A_homo(1:lim), 'LineWidth', 1.5, 'DisplayName', 'Homodyne (Raw)');
hold(axTime, 'on');
plot(axTime, info.t_homo(1:lim), 5*info.A_homo_filt(1:lim), 'LineWidth', 1.5, 'DisplayName', 'Homodyne (Processed x5)');
plot(axTime, info.t_mod(1:lim), 0.5*double(info.A_mod_d(1:lim)), 'LineWidth', 1.5, 'DisplayName', 'Modulation (normalized/2)');
scatter(axTime, info.dst(1:lim_ds), 5*info.dsA(1:lim_ds), 14, 'm', 'filled', 'DisplayName', 'Downsampled (x5)');
xlabel(axTime, 'Time (s)');
ylabel(axTime, 'Amplitude (V)');
title(axTime, sprintf('%s Time Domain (run %05d)', channelName, runIdx));
grid(axTime, 'on'); legend(axTime, 'Location', 'best');

histogram(axHist, info.Xp, 70, 'DisplayName', 'X^+', 'FaceColor', [0.62 0.01 0.84], 'FaceAlpha', 0.9);
hold(axHist, 'on');
histogram(axHist, info.Xm, 70, 'DisplayName', 'X^-', 'FaceColor', [1.0 0.69 0.31], 'FaceAlpha', 0.6);
xline(axHist, mean(info.Xp), '--', 'DisplayName', '\mu^+');
xline(axHist, mean(info.Xm), '--', 'DisplayName', '\mu^-');
xlabel(axHist, 'Amplitude (V)');
ylabel(axHist, 'Counts');
title(axHist, sprintf('%s Histogram (SNRe = %.4f)', channelName, info.SNRe));
grid(axHist, 'on'); legend(axHist, 'Location', 'best');

plot(axFFT, info.fft_mod(:,1), info.fft_mod(:,2), 'LineWidth', 1.3, 'DisplayName', 'Modulation');
hold(axFFT, 'on');
plot(axFFT, info.fft_filt(:,1), info.fft_filt(:,2), 'LineWidth', 1.3, 'DisplayName', 'Processed Homodyne');
xlim(axFFT, [0 100]);
ylabel(axFFT, 'log|FFT|');
xlabel(axFFT, 'Frequency (kHz)');
title(axFFT, sprintf('%s Frequency Domain', channelName));
grid(axFFT, 'on'); legend(axFFT, 'Location', 'best');

stem(axScan, info.scanPhase, info.scanSNR, 'filled', 'DisplayName', 'Scan metric');
hold(axScan, 'on');
xline(axScan, info.bestPhase, '--r', 'LineWidth', 1.4, 'DisplayName', sprintf('Selected phase = %d', info.bestPhase));
xlabel(axScan, 'Start phase index');
ylabel(axScan, 'Metric');
title(axScan, sprintf('%s Phase Scan (M = %d, metric = %s)', channelName, info.report.M, info.methodMetric));
grid(axScan, 'on'); legend(axScan, 'Location', 'best');

margin = NaN;
flag = 'no classical reference';
if isfinite(info.SNR_C)
    margin = info.SNRe - info.SNR_C;
    flag = 'below classical';
    if margin > 0
        flag = 'BEATS CLASSICAL';
    end
end

stats = sprintf('%s run %05d | default best run = %05d | mode = %s | SNRe = %.6f', ...
    channelName, runIdx, bestRun, info.computeMode, info.SNRe);
if isfinite(info.computedSNRe)
    stats = sprintf('%s | computed SNRe = %.6f', stats, info.computedSNRe);
end
if isfinite(info.SNR_C)
    stats = sprintf('%s | SNR_C = %.6f | margin = %+0.6f (%s)', stats, info.SNR_C, margin, flag);
end
if isfinite(info.computedMargin)
    stats = sprintf('%s | computed margin = %+0.6f', stats, info.computedMargin);
end
stats = sprintf('%s | phase = %d | M = %d', stats, info.bestPhase, info.report.M);

if info.hasJsonReference && isfinite(info.jsonSNRe)
    stats = sprintf('%s | JSON SNRe = %.6f', stats, info.jsonSNRe);
end
if info.hasJsonReference && isfinite(info.jsonMargin)
    stats = sprintf('%s | JSON margin = %+0.6f', stats, info.jsonMargin);
end
if isfinite(info.jsonDeltaSNRe)
    status = 'MATCH';
    if abs(info.jsonDeltaSNRe) > info.jsonTolerance
        status = 'MISMATCH';
    end
    stats = sprintf('%s | dSNRe = %+0.6f (%s)', stats, info.jsonDeltaSNRe, status);
end
if isfinite(info.jsonDeltaMargin)
    statusMargin = 'MATCH';
    if abs(info.jsonDeltaMargin) > info.jsonTolerance
        statusMargin = 'MISMATCH';
    end
    stats = sprintf('%s | dMargin = %+0.6f (%s)', stats, info.jsonDeltaMargin, statusMargin);
end

if ~isempty(info.computeReason)
    stats = sprintf('%s | note: %s', stats, info.computeReason);
end

tabState.statsText.String = stats;
end

function [t, y] = loadScopeCsv(runDir, runIdx, ch)
pat = fullfile(runDir, sprintf('scope_*_%d.csv', ch));
files = dir(pat);
if isempty(files)
    p2 = fullfile(runDir, sprintf('scope_%d_%d.csv', runIdx, ch));
    if exist(p2, 'file') ~= 2
        error('Missing scope data for run %d channel %d in %s', runIdx, ch, runDir);
    end
    path = p2;
else
    path = fullfile(files(1).folder, files(1).name);
end

a = readmatrix(path, 'NumHeaderLines', 4);
t = a(:,1);
y = a(:,2);
end

function ft = fftCalc(x, fs)
N = numel(x);
X = fft(x);
P2 = abs(X) / N;
P1 = P2(1:floor(N/2)+1);
if mod(N,2) == 0
    P1(2:end-1) = 2 * P1(2:end-1);
else
    P1(2:end) = 2 * P1(2:end);
end
f = fs * (0:floor(N/2)) / N;
ft = [f(:) ./ 1e3, log(P1(:) + eps)];
end

function constants = defaultConstantsLocal()
constants = struct();
constants.Rb = 16e3;
constants.fd = 32e3;
constants.BW_t = 9.6e3;
constants.RBW = 7.813;
end

function cmap = defaultChannelMap()
cmap = struct();
cmap.S1 = struct('homodyneChannel', 2, 'modChannel', 1);
cmap.S2 = struct('homodyneChannel', 3, 'modChannel', 4);
end

function resultsInfo = loadResultsInfo(resultsJson)
resultsInfo = struct();
resultsInfo.available = false;
resultsInfo.bestRuns = struct('S1', 20, 'S2', 81);
resultsInfo.bestByChannel = struct();
resultsInfo.byRun = struct();

if exist(resultsJson, 'file') ~= 2
    warning('Results JSON not found at %s. Using fallback defaults.', resultsJson);
    return;
end

try
    results = jsondecode(fileread(resultsJson));
catch ME
    msg = char(ME.message);
    warning('%s', sprintf('Could not parse results JSON (%s). Using fallback defaults.', msg));
    return;
end

resultsInfo.available = true;

if isfield(results, 'best_by_channel')
    resultsInfo.bestByChannel = results.best_by_channel;
    if isfield(results.best_by_channel, 'S1') && isfield(results.best_by_channel.S1, 'run_index')
        resultsInfo.bestRuns.S1 = double(results.best_by_channel.S1.run_index);
    end
    if isfield(results.best_by_channel, 'S2') && isfield(results.best_by_channel.S2, 'run_index')
        resultsInfo.bestRuns.S2 = double(results.best_by_channel.S2.run_index);
    end
end

if isfield(results, 'per_run') && isstruct(results.per_run)
    for k = 1:numel(results.per_run)
        row = results.per_run(k);
        if ~isfield(row, 'run_index')
            continue;
        end
        runIdx = double(row.run_index);
        key = runFieldKey(runIdx);
        entry = struct();
        if isfield(row, 'S1') && isstruct(row.S1)
            entry.S1 = row.S1;
        end
        if isfield(row, 'S2') && isstruct(row.S2)
            entry.S2 = row.S2;
        end
        if ~isempty(fieldnames(entry))
            resultsInfo.byRun.(key) = entry;
        end
    end
end
end

function meta = lookupRunChannelMeta(resultsInfo, runIdx, channelName)
meta = defaultResultMeta();

if ~resultsInfo.available
    return;
end

key = runFieldKey(runIdx);
if isfield(resultsInfo.byRun, key)
    row = resultsInfo.byRun.(key);
    if isfield(row, channelName)
        ch = row.(channelName);
        if isfield(ch, 'snre')
            meta.jsonSNRe = double(ch.snre);
        end
        if isfield(ch, 'classical')
            meta.jsonSNR_C = double(ch.classical);
        end
        if isfield(ch, 'margin')
            meta.jsonMargin = double(ch.margin);
        end
        if isfield(ch, 'method')
            meta.methodString = char(string(ch.method));
        end
    end
end

if isfield(resultsInfo.bestByChannel, channelName)
    b = resultsInfo.bestByChannel.(channelName);
    if isfield(b, 'run_index') && double(b.run_index) == runIdx
        if ~isfinite(meta.jsonSNRe) && isfield(b, 'snre')
            meta.jsonSNRe = double(b.snre);
        end
        if ~isfinite(meta.jsonMargin) && isfield(b, 'margin_vs_classical')
            meta.jsonMargin = double(b.margin_vs_classical);
        end
        if ~isfinite(meta.jsonSNR_C) && isfield(b, 'snre') && isfield(b, 'margin_vs_classical')
            meta.jsonSNR_C = double(b.snre) - double(b.margin_vs_classical);
        end
        if isempty(meta.methodString) && isfield(b, 'method')
            meta.methodString = char(string(b.method));
        end

        settings = settingsFromBestChannelRecord(b);
        if isValidMethodSettings(settings)
            meta.settings = settings;
            meta.hasSettings = true;
        end
    end
end

if ~meta.hasSettings && ~isempty(meta.methodString)
    parsed = parseMethodString(meta.methodString);
    if isValidMethodSettings(parsed)
        meta.settings = parsed;
        meta.hasSettings = true;
    end
end

if ~isfinite(meta.jsonSNR_C) && isfinite(meta.jsonSNRe) && isfinite(meta.jsonMargin)
    meta.jsonSNR_C = meta.jsonSNRe - meta.jsonMargin;
end

meta.hasJsonReference = isfinite(meta.jsonSNRe) || isfinite(meta.jsonSNR_C) || isfinite(meta.jsonMargin);
end

function meta = defaultResultMeta()
meta = struct();
meta.settings = defaultMethodSettings();
meta.hasSettings = false;
meta.methodString = '';
meta.jsonSNRe = NaN;
meta.jsonSNR_C = NaN;
meta.jsonMargin = NaN;
meta.hasJsonReference = false;
end

function s = defaultMethodSettings()
s = struct();
s.filter = '';
s.detrend = '';
s.clip = '';
s.threshold = '';
s.invert = false;
s.metric = '';
s.M = NaN;
s.phase = NaN;
s.lag = NaN;
s.methodString = '';
end

function settings = settingsFromBestChannelRecord(rec)
settings = defaultMethodSettings();

if isfield(rec, 'filter')
    settings.filter = char(string(rec.filter));
end
if isfield(rec, 'detrend')
    settings.detrend = char(string(rec.detrend));
end
if isfield(rec, 'clip')
    settings.clip = char(string(rec.clip));
end
if isfield(rec, 'threshold')
    settings.threshold = char(string(rec.threshold));
end
if isfield(rec, 'invert')
    settings.invert = parseBoolValue(rec.invert, false);
end
if isfield(rec, 'metric')
    settings.metric = char(string(rec.metric));
end
if isfield(rec, 'M')
    settings.M = double(rec.M);
end
if isfield(rec, 'phase')
    settings.phase = double(rec.phase);
end
if isfield(rec, 'lag')
    settings.lag = double(rec.lag);
end
if isfield(rec, 'method')
    settings.methodString = char(string(rec.method));
end

if ~isValidMethodSettings(settings) && isfield(rec, 'method')
    settings = parseMethodString(char(string(rec.method)));
end
end

function tf = isValidMethodSettings(settings)
tf = ~isempty(settings.filter) && ...
     ~isempty(settings.detrend) && ...
     ~isempty(settings.clip) && ...
     ~isempty(settings.threshold) && ...
     ~isempty(settings.metric) && ...
     isfinite(settings.M) && settings.M >= 4 && ...
     isfinite(settings.phase) && ...
     isfinite(settings.lag);
end

function settings = parseMethodString(methodString)
settings = defaultMethodSettings();
settings.methodString = char(string(methodString));

if strlength(string(methodString)) == 0
    return;
end

parts = strsplit(char(string(methodString)), ';');
for i = 1:numel(parts)
    tok = strtrim(parts{i});
    if isempty(tok)
        continue;
    end

    m = regexp(tok, '^([^=]+)=(.*)$', 'tokens', 'once');
    if isempty(m)
        continue;
    end

    key = lower(strtrim(m{1}));
    val = strtrim(m{2});

    switch key
        case 'filter'
            settings.filter = val;
        case 'detrend'
            settings.detrend = val;
        case 'clip'
            settings.clip = val;
        case 'threshold'
            settings.threshold = val;
        case 'invert'
            settings.invert = parseBoolValue(val, false);
        case 'metric'
            settings.metric = val;
        case 'm'
            settings.M = str2double(val);
        case 'phase'
            settings.phase = str2double(val);
        case 'lag'
            settings.lag = str2double(val);
        otherwise
            % Ignore unknown tokens for forward compatibility.
    end
end
end

function y = applyOptimizerFilter(x, fs, rb, filterName)
name = lower(strtrim(filterName));
switch name
    case 'none'
        y = x;
    case 'fft_lp_0p6rb'
        y = fftLowpassMask(x, fs, 0.6 * rb);
    case 'fft_lp_0p8rb'
        y = fftLowpassMask(x, fs, 0.8 * rb);
    otherwise
        error('Unsupported filter method: %s', filterName);
end
end

function y = applyOptimizerDetrend(x, detrendName, M)
name = lower(strtrim(detrendName));
switch name
    case 'none'
        y = x;
    case 'movmean_2m'
        win = max(3, round(2 * M));
        kernel = ones(win, 1) / win;
        y = x - conv(x, kernel, 'same');
    otherwise
        error('Unsupported detrend method: %s', detrendName);
end
end

function y = applyOptimizerClip(x, clipName)
name = lower(strtrim(clipName));
switch name
    case 'none'
        y = x;
    case 'winsor_q0p005'
        lo = quantileLinear(x, 0.005);
        hi = quantileLinear(x, 0.995);
        y = min(max(x, lo), hi);
    otherwise
        error('Unsupported clip method: %s', clipName);
end
end

function [sig, modSig, offset] = applyLagOptimizer(sigIn, modIn, lag)
lag = round(lag);
if lag > 0
    sig = sigIn(1:end-lag);
    modSig = modIn(1+lag:end);
    offset = 0;
elseif lag < 0
    k = -lag;
    sig = sigIn(1+k:end);
    modSig = modIn(1:end-k);
    offset = k;
else
    sig = sigIn;
    modSig = modIn;
    offset = 0;
end
end

function ev = evaluateOptimizerPhase(sig, modSig, phaseZeroBased, thresholdName, invertFlag, M)
ev = struct();
ev.valid = false;
ev.bits = [];
ev.xp = [];
ev.xm = [];
ev.snre_asym_xp = NaN;
ev.snre_asym_sym = NaN;

idx = (phaseZeroBased+1):M:numel(sig);
hs = sig(idx);
ms = modSig(idx);
n = min(numel(hs), numel(ms));
if n < 100
    return;
end
hs = hs(1:n);
ms = ms(1:n);

switch lower(strtrim(thresholdName))
    case 'mean'
        th = mean(ms);
    case 'median'
        th = median(ms);
    otherwise
        return;
end

bits = ms > th;
if invertFlag
    bits = ~bits;
end

p = mean(bits);
if p < 0.05 || p > 0.95
    return;
end

xp = hs(bits);
xm = hs(~bits);
if numel(xp) < 4 || numel(xm) < 4
    return;
end

sd_p = std(xp);
sd_m = std(xm);
if ~isfinite(sd_p) || sd_p <= 0
    return;
end

mu_p = mean(xp);
mu_m = mean(xm);

delta = abs(mu_p - mu_m)^2;
snre_asym_xp = delta / (4 * sd_p^2 + 1e-18);
snre_asym_sym = delta / (2 * (sd_p^2 + sd_m^2) + 1e-18);

ev.valid = true;
ev.bits = bits;
ev.xp = xp;
ev.xm = xm;
ev.snre_asym_xp = snre_asym_xp;
ev.snre_asym_sym = snre_asym_sym;
end

function y = fftLowpassMask(x, fs, cutoffHz)
if cutoffHz <= 0
    y = zeros(size(x));
    return;
end

xcol = x(:);
N = numel(xcol);
X = fft(xcol);
f = (0:N-1)' * (fs / N);
mask = (f <= cutoffHz) | (f >= (fs - cutoffHz));
ycol = real(ifft(X .* double(mask)));
y = reshape(ycol, size(x));
end

function qv = quantileLinear(x, q)
xs = sort(x(:));
n = numel(xs);
if n == 0
    qv = NaN;
    return;
end
if n == 1
    qv = xs(1);
    return;
end

q = min(max(q, 0), 1);
pos = 1 + (n - 1) * q;
lo = floor(pos);
hi = ceil(pos);
if lo == hi
    qv = xs(lo);
else
    qv = xs(lo) + (pos - lo) * (xs(hi) - xs(lo));
end
end

function SNR_C = resolveClassicalLimit(resultMeta, runDir, channelName)
if isfinite(resultMeta.jsonSNR_C)
    SNR_C = resultMeta.jsonSNR_C;
    return;
end

SNR_C = NaN;
sumPath = fullfile(runDir, 'processed_summary.json');
if exist(sumPath, 'file') == 2
    s = jsondecode(fileread(sumPath));
    if isfield(s, channelName) && isfield(s.(channelName), 'SNR_C')
        SNR_C = double(s.(channelName).SNR_C);
    end
end
end

function tf = parseBoolValue(v, defaultVal)
if nargin < 2
    defaultVal = false;
end

if islogical(v)
    tf = logical(v);
    return;
end
if isnumeric(v)
    tf = v ~= 0;
    return;
end

s = lower(strtrim(char(string(v))));
if any(strcmp(s, {'true', '1', 'yes'}))
    tf = true;
elseif any(strcmp(s, {'false', '0', 'no'}))
    tf = false;
else
    tf = logical(defaultVal);
end
end

function out = normalizeModForPlot(x)
mx = max(abs(x));
if ~isfinite(mx) || mx <= 0
    out = zeros(size(x));
else
    out = x ./ mx;
end
end

function key = runFieldKey(runIdx)
key = sprintf('r%d', round(runIdx));
end

function pos = computeInitialFigurePosition(targetSize)
monitors = get(groot, 'MonitorPositions');
if isempty(monitors)
    pos = [60 60 targetSize(1) targetSize(2)];
    return;
end

[~, idx] = max(monitors(:,3) .* monitors(:,4));
m = monitors(idx, :);

margin = 30;
maxW = max(700, m(3) - 2 * margin);
maxH = max(520, m(4) - 2 * margin);
w = min(targetSize(1), maxW);
h = min(targetSize(2), maxH);
x = m(1) + (m(3) - w) / 2;
y = m(2) + (m(4) - h) / 2;
pos = round([x y w h]);
end

function enforceFigureBounds(fig)
if ~ishandle(fig)
    return;
end

monitors = get(groot, 'MonitorPositions');
if isempty(monitors)
    return;
end

pos = get(fig, 'Position');
center = [pos(1) + pos(3)/2, pos(2) + pos(4)/2];
m = pickMonitorForPoint(monitors, center);

margin = 20;
maxW = max(600, m(3) - 2 * margin);
maxH = max(450, m(4) - 2 * margin);
newW = min(pos(3), maxW);
newH = min(pos(4), maxH);
newX = min(max(pos(1), m(1) + margin), m(1) + m(3) - newW - margin);
newY = min(max(pos(2), m(2) + margin), m(2) + m(4) - newH - margin);
newPos = round([newX newY newW newH]);

if any(abs(newPos - pos) > 0.5)
    set(fig, 'Position', newPos);
end
end

function m = pickMonitorForPoint(monitors, point)
for i = 1:size(monitors, 1)
    cand = monitors(i, :);
    if point(1) >= cand(1) && point(1) <= cand(1) + cand(3) && ...
       point(2) >= cand(2) && point(2) <= cand(2) + cand(4)
        m = cand;
        return;
    end
end

[~, idx] = max(monitors(:,3) .* monitors(:,4));
m = monitors(idx, :);
end

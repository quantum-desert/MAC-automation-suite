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

bestRuns = struct('S1', 20, 'S2', 81);
if exist(resultsJson, 'file') == 2
    try
        results = jsondecode(fileread(resultsJson));
        if isfield(results, 'best_by_channel')
            if isfield(results.best_by_channel, 'S1') && isfield(results.best_by_channel.S1, 'run_index')
                bestRuns.S1 = double(results.best_by_channel.S1.run_index);
            end
            if isfield(results.best_by_channel, 'S2') && isfield(results.best_by_channel.S2, 'run_index')
                bestRuns.S2 = double(results.best_by_channel.S2.run_index);
            end
        end
    catch ME
        warning('Could not parse results JSON (%s). Using fallback best-run defaults.', ME.message);
    end
end

constants = defaultConstantsLocal();
channelMap = defaultChannelMap();

fig = figure('Name', 'Best Dataset Visualizer (Standalone)', ...
             'Color', 'w', ...
             'NumberTitle', 'off', ...
             'Position', [60 60 1600 920]);

tg = uitabgroup(fig, 'Position', [0 0 1 1]);
app = struct();
app.dataRoot = dataRoot;
app.resultsJson = resultsJson;
app.constants = constants;
app.channelMap = channelMap;
app.runInfo = runInfo;
app.bestRuns = bestRuns;
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
            'Position', [0.015 0.955 0.10 0.03]);

        popup = uicontrol(tab, 'Style', 'popupmenu', ...
            'String', appState.runInfo.labels, ...
            'Units', 'normalized', ...
            'Position', [0.115 0.958 0.15 0.03], ...
            'Callback', @(~,~)refreshChannel(channelName));

        uicontrol(tab, 'Style', 'pushbutton', ...
            'String', 'Refresh', ...
            'Units', 'normalized', ...
            'Position', [0.275 0.958 0.08 0.03], ...
            'Callback', @(~,~)refreshChannel(channelName));

        uicontrol(tab, 'Style', 'pushbutton', ...
            'String', 'Jump To Best', ...
            'Units', 'normalized', ...
            'Position', [0.362 0.958 0.10 0.03], ...
            'Callback', @(~,~)jumpToBest(channelName));

        statsText = uicontrol(tab, 'Style', 'text', ...
            'String', 'Loading...', ...
            'Units', 'normalized', ...
            'BackgroundColor', 'w', ...
            'HorizontalAlignment', 'left', ...
            'Position', [0.475 0.954 0.51 0.04]);

        tl = tiledlayout(tab, 2, 2, ...
            'Units', 'normalized', ...
            'Position', [0.02 0.04 0.96 0.89], ...
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

        try
            info = computeChannelView(runDir, runIdx, channelName, app.channelMap.(channelName), app.constants);
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

function info = computeChannelView(runDir, runIdx, channelName, map, constants)
[t_homo, A_homo] = loadScopeCsv(runDir, runIdx, map.homodyneChannel);
[t_mod, A_mod] = loadScopeCsv(runDir, runIdx, map.modChannel);

L = min([numel(t_homo), numel(A_homo), numel(t_mod), numel(A_mod)]);
t_homo = t_homo(1:L);
A_homo = A_homo(1:L);
A_mod = A_mod(1:L);

A_mod_d = A_mod ./ max(A_mod);
A_mod_d = A_mod_d > mean(A_mod_d);
A_homo = A_homo - mean(A_homo);

delta_t = t_homo(2) - t_homo(1);
Fs = 1 / delta_t;
Fn = Fs / 2;
M = round(Fs / constants.Rb);
N = floor((t_homo(end)-t_homo(1)) * constants.Rb);

A_homo_dt = A_homo - movmean(A_homo, 2 * M);
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
    ds_mod = A_mod_d(idx);

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
ds_mod = A_mod_d(sample_idx);

Xp = dsA(ds_mod);
Xm = dsA(~ds_mod);
if isempty(Xp) || std(Xp) == 0
    SNRe = NaN;
else
    SNRe = (abs(mean(Xp)-mean(Xm)))^2 / (4 * std(Xp)^2);
end

SNR_C = NaN;
sumPath = fullfile(runDir, 'processed_summary.json');
if exist(sumPath, 'file') == 2
    s = jsondecode(fileread(sumPath));
    if isfield(s, channelName) && isfield(s.(channelName), 'SNR_C')
        SNR_C = double(s.(channelName).SNR_C);
    end
end

fft_mod = fftCalc(A_mod, Fs);
fft_filt = fftCalc(A_homo_filt, Fs);

info = struct();
info.runDir = runDir;
info.runIdx = runIdx;
info.channelName = channelName;
info.constants = constants;
info.report = struct('Fs', Fs, 'Fn', Fn, 'M', M, 'N', N, 'delta_t', delta_t);

info.t_homo = t_homo;
info.A_homo = A_homo;
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

function renderChannel(tabState, info, runIdx, channelName, bestRun)
axTime = tabState.axTime;
axHist = tabState.axHist;
axFFT = tabState.axFFT;
axScan = tabState.axScan;

cla(axTime); cla(axHist); cla(axFFT); cla(axScan);

lim = min(1000, numel(info.t_homo));
lim_ds = min(max(1, floor(lim / info.report.M)), numel(info.dst));

plot(axTime, info.t_homo(1:lim), info.A_homo(1:lim), 'LineWidth', 1.5, 'DisplayName', 'Homodyne (Raw)');
hold(axTime, 'on');
plot(axTime, info.t_homo(1:lim), 5*info.A_homo_filt(1:lim), 'LineWidth', 1.5, 'DisplayName', 'Homodyne (Filt x5)');
plot(axTime, info.t_mod(1:lim), 0.5*double(info.A_mod_d(1:lim)), 'LineWidth', 1.5, 'DisplayName', 'Modulation (digital/2)');
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
plot(axFFT, info.fft_filt(:,1), info.fft_filt(:,2), 'LineWidth', 1.3, 'DisplayName', 'Filtered Homodyne');
xlim(axFFT, [0 100]);
ylabel(axFFT, 'log|FFT|');
xlabel(axFFT, 'Frequency (kHz)');
title(axFFT, sprintf('%s Frequency Domain', channelName));
grid(axFFT, 'on'); legend(axFFT, 'Location', 'best');

stem(axScan, info.scanPhase, info.scanSNR, 'filled', 'DisplayName', 'Scan SNR');
hold(axScan, 'on');
xline(axScan, info.bestPhase, '--r', 'LineWidth', 1.4, 'DisplayName', sprintf('Best phase = %d', info.bestPhase));
xlabel(axScan, 'Start phase index');
ylabel(axScan, 'SNRe metric');
title(axScan, sprintf('%s Phase Scan (M = %d)', channelName, info.report.M));
grid(axScan, 'on'); legend(axScan, 'Location', 'best');

if isfinite(info.SNR_C)
    margin = info.SNRe - info.SNR_C;
    flag = 'below classical';
    if margin > 0
        flag = 'BEATS CLASSICAL';
    end
    tabState.statsText.String = sprintf([ ...
        '%s run %05d | default best run = %05d | SNRe = %.6f | SNR_C = %.6f | margin = %+0.6f (%s) | best phase = %d | M = %d'], ...
        channelName, runIdx, bestRun, info.SNRe, info.SNR_C, margin, flag, info.bestPhase, info.report.M);
else
    tabState.statsText.String = sprintf('%s run %05d | default best run = %05d | SNRe = %.6f | best phase = %d | M = %d', ...
        channelName, runIdx, bestRun, info.SNRe, info.bestPhase, info.report.M);
end
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

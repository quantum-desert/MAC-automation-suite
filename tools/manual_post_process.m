function out = manual_post_process(independent)
%MANUAL_POST_PROCESS Manual post-processing skeleton for two explicit datasets.
% Edit cfg.<channel>.pipeline fields to manually tune each stage.
% args
% independent = true | false
% ^ param controls: do we apply optimization from prior step to master
% dataset before sweeping next param?
if(nargin<1)
    independent = false;
end

% override structure defines which optimization steps to skip
%  (apply known best values)

override = struct();


% filters (causal)
override.causal_filt.s1.skip = true;
override.causal_filt.s1.bestLP = 0.99298246;
override.causal_filt.s1.bestHP = 0.98690958;

override.causal_filt.s2.skip = true;
override.causal_filt.s2.bestLP = 0.99298246;
override.causal_filt.s2.bestHP = 0.98690958;

% detrend
override.detrend.s1.skip = true;
override.detrend.s1.window = 3;

override.detrend.s2.skip = true;
override.detrend.s2.window = 3;

% phase
override.phase.s1.skip = true;
override.phase.s1.best_phase = 231;

override.phase.s2.skip = true;
override.phase.s2.best_phase = 264;

% lag
override.lag.s1.skip = true;
override.lag.s1.best_lag = 6;

override.lag.s2.skip = true;
override.lag.s2.best_lag = 6;

% % override sweeping set
set_skip_fields(override,false);


% generate config
cfg = struct();


%% Explicit dataset roots (best S1/S2 from Advantage_Data/Deterministic)
% cfg.paths.s1_run_dir = ['/Users/agentatom/Library/CloudStorage/OneDrive-Umich/' ...
%     'GraduateSchool/UM/QE_LAB/QINET/data/codex_processing/Advantage_Data/' ...
%     'Deterministic/positive_margin_4-22_batch2/batch_2/run_00151'];
% cfg.paths.s2_run_dir = ['/Users/agentatom/Library/CloudStorage/OneDrive-Umich/' ...
%     'GraduateSchool/UM/QE_LAB/QINET/data/codex_processing/Advantage_Data/' ...
%     'Deterministic/positive_margin_4-20/batch_4/run_01082'];


cfg.paths.s1_run_dir = ['/Users/agentatom/Library/CloudStorage/OneDrive-Umich/GraduateSchool/UM/QE_LAB/QINET/data/codex_processing/NB_sweep_Data/Pb_1227uW_S1_batch_2_run_00440'];
cfg.paths.s2_run_dir = ['/Users/agentatom/Library/CloudStorage/OneDrive-Umich/GraduateSchool/UM/QE_LAB/QINET/data/codex_processing/NB_sweep_Data/Pb_1227uW_S2_batch_2_run_00350'];
%% Channel file mapping (MAC convention)
% S1: homodyne from scope_*_2.csv, modulation from scope_*_1.csv
% S2: homodyne from scope_*_3.csv, modulation from scope_*_4.csv
cfg.s1.homo_channel = 2;
cfg.s1.mod_channel = 1;
cfg.s2.homo_channel = 3;
cfg.s2.mod_channel = 4;

%% Pipeline configuration (edit these manually)
% Allowed stage modes are examples; add your own in helper switches below.
cfg.s1.pipeline = default_pipeline();
cfg.s2.pipeline = default_pipeline();

% Run both datasets init
cfg.verbose=false;
out.s1 = run_single_dataset(cfg.paths.s1_run_dir, cfg.s1, 'S1',cfg.verbose);
out.s2 = run_single_dataset(cfg.paths.s2_run_dir, cfg.s2, 'S2',cfg.verbose);
% out.cfg = cfg; % return cfg for debugging

% update config settings based on run
% Note: do not use trim_end + long transient filter
cfg.s1.pipeline.M = floor(out.s1.fs/cfg.s1.pipeline.Rb);
cfg.s1.pipeline.lag = 0; % -1
cfg.s1.pipeline.phase = 7;
cfg.s1.pipeline.filter.N = cfg.s1.pipeline.M;

cfg.s2.pipeline.M = floor(out.s2.fs/cfg.s2.pipeline.Rb);
cfg.s2.pipeline.lag = 1;
cfg.s2.pipeline.phase = 5;
cfg.s2.pipeline.filter.N = cfg.s2.pipeline.M;



% initialize advantage tracker (adv_db after each applied step)
out.tracker.s1.baseline = out.s1.adv_db;
out.tracker.s2.baseline = out.s2.adv_db;

%% ---- pipeline manual sweep per channel ----

%%  manual filter sweep - LP + HP chain


disp(" ");
disp("----- Filter Sweep -----");
cfg.verbose = false;

% S1
[out,cfg] = causal_filter(out,cfg,override,'s1');

% S2
[out,cfg] = causal_filter(out,cfg,override,'s2');

% simple_summary(out);








%% manual detrend window sweep
disp(" ");
disp("----- Detrend Sweep -----");
cfg.verbose = false;

% S1
[out,cfg] = detrend(out,cfg,override,'s1');

% S2
[out,cfg] = detrend(out,cfg,override,'s2');

%% manual lag sweep

disp(" ");
disp("----- Lag Sweep -----");
cfg.verbose = true;
% S1
[out,cfg] = lag(out,cfg,override,'s1');

% S2
[out,cfg] = lag(out,cfg,override,'s2');



%% manual phase sweep


disp(" ");
disp("----- Phase Sweep -----");
cfg.verbose = true;
% S1
[out,cfg] = phase(out,cfg,override,'s1');

% S2
[out,cfg] = phase(out,cfg,override,'s2');




%% Simple summary
simple_summary(out);

% load P_b from processed.mat (stored in W, reported in uW)
pb_s1_uW = load_pb_uW(cfg.paths.s1_run_dir);
pb_s2_uW = load_pb_uW(cfg.paths.s2_run_dir);

% tracker results
fprintf('\n%-12s  %12s  %12s\n', 'Step', 'S1 adv (dB)', 'S2 adv (dB)');
fprintf('%s\n', repmat('-', 1, 40));
steps = {'baseline','filter','detrend','phase','lag'};
for k = 1:numel(steps)
    s = steps{k};
    v1 = nan; v2 = nan;
    if isfield(out.tracker.s1, s), v1 = out.tracker.s1.(s); end
    if isfield(out.tracker.s2, s), v2 = out.tracker.s2.(s); end
    fprintf('%-12s  %+12.4f  %+12.4f\n', s, v1, v2);
end
fprintf('\n');

% pretty results
fprintf('\n%-20s  %14s  %14s\n', 'Parameter', 'S1', 'S2');
fprintf('%s\n', repmat('-', 1, 52));
fprintf('%-20s  %14.8f  %14.8f\n', 'LP filter ratio',  cfg.s1.pipeline.filter.ratio,    cfg.s2.pipeline.filter.ratio);
fprintf('%-20s  %14.8f  %14.8f\n', 'HP filter ratio',  cfg.s1.pipeline.filter.ratio_hp, cfg.s2.pipeline.filter.ratio_hp);
fprintf('%-20s  %14.0f  %14.0f\n', 'Detrend window',   cfg.s1.pipeline.detrend.window,  cfg.s2.pipeline.detrend.window);
fprintf('%-20s  %14.0f  %14.0f\n', 'Phase',            cfg.s1.pipeline.phase,           cfg.s2.pipeline.phase);
fprintf('%-20s  %14.0f  %14.0f\n', 'Lag',              cfg.s1.pipeline.lag,             cfg.s2.pipeline.lag);
fprintf('\n');

% tab-separated results (paste into Excel)
fprintf('\nPrinting order: row 1 = S1; row 2 = S2\n');
fprintf('\nP_b (uW)\tLP Ratio\tHP Ratio\tDetrend Window\tPhase\tLag\tSNRe Adv. (dB)\n');
fprintf('%.4f\t\t%.8f\t%.8f\t%d\t\t%d\t%d\t%.4f\n', ...
    pb_s1_uW, cfg.s1.pipeline.filter.ratio, cfg.s1.pipeline.filter.ratio_hp, ...
    cfg.s1.pipeline.detrend.window, cfg.s1.pipeline.phase, cfg.s1.pipeline.lag, out.s1.adv_db);
fprintf('%.4f\t\t%.8f\t%.8f\t%d\t\t%d\t%d\t%.4f\n', ...
    pb_s2_uW, cfg.s2.pipeline.filter.ratio, cfg.s2.pipeline.filter.ratio_hp, ...
    cfg.s2.pipeline.detrend.window, cfg.s2.pipeline.phase, cfg.s2.pipeline.lag, out.s2.adv_db);
fprintf('\n');
end

function p = default_pipeline()

p.detrend.mode = 'movmean_subtract'; % 'none' | 'movmean_subtract'
p.detrend.window_mult_M = 2;

p.clip.mode = 'none';             % 'none' | 'winsor'
p.clip.q = 0.005;

p.threshold.mode = 'mean';        % 'mean' | 'median'
p.invert_bits = true;

p.metric = 'asym_sym';             % 'asym_xp' | 'asym_sym'
p.M = 16;
p.phase = 0;
p.lag = 0;
p.trim.mode = 'none';
p.trim.points = 0;

p.filter.mode = 'ratio_hp_lp_causal';   % 'none' | 'fft_lp_ratio' | 'fft_lp_ratio_causal' | 'ratio_hp_lp_causal' |  'moving_average' | 'boxcar'
p.filter.ratio = 0.6;             % cutoff = ratio * Rb
p.filter.ratio_hp = 0.75;         % hp cutoff = ratio * Rb
p.filter.window = 8;              % for moving_average
p.filter.cutoff_hz = 6000;        % for causal_1pole_lp
p.filter.N = p.M;                 % for boxcar window length

p.gridSize=20;
p.gridRange = [0.4 1.3];
p.Rb=8e3; % bit rate

end

% Precompute everything up to filtering (done once)
function pre = precompute_dataset(run_dir, ch_cfg)
    [homo_path, mod_path] = resolve_scope_paths(run_dir, ch_cfg.homo_channel, ch_cfg.mod_channel);
    [t_h, x_h] = read_scope_csv(homo_path);
    [~,  x_m] = read_scope_csv(mod_path);
    pre.x_h = x_h;
    pre.x_m = x_m;
    pre.fs  = infer_fs(t_h);
    pre.Rb  = pre.fs / ch_cfg.pipeline.M;
end

function snre = eval_filter(pre, ch_cfg, lp_ratio, hp_ratio)
    ch_cfg.pipeline.filter.ratio    = lp_ratio;
    ch_cfg.pipeline.filter.ratio_hp = hp_ratio;
    
    x_f = apply_filter_stage(pre.x_h, pre.fs, pre.Rb, ch_cfg.pipeline.filter);
    x_d = apply_detrend_stage(x_f, ch_cfg.pipeline.M, ch_cfg.pipeline.detrend);
    [x_l, m_l] = apply_lag_stage(x_d, pre.x_m, ch_cfg.pipeline.lag);
    [xs, ms] = downsample_with_phase(x_l, m_l, ch_cfg.pipeline.phase, ch_cfg.pipeline.M);
    bits = threshold_bits(ms, ch_cfg.pipeline.threshold.mode, ch_cfg.pipeline.invert_bits);
    xp = xs(bits); xm = xs(~bits);
    metrics = compute_snre_metrics(xp, xm);
    snre = metrics.(ch_cfg.pipeline.metric);
end

function result = run_single_dataset(run_dir, ch_cfg, channel_name,verbose)
[homo_path, mod_path] = resolve_scope_paths(run_dir, ch_cfg.homo_channel, ch_cfg.mod_channel);
[t_h, x_h] = read_scope_csv(homo_path);
[t_m, x_m] = read_scope_csv(mod_path);

assert(numel(t_h) == numel(x_h), 'Invalid homodyne data shape.');
assert(numel(t_m) == numel(x_m), 'Invalid modulation data shape.');

fs = infer_fs(t_h);

% Stage 1: filtering
x_f = apply_filter_stage(x_h, fs, ch_cfg.pipeline.Rb, ch_cfg.pipeline.filter);

% Stage 2: detrending
x_d = apply_detrend_stage(x_f, ch_cfg.pipeline.M, ch_cfg.pipeline.detrend);


% Stage 3: clipping / outlier handling
% x_c = apply_clip_stage(x_d, ch_cfg.pipeline.clip);
% skip clip
x_c = x_d;

% Stage 4: lag alignment
[x_l, m_l] = apply_lag_stage(x_c, x_m, ch_cfg.pipeline.lag);
% % skip lag
% x_l = x_c;
% m_l = x_m;

% Stage 5: trimming
% [x_t, m_t] = apply_trim_stage(x_l, m_l, ch_cfg.pipeline.M, ch_cfg.pipeline.trim);
%skip trim
x_t = x_l;
m_t = m_l;


% Stage 6: phase-select and downsample
[xs, ms] = downsample_with_phase(x_t, m_t, ch_cfg.pipeline.phase, ch_cfg.pipeline.M);


% Stage 7: threshold and class split
bits = threshold_bits(ms, ch_cfg.pipeline.threshold.mode, ch_cfg.pipeline.invert_bits);
xp = xs(bits);
xm = xs(~bits);

% Stage 8: SNRe estimation
metrics = compute_snre_metrics(xp, xm);
result.snre = metrics.(ch_cfg.pipeline.metric);
result.metrics = metrics;
result.n_points = numel(xs);
result.fs = fs;
result.run_dir = run_dir;
result.channel = channel_name;
result.paths.homo = homo_path;
result.paths.mod = mod_path;
result.debug.raw = x_h;
result.debug.filtered = x_f;
result.debug.after_trim = x_t;
result.debug.ds.homo = xs;
result.debug.class.xp = xp;
result.debug.class.xm = xm;


% Stage 9 (TODO): Estimate MI (soft decoding)

% Optional: retrieve classical SNR (SNRc) from processed_summary.json.
[result.snr_c, result.snr_c_source] = load_snr_c_from_processed_summary(run_dir, channel_name);
if isfinite(result.snr_c)
    result.margin = result.snre - result.snr_c;
    result.adv_db = 10 * log10(max(result.snre, eps) / result.snr_c);
else
    result.margin = nan;
    result.adv_db = nan;
end

% if(verbose)
%     fprintf('%s done | run: %s | M=%d phase=%d lag=%d | SNRe=%.6f\n', ...
%         channel_name, run_dir, ch_cfg.pipeline.M, ch_cfg.pipeline.phase, ch_cfg.pipeline.lag, result.snre);
% end
% if isfinite(result.snr_c) && verbose
%     fprintf('%s SNRc: %.6f | margin: %+0.6f | adv(dB): %+0.6f\n', ...
%         channel_name, result.snr_c, result.margin, result.adv_db);
% elseif verbose
%     fprintf('%s SNRc: n/a (processed_summary.json missing or invalid)\n', channel_name);
% end
end


function [homo_path, mod_path] = resolve_scope_paths(run_dir, homo_ch, mod_ch)
homo_matches = dir(fullfile(run_dir, sprintf('scope_*_%d.csv', homo_ch)));
mod_matches = dir(fullfile(run_dir, sprintf('scope_*_%d.csv', mod_ch)));
assert(~isempty(homo_matches), 'No homodyne scope file found in %s', run_dir);
assert(~isempty(mod_matches), 'No modulation scope file found in %s', run_dir);
homo_path = fullfile(homo_matches(1).folder, homo_matches(1).name);
mod_path = fullfile(mod_matches(1).folder, mod_matches(1).name);
end

function [t, x] = read_scope_csv(path)
mat = readmatrix(path, 'NumHeaderLines', 4);
assert(size(mat,2) >= 2, 'Scope CSV has <2 columns: %s', path);
t = mat(:,1);
x = mat(:,2);
end

function fs = infer_fs(t)
assert(numel(t) >= 3, 'Need at least 3 time points to infer fs.');
dt = mean(diff(t(1:min(end,1000))));
fs = 1.0 / dt;
end

function y = apply_filter_stage(x, fs, Rb, fcfg)
switch lower(string(fcfg.mode))
    case "none"
        y = x;
    case "fft_lp_ratio"
        cutoff = fcfg.ratio * Rb;
        y = fft_lowpass(x, fs, cutoff);

    case "ratio_hp_lp_causal"
        % low pass
        cutoff = fcfg.ratio * Rb;
        [z,p,k] = butter(12, cutoff/(fs/2), "low");
        sos = zp2sos(z,p,k);           % convert to SOS
        y = sosfilt(sos, x);           % numerically stable filtering

        % high pass
        cutoff = fcfg.ratio_hp * Rb;
        [z,p,k] = butter(5, cutoff/(fs/2), "high");
        sos = zp2sos(z,p,k);
        y = sosfilt(sos, y);

    case "fft_lp_ratio_causal"
        cutoff = fcfg.ratio * Rb;
        [b,a] = butter(8,cutoff/(fs/2),"low");
        y = filter(b,a,x);

    case "moving_average"
        w = max(1, round(fcfg.window));
        y = movmean(x, w);
    case "causal_1pole_lp"
        y = causal_one_pole_lowpass(x, fs, fcfg.cutoff_hz);
    case "boxcar"
        b = ones(1,fcfg.N/2)/(fcfg.N/2); a=1;
        y = filter(b,a,x);
    otherwise
        error('Unknown filter mode: %s', string(fcfg.mode));
end
end

function y = apply_detrend_stage(x, M, dcfg)
switch lower(string(dcfg.mode))
    case "none"
        y = x;
    case "movmean_subtract"
        w = max(3, round(dcfg.window_mult_M * M));
        y = x - movmean(x, w);
    case "custom_movmean_subtract"
        w = dcfg.window;
        y = x - movmean(x,w);
    otherwise
        error('Unknown detrend mode: %s', string(dcfg.mode));
end
end

function y = apply_clip_stage(x, ccfg)
switch lower(string(ccfg.mode))
    case "none"
        y = x;
    case "winsor"
        q = ccfg.q;
        lo = quantile(x, q);
        hi = quantile(x, 1-q);
        y = min(max(x, lo), hi);
    otherwise
        error('Unknown clip mode: %s', string(ccfg.mode));
end
end

function [x2, m2] = apply_lag_stage(x, m, lag)
if lag > 0
    x2 = x(1:end-lag);
    m2 = m(1+lag:end);
elseif lag < 0
    k = -lag;
    x2 = x(1+k:end);
    m2 = m(1:end-k);
else
    x2 = x;
    m2 = m;
end
n = min(numel(x2), numel(m2));
x2 = x2(1:n);
m2 = m2(1:n);
end

function [x2, m2] = apply_trim_stage(x, m, M, tcfg)
mode = lower(string(tcfg.mode));
trim_raw = round(tcfg.points * M);
n = min(numel(x), numel(m));
x = x(1:n);
m = m(1:n);

switch mode
    case "none"
        idx = 1:n;
    case "trim_start"
        idx = (1+trim_raw):n;
    case "trim_end"
        idx = 1:(n-trim_raw);
    otherwise
        error('Unknown trim mode: %s', string(tcfg.mode));
end

assert(~isempty(idx), 'Trim removed all points.');
x2 = x(idx);
m2 = m(idx);
end

function [xs, ms] = downsample_with_phase(x, m, phase, M)
phase = mod(phase, M);
idx = (1+phase):M:numel(x);
xs = x(idx);
ms = m(idx);
end

function bits = threshold_bits(m, threshold_mode, invert_bits)
switch lower(string(threshold_mode))
    case "mean"
        th = mean(m);
    case "median"
        th = median(m);
    otherwise
        error('Unknown threshold mode: %s', string(threshold_mode));
end
bits = m > th;
if invert_bits
    bits = ~bits;
end
end

function metrics = compute_snre_metrics(xp, xm)
assert(~isempty(xp) && ~isempty(xm), 'Class split is empty. Adjust threshold/phase/lag.');
mu_p = mean(xp);
mu_m = mean(xm);
var_p = var(xp, 1);
var_m = var(xm, 1);
dmu2 = (abs(mu_p - mu_m))^2;
metrics.asym_xp = dmu2 / (4*var_p + eps);
metrics.asym_sym = dmu2 / (2*(var_p + var_m) + eps);
end

function y = fft_lowpass(x, fs, cutoff_hz)
if cutoff_hz <= 0
    y = zeros(size(x));
    return;
end
n = numel(x);
f = (0:floor(n/2))' * (fs / n);
X = fft(x);
Xr = X(1:numel(f));
mask = (f <= cutoff_hz);
Xr_filt = Xr .* mask;

if rem(n,2) == 0
    Xfull = [Xr_filt; conj(Xr_filt(end-1:-1:2))];
else
    Xfull = [Xr_filt; conj(Xr_filt(end:-1:2))];
end

y = real(ifft(Xfull));
end

function y = causal_one_pole_lowpass(x, fs, cutoff_hz)
if cutoff_hz <= 0
    y = zeros(size(x));
    return;
end
dt = 1/fs;
tau = 1/(2*pi*cutoff_hz);
alpha = dt / (tau + dt);
y = zeros(size(x));
y(1) = x(1);
for k = 2:numel(x)
    y(k) = y(k-1) + alpha*(x(k)-y(k-1));
end
end

function h = plot_fft_from_outsx(ax, sx, label_name)
%PLOT_FFT_FROM_OUTSX Plot one-sided FFT from out.sx onto existing axes.
% Usage:
%   plot_fft_from_outsx(ax, out.s1)                       % default: after_trim
%   plot_fft_from_outsx(ax, out.s1, 'raw', 'S1 raw')
%   plot_fft_from_outsx(ax, out.s1, 'filtered', 'S1 filt')


if nargin < 3 || isempty(label_name)
    label_name = '';
end

signal_name = 'filtered'; % 'raw' | 'filtered' | 'after_trim'

% Pull signal from sx.debug.<signal_name>
assert(isfield(sx, 'debug') && isfield(sx.debug, signal_name), ...
    'sx.debug.%s not found.', signal_name);
x = sx.debug.(signal_name);
fs = sx.fs;

x = x(:) - mean(x, 'omitnan');
n = numel(x);
assert(n > 8, 'Signal too short for FFT.');

% Window + one-sided spectrum
w = hann(n);
X = fft(x .* w);
k = floor(n/2) + 1;
X = X(1:k);
f = (0:k-1)' * (fs / n);

mag = abs(X);
mag = mag ./ (max(mag) + eps);              % normalize to 0 dB peak
mag_db = 20 * log10(max(mag, 1e-12));       % floor for plotting

hold(ax, 'on');
h = plot(ax, f/1e3, mag_db, 'LineWidth', 1.2, 'DisplayName', label_name);


% Optional bit-rate marker if present
% if isfield(sx, 'rb') && ~isempty(sx.rb) && isfinite(sx.rb)
%     xline(ax, sx.rb/1e3, '--', 'Color', [0.2 0.2 0.2], ...
%         'LineWidth', 1.0, 'DisplayName', sprintf('%s R_b', label_name));
% end

grid(ax, 'on');
xlabel(ax, 'Frequency (kHz)');
ylabel(ax, 'Magnitude (dB, normalized)');
legend;
end

function pb_uW = load_pb_uW(run_dir)
%LOAD_PB_UW Load P_b (W) from physics_cfg.json and return in microwatts.
pb_uW = nan;
p = fullfile(run_dir, 'physics_cfg.json');
if ~isfile(p)
    warning('load_pb_uW: physics_cfg.json not found in %s', run_dir);
    return;
end
try
    j = jsondecode(fileread(p))
    if isfield(j, 'S1')
        pb_uW = double(j.S1.P_b) * 1e6;
    else
        warning('load_pb_uW: P_b not found in %s', p);
    end
catch e
    warning('load_pb_uW: failed to load %s — %s', p, e.message);
end
end

function [snr_c, source] = load_snr_c_from_processed_summary(run_dir, channel_name)
%LOAD_SNRC_FROM_PROCESSED_SUMMARY Read SNR_C for a selected run/channel.
snr_c = nan;
source = 'missing';
p = fullfile(run_dir, 'processed_summary.json');
if ~isfile(p)
    return;
end
try
    j = jsondecode(fileread(p));
    if isfield(j, channel_name) && isstruct(j.(channel_name)) && isfield(j.(channel_name), 'SNR_C')
        snr_c = double(j.(channel_name).SNR_C);
        source = p;
    else
        source = 'invalid_structure';
    end
catch
    source = 'parse_error';
end
end

function h = plot_time_slice_with_downsample(ax, sx, varargin)
%PLOT_TIME_SLICE_WITH_DOWNSAMPLE Visualize a time-domain slice + downsample points.
%
% Required:
%   ax : axes handle
%   sx : output struct from run_single_dataset / manual_post_process (e.g., out.s1)
%
% Name-value options:
%   'SignalName'   : 'raw' | 'filtered' | 'after_trim'   (default: 'after_trim')
%   'StartIndex'   : 1-based slice start index           (default: 1)
%   'NumSamples'   : number of samples in slice          (default: 2000)
%   'Color'        : line color for waveform             (default: [0 0.447 0.741])
%   'MarkerColor'  : color for downsample markers        (default: [0.850 0.325 0.098])
%   'LineWidth'    : waveform line width                 (default: 1.1)
%   'MarkerSize'   : marker size                         (default: 24)
%   'ShowBitColor' : true/false color markers by bit     (default: true)
%
% Notes:
% - Uses sx.debug.<SignalName> for waveform.
% - Uses sx.pipeline (if present) or sx.M/sx.phase for downsample indexing.
% - If modulation is unavailable in sx.debug, bit coloring is skipped.

% -------- Parse inputs --------
p = inputParser;
p.addParameter('SignalName', 'after_trim');
p.addParameter('StartIndex', 1);
p.addParameter('NumSamples', 2000);
p.addParameter('Color', [0 0.447 0.741]);
p.addParameter('MarkerColor', [0.850 0.325 0.098]);
p.addParameter('LineWidth', 1.1);
p.addParameter('MarkerSize', 24);
p.addParameter('ShowBitColor', true);
p.parse(varargin{:});
o = p.Results;

% assert(isgraphics(ax, 'axes'), 'ax must be a valid axes handle.');
% assert(isfield(sx, 'debug') && isfield(sx.debug, o.SignalName), ...
%     'sx.debug.%s not found.', o.SignalName);

x = sx.debug.(o.SignalName);
x = x(:);
n = numel(x);

i1 = max(1, round(o.StartIndex));
i2 = min(n, i1 + round(o.NumSamples) - 1);
assert(i2 >= i1, 'Invalid slice bounds.');

idx_slice = (i1:i2).';
x_slice = x(idx_slice);

% Fs/time axis
if isfield(sx, 'fs') && ~isempty(sx.fs) && isfinite(sx.fs)
    fs = sx.fs;
    t_slice = (idx_slice - 1) / fs;
    xLabelText = 'Time (s)';
else
    fs = [];
    t_slice = idx_slice;
    xLabelText = 'Sample Index';
end

% -------- Get M and phase --------
M = [];
ph = [];

if isfield(sx, 'pipeline') && isstruct(sx.pipeline)
    if isfield(sx.pipeline, 'M'), M = sx.pipeline.M; end
    if isfield(sx.pipeline, 'phase'), ph = sx.pipeline.phase; end
end
if isempty(M) && isfield(sx, 'M'), M = sx.M; end
if isempty(ph) && isfield(sx, 'phase'), ph = sx.phase; end

assert(~isempty(M) && ~isempty(ph), ...
    'Could not find M/phase in sx. Add sx.pipeline.M and sx.pipeline.phase (or sx.M/sx.phase).');

M = round(M);
ph = mod(round(ph), M);

% -------- Downsample indices over full signal --------
idx_ds_full = (1 + ph):M:n;
in_slice = idx_ds_full >= i1 & idx_ds_full <= i2;
idx_ds = idx_ds_full(in_slice).';
x_ds = x(idx_ds);

if isempty(fs)
    t_ds = idx_ds;
else
    t_ds = (idx_ds - 1) / fs;
end

% -------- Optional bit coloring --------
bits = [];
if o.ShowBitColor
    if isfield(sx.debug, 'mod_after_trim')
        m = sx.debug.mod_after_trim(:);
        if numel(m) == n
            if isfield(sx, 'threshold_mode')
                thMode = string(sx.threshold_mode);
            else
                thMode = "mean";
            end
            if thMode == "median"
                th = median(m);
            else
                th = mean(m);
            end
            b = m > th;
            if isfield(sx, 'invert_bits') && sx.invert_bits
                b = ~b;
            end
            bits = b(idx_ds);
        end
    end
end

% -------- Plot --------
hold(ax, 'on');
% h.wave = plot(ax, t_slice, x_slice, 'LineWidth', o.LineWidth, 'Color', o.Color, ...
%     'DisplayName', sprintf('%s slice', o.SignalName));
h.wave = plot(ax, t_slice, x_slice, 'LineWidth', o.LineWidth, 'Color', o.Color, ...
    'HandleVisibility','off')
if isempty(bits)
    h.ds = scatter(ax, t_ds, x_ds, o.MarkerSize, 'filled', ...
        'DisplayName', sprintf('Downsampled (M=%d, ph=%d)', M, ph));
else
    c0 = [0.2 0.2 0.2];      % bit 0
    c1 = [0.85 0.1 0.1];     % bit 1
    h.ds0 = scatter(ax, t_ds(~bits), x_ds(~bits), o.MarkerSize, 'filled', ...
        'DisplayName', 'Downsample bit=0');
    h.ds1 = scatter(ax, t_ds(bits),  x_ds(bits),  o.MarkerSize, 'filled', ...
        'DisplayName', 'Downsample bit=1');
end

grid(ax, 'on');
xlabel(ax, xLabelText);
ylabel(ax, 'Amplitude');
title(ax, sprintf('Time Slice with Downsample Points (%s)', o.SignalName));
legend(ax, 'show');
end

function sweepr = filter_grid_search(lp,hp,sx,sx_fname,cfg,plot_opts)
% args
% sx = actual channel input structure
% sx_fname = dynamic field name, so oither structures with 'sx' as a
% field name can dynamically call it
% cfg = cfg struct with both channels
% set causal LP + HP chain

% output: sweepr
% only returns results of sweep - user responsibility to update
% appropriate config struct and run post process w/ updated vals
cfg.(sx_fname).pipeline.filter.mode = 'ratio_hp_lp_causal';

t_run = 10; % approx time in ms
t_total = t_run*length(lp)*length(hp); % ms
%  grid
SNRr = nan(length(lp),length(hp)); % (lp, hp, SNRe)
run_num = 0;

pre = precompute_dataset(sx.run_dir, cfg.(sx_fname));
for r_lp = 1:numel(lp)
    for r_hp = 1:numel(hp)
        SNRr(r_lp, r_hp) = eval_filter(pre, cfg.(sx_fname), lp(r_lp), hp(r_hp));
        % timing
        run_num = run_num + 1;
        % disp(strcat("Remaining time ~:",num2str(round(t_total-t_run*run_num,3))," ms"));
        
    end
end
fixedMin=min(SNRr(:));
fixedMax=max(SNRr(:));

% pick out max
[maxSnr, k] = max(SNRr(:));
[iLP, iHP] = ind2sub(size(SNRr), k);
bestLP = lp(iLP);  % row axis value
bestHP = hp(iHP);   % col axis value

if(plot_opts.visualize)
    % visualize coarse SNRe sweep space for 2X filter chain
    figure;
    hold on; theme light;
    imagesc(hp, lp, SNRr);  % cols->HP, rows->LP
    axis xy
    cb=colorbar; cb.Label.String = 'SNRe';
    xlabel('HP Ratio'); ylabel('LP Ratio');
    clim([fixedMin fixedMax]);
    title(plot_opts.title);
    % xlim([min(hp) max(hp)]); ylim([min(lp) max(lp)]);

    dx = mean(diff(hp));
    dy = mean(diff(lp));

    xlim([hp(1)-dx/2, hp(end)+dx/2])
    ylim([lp(1)-dy/2, lp(end)+dy/2])
    plot(bestHP, bestLP, 'rx', 'MarkerSize', 12, 'LineWidth', 2);
end

sweepr.bestLP=bestLP;
sweepr.bestHP=bestHP;
sweepr.SNRr=SNRr;
sweepr.maxSNR = maxSnr;
end

function [out,cfg] = causal_filter(out,cfg,override,select)

if(strcmp(select,'s1'))
    if(~override.causal_filt.s1.skip)
        if(cfg.verbose)
            disp(strcat("Sweeping Channel: ",select));
        end
        % S1
        %  coarse grid search
        lp1 = linspace(cfg.s1.pipeline.gridRange(1),cfg.s1.pipeline.gridRange(2),cfg.s1.pipeline.gridSize);
        hp1 = linspace(cfg.s1.pipeline.gridRange(1),cfg.s1.pipeline.gridRange(2),cfg.s1.pipeline.gridSize);

        plot_opts = struct();
        plot_opts.visualize = true;
        plot_opts.title= 'Coarse Search';
        sweeprCoarse = filter_grid_search(lp1,hp1,out.s1,'s1',cfg,plot_opts);

        % fine grid sweep
        % locate ridge window from top percentile
        prc = 10;
        thr = prctile(sweeprCoarse.SNRr(:), 100-prc);      % top prc%
        [r,c] = find(sweeprCoarse.SNRr >= thr);

        lp_lo = max(min(lp1(r)) - prc/1e2, min(lp1));
        lp_hi = min(max(lp1(r)) + prc/1e2, max(lp1));
        hp_lo = max(min(hp1(c)) - prc/1e2, min(hp1));
        hp_hi = min(max(hp1(c)) + prc/1e2, max(hp1));

        % --- pass 2: fine near transition ---
        plot_opts.title= 'Fine Search';
        lp2 = linspace(lp_lo, lp_hi, 2*cfg.s1.pipeline.gridSize);
        hp2 = linspace(hp_lo, hp_hi, 2*cfg.s1.pipeline.gridSize);
        sweeprFine = filter_grid_search(lp2,hp2,out.s1,'s1',cfg,plot_opts);

    else
        disp(strcat("Using pre-set filter params for channel: ",select))
        sweeprFine.bestLP = override.causal_filt.s1.bestLP;
        sweeprFine.bestHP = override.causal_filt.s1.bestHP;

    end
    % apply best filters
    cfg.s1.pipeline.filter.mode = 'ratio_hp_lp_causal';
    cfg.s1.pipeline.filter.ratio = sweeprFine.bestLP;
    cfg.s1.pipeline.filter.ratio_hp = sweeprFine.bestHP;
    out.s1 = run_single_dataset(cfg.paths.s1_run_dir, cfg.s1, 'S1',cfg.verbose);
    out.tracker.s1.filter = out.s1.adv_db;

    % report
    fprintf('\n(S1) Fine scan best:\nLP ratio = %.8f, HP ratio = %.8f', ...
        sweeprFine.bestLP, sweeprFine.bestHP);
    fprintf('\nSNRe = %.3f, Adv. (dB) = %.2f\n', ...
        out.s1.snre,out.s1.adv_db); disp(" ");

    % plot fft
    if(cfg.verbose)
        figure;ax=gca; grid off; theme light;
        plot_fft_from_outsx(ax,out.s1,strcat("fc_lp=",num2str(round(sweeprFine.bestLP,3)),";fc_hp=",num2str(round(sweeprFine.bestHP,3))));
        xlim([0 40]); ylim([-80 1]);
        title('fft: optimized causal bandpass filter')
    end
elseif(strcmp(select,'s2'))
    if(~override.causal_filt.s2.skip)
        if(cfg.verbose)
            disp(strcat("Sweeping Channel: ",select));
        end
        % S2
        %  coarse grid search
        lp1 = linspace(cfg.s2.pipeline.gridRange(1),cfg.s2.pipeline.gridRange(2),cfg.s2.pipeline.gridSize);
        hp1 = linspace(cfg.s2.pipeline.gridRange(1),cfg.s2.pipeline.gridRange(2),cfg.s2.pipeline.gridSize);

        plot_opts = struct();
        plot_opts.visualize = true;
        plot_opts.title= 'Coarse Search';
        sweeprCoarse = filter_grid_search(lp1,hp1,out.s2,'s2',cfg,plot_opts);

        % fine grid sweep
        % locate ridge window from top percentile
        prc = 10;
        thr = prctile(sweeprCoarse.SNRr(:), 100-prc);      % top prc%
        [r,c] = find(sweeprCoarse.SNRr >= thr);

        lp_lo = max(min(lp1(r)) - prc/1e2, min(lp1));
        lp_hi = min(max(lp1(r)) + prc/1e2, max(lp1));
        hp_lo = max(min(hp1(c)) - prc/1e2, min(hp1));
        hp_hi = min(max(hp1(c)) + prc/1e2, max(hp1));

        % --- pass 2: fine near transition ---
        plot_opts.title= 'Fine Search';
        lp2 = linspace(lp_lo, lp_hi, 2*cfg.s2.pipeline.gridSize);
        hp2 = linspace(hp_lo, hp_hi, 2*cfg.s2.pipeline.gridSize);
        sweeprFine = filter_grid_search(lp2,hp2,out.s2,'s2',cfg,plot_opts);

    else
        disp(strcat("Using pre-set filter params for channel: ",select))
        sweeprFine.bestLP = override.causal_filt.s2.bestLP;
        sweeprFine.bestHP = override.causal_filt.s2.bestHP;

    end
    % apply best filters
    cfg.s2.pipeline.filter.mode = 'ratio_hp_lp_causal';
    cfg.s2.pipeline.filter.ratio = sweeprFine.bestLP;
    cfg.s2.pipeline.filter.ratio_hp = sweeprFine.bestHP;
    out.s2 = run_single_dataset(cfg.paths.s2_run_dir, cfg.s2, 'S2',cfg.verbose);
    out.tracker.s2.filter = out.s2.adv_db;

    % report
    fprintf('\n(S2) Fine scan best:\nLP ratio = %.8f, HP ratio = %.8f', ...
        sweeprFine.bestLP, sweeprFine.bestHP);
    fprintf('\nSNRe = %.3f, Adv. (dB) = %.2f\n', ...
        out.s2.snre,out.s2.adv_db); disp(" ");

    if(cfg.verbose)
        % plot fft
        figure;ax=gca; grid off; theme light;
        plot_fft_from_outsx(ax,out.s2,strcat("fc_lp=",num2str(round(sweeprFine.bestLP,3)),";fc_hp=",num2str(round(sweeprFine.bestHP,3))));
        xlim([0 40]); ylim([-80 1]);
        title('fft: optimized causal bandpass filter')
    end
else
    disp('error');
    return;
end

end

function [out,cfg] = detrend(out,cfg,override,select)
if(strcmp(select,'s1'))
    if(~override.detrend.s1.skip)
        % options
        window_options = [1:3*cfg.s1.pipeline.M];
        SNRr = zeros(size(window_options));

        % mode for intra-bit window sizes
        cfg.s1.pipeline.detrend.mode = "custom_movmean_subtract";

        % Precompute once before detrend sweep
        pre = precompute_dataset(out.s1.run_dir, cfg.s1);
        pre_detrend.x_f  = apply_filter_stage(pre.x_h, pre.fs, pre.Rb, cfg.s1.pipeline.filter);
        pre_detrend.x_m  = pre.x_m;

        % Inner loop only runs detrend onward
        for w = 1:numel(window_options)
            x_d = apply_detrend_stage(pre_detrend.x_f, cfg.s1.pipeline.M, ...
                struct('mode','custom_movmean_subtract','window',window_options(w)));
            [x_l, m_l] = apply_lag_stage(x_d, pre_detrend.x_m, cfg.s1.pipeline.lag);
            [xs, ms]   = downsample_with_phase(x_l, m_l, cfg.s1.pipeline.phase, cfg.s1.pipeline.M);
            bits = threshold_bits(ms, cfg.s1.pipeline.threshold.mode, cfg.s1.pipeline.invert_bits);
            xp = xs(bits); xm = xs(~bits);
            SNRr(w) = compute_snre_metrics(xp, xm).(cfg.s1.pipeline.metric);
        end

        % extract max
        [~,idx] = max(SNRr); best_window = window_options(idx);

        % visualize SNRe trend
        if(cfg.verbose)
            figure;
            hold on; theme light;
            plot(window_options,SNRr,LineWidth=2);
            yline(out.s1.snr_c,'--','DisplayName','SNRc',LineWidth=2);
            xlabel('window size');
            ylabel('SNRe');
            title(strcat(select," Detrend Window Optimization; Best Window=",num2str(best_window)));
        end
    else
        best_window = override.detrend.s1.window;
    end
    % apply best window configuration
    cfg.s1.pipeline.detrend.mode = "custom_movmean_subtract";
    cfg.s1.pipeline.detrend.window = best_window;

    % run processing w/ best phase

    out.s1 = run_single_dataset(cfg.paths.s1_run_dir, cfg.s1, 'S1',cfg.verbose);
    out.tracker.s1.detrend = out.s1.adv_db;

    % report
    fprintf('\nS1 Best Window = %.f', ...
        best_window);
    fprintf('\nS1 SNRe = %.3f, Adv. (dB) = %.2f\n', ...
        out.s1.snre,out.s1.adv_db);
elseif(strcmp(select,'s2'))
    if(~override.detrend.s2.skip)
        % options
        window_options = [1:3*cfg.s2.pipeline.M];
        SNRr = zeros(size(window_options));

        % mode for intra-bit window sizes
        cfg.s2.pipeline.detrend.mode = "custom_movmean_subtract";

        % Precompute once before detrend sweep
        pre = precompute_dataset(out.s2.run_dir, cfg.s2);
        pre_detrend.x_f  = apply_filter_stage(pre.x_h, pre.fs, pre.Rb, cfg.s2.pipeline.filter);
        pre_detrend.x_m  = pre.x_m;

        % Inner loop only runs detrend onward
        for w = 1:numel(window_options)
            x_d = apply_detrend_stage(pre_detrend.x_f, cfg.s2.pipeline.M, ...
                struct('mode','custom_movmean_subtract','window',window_options(w)));
            [x_l, m_l] = apply_lag_stage(x_d, pre_detrend.x_m, cfg.s2.pipeline.lag);
            [xs, ms]   = downsample_with_phase(x_l, m_l, cfg.s2.pipeline.phase, cfg.s2.pipeline.M);
            bits = threshold_bits(ms, cfg.s2.pipeline.threshold.mode, cfg.s2.pipeline.invert_bits);
            xp = xs(bits); xm = xs(~bits);
            SNRr(w) = compute_snre_metrics(xp, xm).(cfg.s2.pipeline.metric);
        end

        % extract max
        [maxSNR,idx] = max(SNRr); best_window = window_options(idx);

        % visualize SNRe trend
        if(cfg.verbose)
            figure;
            hold on; theme light;
            plot(window_options,SNRr,LineWidth=2);
            yline(out.s2.snr_c,'--','DisplayName','SNRc',LineWidth=2);
            xlabel('window size');
            ylabel('SNRe');
            title(strcat(select," Detrend Window Optimization; Best Window=",num2str(best_window)));
        end
    else
        best_window = override.detrend.s2.window;
    end
    % apply best window configuration
    cfg.s2.pipeline.detrend.mode = "custom_movmean_subtract";
    cfg.s2.pipeline.detrend.window = best_window;

    % run processing w/ best phase

    out.s2 = run_single_dataset(cfg.paths.s2_run_dir, cfg.s2, 'S2',cfg.verbose);
    out.tracker.s2.detrend = out.s2.adv_db;

    % report
    fprintf('\nS2 Best Window = %.f', ...
        best_window);
    fprintf('\nS2 SNRe = %.3f, Adv. (dB) = %.2f\n', ...
        out.s2.snre,out.s2.adv_db);
else
    disp('error');
end
end

function [out,cfg] = phase(out,cfg,override,select)
if(strcmp(select,'s1'))
    if(~override.phase.s1.skip)
        ch_cfg = cfg.s1;
        % options
        phase_options = [1:cfg.s1.pipeline.M];
        SNRr = zeros(size(phase_options));

        % Precompute once before phase sweep
        pre = precompute_dataset(out.s1.run_dir, cfg.s1);
        pre_detrend.x_f  = apply_filter_stage(pre.x_h, pre.fs, pre.Rb, cfg.s1.pipeline.filter);
        pre_detrend.x_m  = pre.x_m;
        pre_lag.x_d = apply_detrend_stage(pre_detrend.x_f, cfg.s1.pipeline.M, cfg.s1.pipeline.detrend);
        pre_lag.x_m = pre.x_m;
        [pre_phase.x_l, pre_phase.m_l] = apply_lag_stage(pre_lag.x_d, pre_lag.x_m, ch_cfg.pipeline.lag);

        % Inner loop is now just indexing + threshold + metric
        for p = 1:numel(phase_options)
            [xs, ms] = downsample_with_phase(pre_phase.x_l, pre_phase.m_l, phase_options(p), ch_cfg.pipeline.M);
            bits = threshold_bits(ms, ch_cfg.pipeline.threshold.mode, ch_cfg.pipeline.invert_bits);
            xp = xs(bits); xm = xs(~bits);
            SNRr(p) = compute_snre_metrics(xp, xm).(ch_cfg.pipeline.metric);
        end
        % extract max
        [~,idx] = max(SNRr); best_phase = phase_options(idx);


        % visualize SNRe trend
        if(cfg.verbose)
            figure;
            hold on; theme light;
            plot(phase_options,SNRr,LineWidth=2);
            yline(out.s1.snr_c,'--','DisplayName','SNRc',LineWidth=2);
            xlabel('phase'); ylabel('SNRe');
            title('S1 Intrabit Phase Sweep Optimization');
        end
    else
        best_phase = override.phase.s1.best_phase;
    end

    % apply best phase
    cfg.s1.pipeline.phase = best_phase;
    out.s1 = run_single_dataset(cfg.paths.s1_run_dir, cfg.s1, 'S1',cfg.verbose);
    out.tracker.s1.phase = out.s1.adv_db;

    % report
    fprintf('\nS1 Best Phase = %.f', ...
        best_phase);
    fprintf('\nS1 SNRe = %.3f, Adv. (dB) = %.2f\n', ...
        out.s1.snre,out.s1.adv_db);
elseif(strcmp(select,'s2'))
    if(~override.phase.s2.skip)
        ch_cfg = cfg.s2;
        % options
        phase_options = [1:cfg.s2.pipeline.M];
        SNRr = zeros(size(phase_options));

        % Precompute once before phase sweep
        pre = precompute_dataset(out.s2.run_dir, cfg.s2);
        pre_detrend.x_f  = apply_filter_stage(pre.x_h, pre.fs, pre.Rb, cfg.s2.pipeline.filter);
        pre_detrend.x_m  = pre.x_m;
        pre_lag.x_d = apply_detrend_stage(pre_detrend.x_f, cfg.s2.pipeline.M, cfg.s2.pipeline.detrend);
        pre_lag.x_m = pre.x_m;
        [pre_phase.x_l, pre_phase.m_l] = apply_lag_stage(pre_lag.x_d, pre_lag.x_m, ch_cfg.pipeline.lag);

        % Inner loop is now just indexing + threshold + metric
        for p = 1:numel(phase_options)
            [xs, ms] = downsample_with_phase(pre_phase.x_l, pre_phase.m_l, phase_options(p), ch_cfg.pipeline.M);
            bits = threshold_bits(ms, ch_cfg.pipeline.threshold.mode, ch_cfg.pipeline.invert_bits);
            xp = xs(bits); xm = xs(~bits);
            SNRr(p) = compute_snre_metrics(xp, xm).(ch_cfg.pipeline.metric);
        end

        % extract max
        [~,idx] = max(SNRr); best_phase = phase_options(idx);


        % visualize SNRe trend
        if(cfg.verbose)
            figure;
            hold on; theme light;
            plot(phase_options,SNRr,LineWidth=2);
            yline(out.s2.snr_c,'--','DisplayName','SNRc',LineWidth=2);
            xlabel('phase'); ylabel('SNRe');
            title('S2 Intrabit Phase Sweep Optimization');
        end
    else
        best_phase = override.phase.s2.best_phase;
    end

    % apply best phase
    cfg.s2.pipeline.phase = best_phase;
    out.s2 = run_single_dataset(cfg.paths.s2_run_dir, cfg.s2, 'S2',cfg.verbose);
    out.tracker.s2.phase = out.s2.adv_db;

    % report
    fprintf('\nS2 Best Phase = %.f', ...
        best_phase);
    fprintf('\nS2 SNRe = %.3f, Adv. (dB) = %.2f\n', ...
        out.s2.snre,out.s2.adv_db);
else
    disp('error');
end
end

function [out,cfg] = lag(out,cfg,override,select)
if(strcmp(select,'s1'))
    if(~override.lag.s1.skip)
        % options
        lag_options = [-10:10];
        SNRr = zeros(size(lag_options));

        % Precompute once before lag sweep
        pre = precompute_dataset(out.s1.run_dir, cfg.s1);
        pre_detrend.x_f  = apply_filter_stage(pre.x_h, pre.fs, pre.Rb, cfg.s1.pipeline.filter);
        pre_detrend.x_m  = pre.x_m;
        pre_lag.x_d = apply_detrend_stage(pre_detrend.x_f, cfg.s1.pipeline.M, cfg.s1.pipeline.detrend);
        pre_lag.x_m = pre.x_m;

        % Inner loop only runs lag onward
        for l = 1:numel(lag_options)
            [x_l, m_l] = apply_lag_stage(pre_lag.x_d, pre_lag.x_m, lag_options(l));
            [xs, ms]   = downsample_with_phase(x_l, m_l, cfg.s1.pipeline.phase, cfg.s1.pipeline.M);
            bits = threshold_bits(ms, cfg.s1.pipeline.threshold.mode, cfg.s1.pipeline.invert_bits);
            xp = xs(bits); xm = xs(~bits);
            SNRr(l) = compute_snre_metrics(xp, xm).(cfg.s1.pipeline.metric);
        end
        % extract max
        [~,idx] = max(SNRr); best_lag = lag_options(idx);


        % visualize SNRe trend
        figure;
        hold on; theme light;
        plot(lag_options,SNRr,LineWidth=2);
        yline(out.s1.snr_c,'--','DisplayName','SNRc',LineWidth=2);
        xlabel('lag'); ylabel('SNRe');
        title('S1 Lag Sweep Optimization');
    else
        best_lag = override.lag.s1.best_lag;
    end

    % apply best phase
    cfg.s1.pipeline.lag = best_lag;
    out.s1 = run_single_dataset(cfg.paths.s1_run_dir, cfg.s1, 'S1',cfg.verbose);
    out.tracker.s1.lag = out.s1.adv_db;

    % report
    fprintf('\nS1 Best Lag = %.f', ...
        best_lag);
    fprintf('\nS1 SNRe = %.3f, Adv. (dB) = %.2f\n', ...
        out.s1.snre,out.s1.adv_db);
elseif(strcmp(select,'s2'))
    if(~override.lag.s2.skip)
        % options
        lag_options = [-10:10];
        SNRr = zeros(size(lag_options));

         % Precompute once before lag sweep
        pre = precompute_dataset(out.s2.run_dir, cfg.s2);
        pre_detrend.x_f  = apply_filter_stage(pre.x_h, pre.fs, pre.Rb, cfg.s2.pipeline.filter);
        pre_detrend.x_m  = pre.x_m;
        pre_lag.x_d = apply_detrend_stage(pre_detrend.x_f, cfg.s2.pipeline.M, cfg.s2.pipeline.detrend);
        pre_lag.x_m = pre.x_m;

        % Inner loop only runs lag onward
        for l = 1:numel(lag_options)
            [x_l, m_l] = apply_lag_stage(pre_lag.x_d, pre_lag.x_m, lag_options(l));
            [xs, ms]   = downsample_with_phase(x_l, m_l, cfg.s2.pipeline.phase, cfg.s2.pipeline.M);
            bits = threshold_bits(ms, cfg.s2.pipeline.threshold.mode, cfg.s2.pipeline.invert_bits);
            xp = xs(bits); xm = xs(~bits);
            SNRr(l) = compute_snre_metrics(xp, xm).(cfg.s2.pipeline.metric);
        end
        % extract max
        [~,idx] = max(SNRr); best_lag = lag_options(idx);


        % visualize SNRe trend
        figure;
        hold on; theme light;
        plot(lag_options,SNRr,LineWidth=2);
        yline(out.s2.snr_c,'--','DisplayName','SNRc',LineWidth=2);
        xlabel('lag'); ylabel('SNRe');
        title('S2 Lag Sweep Optimization');
    else
        best_lag = override.lag.s2.best_lag;
    end

    % apply best phase
    cfg.s2.pipeline.lag = best_lag;
    out.s2 = run_single_dataset(cfg.paths.s2_run_dir, cfg.s2, 'S2',cfg.verbose);
    out.tracker.s2.lag = out.s2.adv_db;

    % report
    fprintf('\nS2 Best Lag = %.f', ...
        best_lag);
    fprintf('\nS2 SNRe = %.3f, Adv. (dB) = %.2f\n', ...
        out.s2.snre,out.s2.adv_db);
else
    disp('error');
end
end

function simple_summary(out)
fprintf('\nManual post-processing summary\n');
fprintf('S1 SNRe: %.6f (N=%d)\n', out.s1.snre, out.s1.n_points);
fprintf('S2 SNRe: %.6f (N=%d)\n', out.s2.snre, out.s2.n_points);
if isfield(out.s1, 'snr_c') && isfinite(out.s1.snr_c)
    fprintf('S1 SNRc: %.6f | margin: %+0.6f | adv(dB): %+0.6f\n', out.s1.snr_c, out.s1.margin, out.s1.adv_db);
else
    fprintf('S1 SNRc: n/a (processed_summary.json missing or invalid)\n');
end
if isfield(out.s2, 'snr_c') && isfinite(out.s2.snr_c)
    fprintf('S2 SNRc: %.6f | margin: %+0.6f | adv(dB): %+0.6f\n', out.s2.snr_c, out.s2.margin, out.s2.adv_db);
else
    fprintf('S2 SNRc: n/a (processed_summary.json missing or invalid)\n');
end
end

function s = set_skip_fields(s, val)
fields = fieldnames(s);
for k = 1:numel(fields)
    if strcmp(fields{k}, 'skip')
        s.(fields{k}) = val;
    elseif isstruct(s.(fields{k}))
        s.(fields{k}) = set_skip_fields(s.(fields{k}), val);
    end
end
end

%% Codex rate-region launcher
% Launcher for rate_region_normalized_tool with coded selection options.

%% User settings
root = "/Users/agentatom/Library/CloudStorage/OneDrive-Umich/GraduateSchool/UM/QE_LAB/MAC/data/codex_processing";
date = "4-20-26";
batch_ids = [1 4];

% JSON selection mode:
%   "auto"    -> prefer non-trim JSON if present, else trim
%   "trim"    -> require trim JSON
%   "nontrim" -> require non-trim JSON
json_mode = "nontrim";

% Output location for generated plot and summary JSON.
output_dir = "/Users/agentatom/Documents/New project";
output_json_path = ""; % leave empty to use default naming
plot_png_path = "";    % leave empty to use default naming
plot_fig_path = "";    % leave empty to use default naming

% Plot toggles
show_ea_outer_bound = false;
show_experimental_joint_region = true;
show_coherent_constraint_lines = true; % plot only the coherent diagonal outer-bound line
show_figure = true; % open the figure window when running interactively

% MI estimator
%   "hw_hist"  -> HW-style histogram entropy estimate (recommended)
%   "llr_soft" -> Gaussian LLR soft-decoding estimate
mi_estimator = "hw_hist";
hw_hist_bins = 500;

% Joint MI estimator
%   "hw_hist_2d"    -> HW-style 2D histogram estimator (recommended)
%   "gaussian_soft" -> 4-class Gaussian soft decoder
joint_mi_estimator = "hw_hist_2d";
hw_joint_hist_bins = 80;

% Selector modes per channel:
%   "best"          -> max HW-MI margin across selected batches
%   "best_in_batch" -> max HW-MI margin within selector.batch
%   "manual"        -> explicit selector.batch + selector.run
s1_selector_mode = "best";
s1_selector_batch = 1;
s1_selector_run = NaN;

s2_selector_mode = "best";
s2_selector_batch = 4;
s2_selector_run = NaN;

% Receiver overlay controls (Fig.8-style proxy overlays)
receiver_overlay_enable = false;
receiver_show_opar = false;
receiver_show_pcr = false;
receiver_alpha_source = "auto_from_data"; % "auto_from_data" | "manual"
receiver_alpha_base = 0.08;
receiver_alpha_opar_factor = 0.75;
receiver_alpha_pcr_factor = 1.10;

% Physics-model merge options for bound evaluation
nb_merge_mode = "average"; % "average" | "s1" | "s2" | "min" | "max"
tau_mode = "sum_kappa";    % "sum_kappa" | "explicit"
tau_override = NaN;         % required when tau_mode="explicit"

% Secondary overlay scenario (second MI-best point set)
secondary_enable = true;
secondary_label = "4-22 batch 2";
secondary_date = "4-22-26";
secondary_batch_ids = [2];
secondary_json_mode = "auto";
secondary_s1_selector_mode = "best";
secondary_s1_selector_batch = 2;
secondary_s1_selector_run = NaN;
secondary_s2_selector_mode = "best";
secondary_s2_selector_batch = 2;
secondary_s2_selector_run = NaN;

%% Build options struct
opts = struct();
opts.root = char(root);
opts.date = char(date);
opts.batchIds = batch_ids;
opts.resultsMode = char(json_mode);
opts.outputDir = char(output_dir);
opts.showEAOuterBound = logical(show_ea_outer_bound);
opts.showExperimentalJointRegion = logical(show_experimental_joint_region);
opts.showCoherentConstraintLines = logical(show_coherent_constraint_lines);
opts.showFigure = logical(show_figure);
opts.miEstimator = char(mi_estimator);
opts.hwHistBins = hw_hist_bins;
opts.jointMiEstimator = char(joint_mi_estimator);
opts.hwJointHistBins = hw_joint_hist_bins;

if strlength(output_json_path) > 0
    opts.outputJsonPath = char(output_json_path);
else
    opts.outputJsonPath = fullfile(char(output_dir), sprintf('normalized_rate_region_summary_%s.json', char(date)));
end
if strlength(plot_png_path) > 0
    opts.plotPngPath = char(plot_png_path);
else
    opts.plotPngPath = fullfile(char(output_dir), sprintf('normalized_rate_region_%s.png', char(date)));
end
if strlength(plot_fig_path) > 0
    opts.plotFigPath = char(plot_fig_path);
else
    opts.plotFigPath = fullfile(char(output_dir), sprintf('normalized_rate_region_%s.fig', char(date)));
end

opts.nbMergeMode = char(nb_merge_mode);
opts.tauMode = char(tau_mode);
opts.tauOverride = tau_override;

opts.selector = struct();
opts.selector.S1 = make_selector(s1_selector_mode, s1_selector_batch, s1_selector_run);
opts.selector.S2 = make_selector(s2_selector_mode, s2_selector_batch, s2_selector_run);

opts.receiverOverlay = struct( ...
    'enable', logical(receiver_overlay_enable), ...
    'showOPAR', logical(receiver_show_opar), ...
    'showPCR', logical(receiver_show_pcr), ...
    'method', 'ea_gap_interp', ...
    'alphaSource', char(receiver_alpha_source), ...
    'alphaBase', receiver_alpha_base, ...
    'alphaOPARFactor', receiver_alpha_opar_factor, ...
    'alphaPCRFactor', receiver_alpha_pcr_factor ...
);

opts.secondaryOverlay = struct( ...
    'enable', logical(secondary_enable), ...
    'label', char(secondary_label), ...
    'date', char(secondary_date), ...
    'batchIds', secondary_batch_ids, ...
    'resultsMode', char(secondary_json_mode), ...
    'selector', struct( ...
        'S1', make_selector(secondary_s1_selector_mode, secondary_s1_selector_batch, secondary_s1_selector_run), ...
        'S2', make_selector(secondary_s2_selector_mode, secondary_s2_selector_batch, secondary_s2_selector_run) ...
    ) ...
);

%% Run tool
tool_dir = fileparts(mfilename('fullpath'));
addpath(tool_dir);

if exist(opts.outputDir, 'dir') ~= 7
    mkdir(opts.outputDir);
end

summary = rate_region_normalized_tool(opts);

%% Console summary
fprintf('\nrun_rate_region completed.\n');
fprintf('S1 selected: %s run_%05d\n', summary.selected.S1.batchTag, summary.selected.S1.run_index);
fprintf('S2 selected: %s run_%05d\n', summary.selected.S2.batchTag, summary.selected.S2.run_index);
if isfield(summary.selected.S1, 'hw_margin_bits_per_use') && isfield(summary.selected.S2, 'hw_margin_bits_per_use')
    fprintf('HW selection margins (bits/use): S1=%.6f | S2=%.6f\n', ...
        summary.selected.S1.hw_margin_bits_per_use, summary.selected.S2.hw_margin_bits_per_use);
end
fprintf('Estimators: per-channel=%s | joint=%s\n', ...
    summary.channels.S1.mi_estimator, summary.joint.mi_estimator);
fprintf('Eq.8 coherent bounds (bits/use): C1=%.6f | C2=%.6f | Csum=%.6f\n', ...
    summary.bounds.eq8.individual.S1.bits_per_use, ...
    summary.bounds.eq8.individual.S2.bits_per_use, ...
    summary.bounds.eq8.sum.bits_per_use);
if isfield(summary, 'secondary_overlay') && isfield(summary.secondary_overlay, 'enabled') && summary.secondary_overlay.enabled
    fprintf('Secondary point (%s): S1 %s run_%05d | S2 %s run_%05d\n', ...
        summary.secondary_overlay.label, ...
        summary.secondary_overlay.selected.S1.batchTag, summary.secondary_overlay.selected.S1.run_index, ...
        summary.secondary_overlay.selected.S2.batchTag, summary.secondary_overlay.selected.S2.run_index);
end
fprintf('Plot: %s\n', summary.normalized_rate_region_plot.png_path);
fprintf('Summary JSON: %s\n\n', opts.outputJsonPath);


function s = make_selector(mode, batch_id, run_idx)
s = struct('mode', char(mode), 'batchId', double(batch_id), 'runIndex', double(run_idx));
end

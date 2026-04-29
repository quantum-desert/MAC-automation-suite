%% Codex optimizer launcher
% Programmatically configure and run deterministic SNRe optimization.
% Mirrors the simple editable style of run_visualizer.m.

%% User settings
% Dataset root that contains run_XXXXX folders.
data_path = "/Users/agentatom/Documents/_tmp_MAC_DATA/2026-04-27";

% Python optimizer script path.x
optimizer_py = "/Users/agentatom/Documents/New project/optimize_snr_extraction.py";
python_bin = "python3";

% Output files (written inside data_path by default).
report_path = fullfile(data_path, "snr_optimization_report_2026-04-27.md");
json_path   = fullfile(data_path, "snr_optimization_results_2026-04-27.json");

% Optional: only process specific run indices listed in a text file
% (comma/space/newline separated). Set "" to disable.
run_index_file = "";

% Optional: sweep-tracking JSON for classical lookup by run index.
% Set "" to disable and use processed_summary.json values instead.
sweep_tracking_json = "";

% Optional fallback classical run index when a run is missing
% processed_summary.json. Set negative to disable.
fallback_classical_from_run = 37;

% Core optimizer settings.
use_dynamic_m = true;        % true -> M=round(Fs/Rb)
rb_s1_hz = 16000;            % S1 bit rate
rb_s2_hz = 16000;            % S2 bit rate
phase_multiplier = 2;        % phase sweep = phase_multiplier * M
lag_range = 3;               % lag sweep = [-lag_range, +lag_range]

% Only used when dynamic M is disabled.
m_values = "16,18";

% Console output settings.
verbose = true;
progress_every = 25;
show_command = true;

%% Validation
if ~isfolder(data_path)
    error('Dataset path not found: %s', data_path);
end
if ~isfile(optimizer_py)
    error('Optimizer script not found: %s', optimizer_py);
end

%% Build command
args = strings(0, 1);
args(end+1) = "--root " + shquote(data_path);
args(end+1) = "--report " + shquote(report_path);
args(end+1) = "--json " + shquote(json_path);

if strlength(strtrim(run_index_file)) > 0
    if ~isfile(run_index_file)
        error('run_index_file not found: %s', run_index_file);
    end
    args(end+1) = "--run-index-file " + shquote(run_index_file);
end

if strlength(strtrim(sweep_tracking_json)) > 0
    if ~isfile(sweep_tracking_json)
        error('sweep_tracking_json not found: %s', sweep_tracking_json);
    end
    args(end+1) = "--sweep-tracking-json " + shquote(sweep_tracking_json);
end

if fallback_classical_from_run >= 0
    args(end+1) = "--fallback-classical-from-run " + string(fallback_classical_from_run);
end

if use_dynamic_m
    args(end+1) = "--dynamic-m";
    args(end+1) = "--rb-s1 " + string(rb_s1_hz);
    args(end+1) = "--rb-s2 " + string(rb_s2_hz);
else
    args(end+1) = "--m-values " + shquote(m_values);
end

args(end+1) = "--phase-multiplier " + string(phase_multiplier);
args(end+1) = "--lag-range " + string(lag_range);

if verbose
    args(end+1) = "--verbose";
    args(end+1) = "--progress-every " + string(progress_every);
end

cmd = python_bin + " " + shquote(optimizer_py) + " " + strjoin(args, " ");

if show_command
    fprintf('\n[run_optimizer] Command:\n%s\n\n', cmd);
end

%% Execute
[status, out] = system(char(cmd));

fprintf('%s\n', out);

if status ~= 0
    error('Optimizer failed with exit code %d', status);
end

fprintf('[run_optimizer] Complete.\n');
fprintf('  Report: %s\n', report_path);
fprintf('  JSON:   %s\n', json_path);


function q = shquote(s)
% Shell-quote for POSIX sh/zsh: wrap in single quotes and escape inner '.
cs = char(string(s));
q = ["'" strrep(string(cs), "'", "'\"'\"'") "'"];
q = char(q);
end

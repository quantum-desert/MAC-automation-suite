%% Codex visualizer launcher
% This script auto-selects trim or non-trim optimization JSONs without
% hardcoding a specific filename.

%% User settings
root = "/Users/agentatom/Library/CloudStorage/OneDrive-Umich/GraduateSchool/UM/QE_LAB/MAC/data/codex_processing/";
date = "4-20-26";
batch = "batch_4";
mod = 'd'; % 'd' = deterministic, 'p' = PN15

% JSON selection mode:
%   "auto"    -> prefer trim JSON if present, else fall back to non-trim
%   "trim"    -> require trim JSON
%   "nontrim" -> require non-trim JSON
json_mode = "nontrim";

%% Build dataset path
if strcmp(mod, 'd')
    date_reform = string(datetime(date, 'InputFormat', 'M-dd-yy'), 'yyyy-MM-dd');
    data_path = strcat(root, date, "/", batch, "/", date_reform, "-1010-", strrep(batch, '_', ''));
else
    date_reform = string(datetime(date, 'InputFormat', 'M-dd-yy'), 'yyyy-MM-dd');
    data_path = strcat(root, date, "/", batch, "/", date_reform, "-PN15-", strrep(batch, '_', ''));
end

if ~isfolder(data_path)
    error('Dataset path not found: %s', data_path);
end

%% Resolve optimization JSON path (trim/non-trim)
json_path = resolve_results_json(char(data_path), char(json_mode));

%% Run visualizer tool
addpath('/Users/agentatom/Library/CloudStorage/OneDrive-Umich/GraduateSchool/UM/QE_LAB/MAC/codes/MAC-automation-suite/tools');

if strlength(string(json_path)) > 0
    fprintf('Using results JSON (%s): %s\n', json_mode, json_path);
    visualize_best_dataset_tool(char(data_path), char(json_path));
else
    fprintf('No optimization JSON found. Falling back to tool auto-discovery for: %s\n', data_path);
    visualize_best_dataset_tool(char(data_path));
end


function json_path = resolve_results_json(data_path, json_mode)
% Search nearby locations for matching optimization result JSON files.

batch_dir = fileparts(data_path);
date_dir = fileparts(batch_dir);
tool_dir = fileparts(mfilename('fullpath'));

search_dirs = unique({data_path, batch_dir, date_dir, pwd, tool_dir});

trim_candidates = collect_candidates(search_dirs, 'snr_trim_optimization_results_*.json');
nontrim_candidates = collect_candidates(search_dirs, 'snr_optimization_results_*.json');

mode = lower(strtrim(char(string(json_mode))));

switch mode
    case 'trim'
        chosen = newest_path(trim_candidates);
        if isempty(chosen)
            error('json_mode=trim but no trim JSON found near %s', data_path);
        end
    case 'nontrim'
        chosen = newest_path(nontrim_candidates);
        if isempty(chosen)
            error('json_mode=nontrim but no non-trim JSON found near %s', data_path);
        end
    otherwise % auto
        chosen = newest_path(trim_candidates);
        if isempty(chosen)
            chosen = newest_path(nontrim_candidates);
        end
end

json_path = chosen;
end


function candidates = collect_candidates(search_dirs, pattern)
candidates = struct('path', {}, 'datenum', {});

for i = 1:numel(search_dirs)
    d = search_dirs{i};
    if ~isfolder(d)
        continue;
    end
    m = dir(fullfile(d, pattern));
    for k = 1:numel(m)
        if m(k).isdir
            continue;
        end
        p = fullfile(m(k).folder, m(k).name);
        candidates(end+1).path = p; %#ok<AGROW>
        candidates(end).datenum = m(k).datenum; %#ok<AGROW>
    end
end

% Deduplicate by absolute path (keep newest datenum if duplicated)
if isempty(candidates)
    return;
end

all_paths = {candidates.path};
[uniq_paths, ~, idx] = unique(all_paths, 'stable');
out = struct('path', {}, 'datenum', {});
for u = 1:numel(uniq_paths)
    mask = (idx == u);
    dn = [candidates(mask).datenum];
    out(end+1).path = uniq_paths{u}; %#ok<AGROW>
    out(end).datenum = max(dn); %#ok<AGROW>
end
candidates = out;
end


function p = newest_path(candidates)
if isempty(candidates)
    p = '';
    return;
end
[~, k] = max([candidates.datenum]);
p = candidates(k).path;
end

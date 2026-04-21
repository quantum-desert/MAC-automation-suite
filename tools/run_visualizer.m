%% Codex visualizer

%% setup paths
% Record dataset paths
root = "/Users/agentatom/Library/CloudStorage/OneDrive-Umich/GraduateSchool/UM/QE_LAB/MAC/data/codex_processing/";
date = "4-20-26";
batch = "batch_1";
mod = 'd'; % d = deterministic; p = 'pn15'
bi1 = 20; bi2 = 81; % best indicies (see report.md)

% build data path
date_reform = string(datetime(date, 'InputFormat', 'M-dd-yy'), 'yyyy-MM-dd');
if(strcmp(mod,'d'))
data_path = strcat(root,date,"/",batch,"/",date_reform,"-1010-",strrep(batch, '_', ''))
else
data_path = strcat(root,date,"/",batch,"/",date_reform,"-PN15-",strrep(batch, '_', ''))
end

% build json path
json_path = strcat(root,date,"/",batch,"/","snr_optimization_results_",date,"_",strrep(batch, '_', ''),".json")


%% Run visualizer tool
addpath('/Users/agentatom/Library/CloudStorage/OneDrive-Umich/GraduateSchool/UM/QE_LAB/MAC/codes/MAC-automation-suite/tools'); % ensure tool tracked
visualize_best_dataset_tool(data_path,json_path)

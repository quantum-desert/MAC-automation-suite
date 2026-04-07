function cfg =  updateConfig(cfg)
% passed existing config object (loaded from defaultConfig)
% dynamically update config objects based on existing file structure
% change config objects and return passed, updated config object

% update run index
% Build storage path
runDir = lecroy.buildRunDir(cfg.storage, cfg.acquisition.runIndex);

timeout=tic;
while(exist(runDir,'dir'))
    % update run index folder until new # if existing
    cfg.acquisition.runIndex = cfg.acquisition.runIndex + 1;
    runDir = lecroy.buildRunDir(cfg.storage, cfg.acquisition.runIndex);

    % prevent infinite
    if toc(timeout) > 10
        error('Timeout creating new run dir folder');
    end
end
mkdir(runDir);

end
function runFolder = makeRunFolder(cfg, runTimestamp, runIndex)
% lecroy.makeRunFolder  Create date/run folder for one acquisition.

rootDir = char(cfg.storage.rootDir);
if ~exist(rootDir, 'dir')
    mkdir(rootDir);
end

baseDir = rootDir;
if isfield(cfg.storage, 'createDateFolder') && cfg.storage.createDateFolder
    dateDir = datestr(runTimestamp, 'yyyy-mm-dd');
    baseDir = fullfile(rootDir, dateDir);
    if ~exist(baseDir, 'dir')
        mkdir(baseDir);
    end
end

folderName = sprintf(char(cfg.storage.runFolderPattern), runIndex);
runFolder = fullfile(baseDir, folderName);
if ~exist(runFolder, 'dir')
    mkdir(runFolder);
end
end

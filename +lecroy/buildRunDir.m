
function runDir = buildRunDir(storageCfg, runIndex)
    rootDir = storageCfg.rootDir;

    if storageCfg.createDateFolder
        dateDir = char(datetime('today', 'Format', 'yyyy-MM-dd'));
        rootDir = fullfile(rootDir, dateDir);
    end

    runDirName = sprintf(char(storageCfg.runFolderPattern), runIndex);
    runDir = fullfile(rootDir, runDirName);
end
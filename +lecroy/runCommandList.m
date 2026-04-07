function runCommandList(session, cmds)
    if isempty(cmds)
        return;
    end
    cmds = string(cmds(:));
    for k = 1:numel(cmds)
        cmd = strtrim(cmds(k));
        if strlength(cmd) == 0
            continue;
        end
        lecroy.tryWriteLine(session, cmd);
    end
end
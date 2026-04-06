function disconnect(session)
% lecroy.disconnect  Close VISA connection.

if isempty(session)
    return;
end

if ~isfield(session,'io') || isempty(session.io)
    return;
end

try
    if session.backend == "visadev"
        clear session.io %#ok<CLSCR>
    else
        if strcmp(session.io.Status,'open')
            fclose(session.io);
        end
        delete(session.io);
    end
catch
end
end

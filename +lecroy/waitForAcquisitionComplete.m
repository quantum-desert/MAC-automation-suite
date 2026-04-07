function waitForAcquisitionComplete(session, timeoutSeconds)
    if nargin < 2 || isempty(timeoutSeconds)
        timeoutSeconds = 30;
    end

    io=session.io; % assign to actual object

    oldTimeout = io.Timeout;
    c = onCleanup(@() setTimeout(session, oldTimeout));
    io.Timeout = timeoutSeconds;

    writeline(io, "*OPC?");
    resp = strtrim(readline(io)); %#ok<NASGU>
end

function setTimeout(session, val)
    io=session.io;
    try
        io.Timeout = val;
    catch
    end
end
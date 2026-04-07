function trigger(cfg, session)
% lecroy.trigger
% Force one acquisition and block until the scope is ready for waveform readback.

    arguments
        cfg struct
        session struct
    end

    io = session.io;

    oldTimeout = io.Timeout;
    c = onCleanup(@() restoreTimeout(io, oldTimeout));

    % Use the acquisition wait timeout from config
    trigTimeout = cfg.acquisition.waitTimeoutSeconds;
    if isempty(trigTimeout) || trigTimeout <= 0
        trigTimeout = 30;
    end
    io.Timeout = trigTimeout;

    % Recommended sequence from LeCroy manual:
    % STOP -> setup already done by caller -> TRMD SINGLE -> WAIT -> *OPC?
    writeline(io, "STOP");

    % Optional: clear status/event registers before arming
    try
        writeline(io, "*CLS");
    catch
    end

    % Arm one acquisition
    writeline(io, "TRMD SINGLE");

    % WAIT blocks until trigger/acquisition completes.
    % The manual recommends following WAIT with *OPC? so processing is complete.
    % Use an explicit timeout so the program does not hang forever.
    try
        writeline(io, sprintf("WAIT %g", trigTimeout));
    catch
        % Fallback if WAIT syntax/behavior is not accepted in your setup:
        pause(0.1);
    end

    % Ensure processing has completed before readback
    writeline(io, "*OPC?");
    resp = split(strtrim(readline(io)),' ');
    resp=resp(2); % extract response #

    if ~strcmp(resp, "1")
        warning("lecroy.trigger:UnexpectedOPC", ...
            "Expected *OPC? to return 1, got: %s", resp);
    end
end

function restoreTimeout(io, oldTimeout)
    try
        io.Timeout = oldTimeout;
    catch
    end
end
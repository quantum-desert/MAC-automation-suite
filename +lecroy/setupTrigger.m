function setupTrigger(cfg,session)
% Arm acquisition
switch lower(string(cfg.acquisition.acquireMode))
    case "single"
        lecroy.tryWriteLine(session, "TRMD SINGLE");
        lecroy.waitForAcquisitionComplete(session, cfg.acquisition.waitTimeoutSeconds);
    case "normal"
        lecroy.tryWriteLine(session, "TRMD NORM");
        lecroy.waitForAcquisitionComplete(session, cfg.acquisition.waitTimeoutSeconds);
    otherwise
        error("lecroy.acquireRun:UnsupportedAcquireMode", ...
            "Unsupported acquireMode: %s", cfg.acquisition.acquireMode);
end
end
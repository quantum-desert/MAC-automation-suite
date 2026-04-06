function runSingleAcquisition(session, cfg)
% lecroy.runSingleAcquisition  Stop, configure, arm, and wait for one acquisition.
%
% The manual recommends stopping the previous acquisition before taking a new
% acquisition and using status registers, WAIT, *OPC?, or Automation wait
% methods for synchronization. This helper uses a conservative sequence:
% STOP -> optional setup commands -> TRMD SINGLE -> *OPC?.

arguments
    session struct
    cfg struct
end

if cfg.acquisition.setCommHeaderOff
    lecroy.write(session, 'COMM_HEADER OFF');
end

if cfg.acquisition.stopBeforeSetup
    lecroy.write(session, 'TRMD STOP');
end

if cfg.acquisition.clearSweeps
    try
        lecroy.write(session, "VBS 'app.measure.clearsweeps'");
    catch
    end
end

for cmd = reshape(string(cfg.acquisition.setupCommands),1,[])
    if strlength(cmd) > 0
        lecroy.write(session, cmd);
    end
end

switch lower(char(cfg.acquisition.acquireMode))
    case 'single'
        lecroy.write(session, 'TRMD SINGLE');
    otherwise
        error('lecroy:runSingleAcquisition:UnsupportedMode', ...
            'Unsupported acquireMode: %s', cfg.acquisition.acquireMode);
end

for cmd = reshape(string(cfg.acquisition.postArmCommands),1,[])
    if strlength(cmd) > 0
        lecroy.write(session, cmd);
    end
end

% Use *OPC? as a simple synchronization primitive.
% For problematic trigger situations, this can be extended to WAIT or INR?.
tStart = tic;
while toc(tStart) < cfg.acquisition.waitTimeoutSeconds
    try
        rsp = lecroy.query(session, '*OPC?');
        if contains(rsp, '1')
            pause(cfg.acquisition.waitAfterIdleSeconds);
            return;
        end
    catch
        pause(0.1);
    end
    pause(0.1);
end

error('lecroy:runSingleAcquisition:Timeout', ...
    'Timed out waiting for acquisition completion after %.3f seconds.', ...
    cfg.acquisition.waitTimeoutSeconds);
end

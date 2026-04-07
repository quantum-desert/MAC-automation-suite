% Example: single automated acquisition from a Teledyne LeCroy scope.
%
% Before running:
%   1) Install NI-VISA.
%   2) Put the scope into USBTMC remote mode.
%   3) Replace the VISA resource below with the one shown on the scope.

% clear old visadev objects
clear all;

addpath(fileparts(fileparts(mfilename('fullpath'))));


cfg = lecroy.defaultConfig();
cfg.storage.rootDir = fullfile(pwd, 'captures');
cfg = lecroy.updateConfig(cfg);

%  fixed setup commands
cfg.acquisition.setupCommands = [ ...
    % "COMM_HEADER OFF" ...
    "TRMD STOP" ...
    "C1:TRA ON" ...
    "C2:TRA ON" ...
    "C3:TRA ON" ...
    "C4:TRA ON" ...
    "C1:VDIV 1V" ...
    "C2:VDIV 20mV" ...
    "C3:VDIV 20mV" ...
    "C4:VDIV 1V" ...
    "C1:OFST 0V" ...
    "C2:OFST 0V" ...
    "C3:OFST 0V" ...
    "C4:OFST 0V" ...
    "C1:TRLV 1.91V" ...
    "TRSE EDGE,SR,C1" ...
    "C1:TRSL EITHER" ...
    "TRMD NORMAL" ...
    "TDIV 20MS" ...
    "MSIZ 250K"
    ];

% establish session
session = [];
try
    session = lecroy.connect(cfg);
    
    if cfg.acquisition.stopBeforeSetup
        lecroy.tryWriteLine(session, "STOP");
    end
    
    if cfg.acquisition.clearSweeps
        lecroy.tryWriteLine(session, "CLSW");
    end
    
    % Optional user setup commands before arming
    lecroy.runCommandList(session, cfg.acquisition.setupCommands);
    
    % Arm acquisition if requested
    switch lower(string(cfg.acquisition.acquireMode))
        case "single"
            lecroy.tryWriteLine(session, "TRMD SINGLE");
            lecroy.waitForAcquisitionComplete(session, cfg.acquisition.waitTimeoutSeconds);
        otherwise
            error("lecroy.acquireRun:UnsupportedAcquireMode", ...
                "Unsupported acquireMode: %s", cfg.acquisition.acquireMode);
    end
        catch ME
        if ~isempty(session)
            try
                clear session %#ok<NASGU>
            catch
            end
        end
        rethrow(ME);
    end


result = lecroy.acquireRun(cfg,session);
disp(result.manifestPath)

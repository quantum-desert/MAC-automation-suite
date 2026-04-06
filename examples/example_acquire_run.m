% Example: single automated acquisition from a Teledyne LeCroy scope.
%
% Before running:
%   1) Install NI-VISA.
%   2) Put the scope into USBTMC remote mode.
%   3) Replace the VISA resource below with the one shown on the scope.

addpath(fileparts(fileparts(mfilename('fullpath'))));

cfg = lecroy.defaultConfig();
cfg.connection.resource = "USB0::0x05FF::0x1023::123456::INSTR";
cfg.storage.rootDir = fullfile(pwd, 'captures');
cfg.acquisition.runIndex = 0;

% Example fixed setup commands. Replace with your experiment values.
cfg.acquisition.setupCommands = [ ...
    "COMM_HEADER OFF" ...
    "TRMD STOP" ...
    "C1:TRA ON" ...
    "C2:TRA ON" ...
    "C3:TRA ON" ...
    "C4:TRA ON" ...
    ];

result = lecroy.acquireRun(cfg);
disp(result.manifestPath)

function pass = verifyConfig(cfg)
% pass/fail test: verify specific config params were applied by reading
% back from the lecroy and inferring results
pass=false; % fail default

% test 1: verify sampling rate
Fs_goal = 1e6; % 1Msps
Fs_actual = lecroy.tryWriteLine(cfg.)
end
function tank = preprocess_data(filenames,constants)
% Purpose: read in raw data, organize and process into data structure
% Input:
%   filenames - struct containing paths to the txt file(s)
%   filenames: includes .homodyne .absent .mod
%
% Output:
%   tank - structure containing parsed data
%   tank.t_xxx - named time series
%   tank.A_xxx - named amplitude series
%   tank.report - structure containing preprocess information 

arguments
    filenames
    constants
end

tank.label = filenames.label; 

homodyne = readmatrix(filenames.homodyne, 'NumHeaderLines', 4);
tank.t_homo = homodyne(:,1);
tank.A_homo = homodyne(:,2);

% absent = readmatrix(filenames.absent, 'NumHeaderLines', 4);
% tank.t_abs = absent(:,1);
% tank.A_abs = absent(:,2);

modulation = readmatrix(filenames.mod, 'NumHeaderLines', 4);
tank.t_mod = modulation(:,1);
tank.A_mod = modulation(:,2);

% pre-processing
% % truncate dataset
% len = length(tank.t_homo);
% tank.t_homo = tank.t_homo(1:floor(len*shorten));
% tank.A_homo = tank.A_homo(1:floor(len*shorten));
% tank.A_mod = tank.A_mod(1:floor(len*shorten));

% digitize modulation
tank.A_mod_d = (tank.A_mod)./max(tank.A_mod);
tank.A_mod_d = tank.A_mod_d>mean(tank.A_mod_d);

% flip polarity
% tank.A_mod_d = ~tank.A_mod_d;

% remove bias
tank.A_homo = tank.A_homo - mean(tank.A_homo);
% tank.A_abs = tank.A_abs - mean(tank.A_abs);

% fill report
tank.report = struct;
tank.report.delta_t = tank.t_homo(2)-tank.t_homo(1); % sampling time (s)
tank.report.t_total = tank.t_homo(end)-tank.t_homo(1); % total time (s)
tank.report.Fs = 1/tank.report.delta_t; % sampling rate (Samples/sec)
tank.report.Fn = tank.report.Fs/2; % Nyquist frequency (Hz); highest sampling w/o distortion
tank.report.M = round(tank.report.Fs/constants.Rb); % samples / symbol

% FIXED BUG HERE
tank.report.N = floor(tank.report.t_total*constants.Rb); % total # of points in downsampled data 

% final processing (depends on report)
tank.sample_index_arr = linspace(1,tank.report.N,tank.report.N);% define sampling index integer array

% notes
% assume sampling rate consistent between datasets
end

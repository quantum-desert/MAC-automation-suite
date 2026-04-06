function constants = defaultConstants()
% postprocess.defaultConstants  Default constants copied from the original script.

constants = struct;
constants.Rb = 8e3; % bit rate (Hz) PN15
% constants.Rb = 16e3; % bit rate (Hz), used for determinstic mod
constants.fd = 32e3; % dither frequency (Hz)
constants.filtering = 1; % filter flag
constants.S = 1.23; % PD responsivity
constants.G_TIA = 5e7; % TIA gain
constants.orange = "#ffb14e";
constants.purple = "#9d02d7";
constants.blue = "#3449eb";
constants.pink = "#eb348f";
end

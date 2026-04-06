function phys_constants = defaultPhysConstants()
% postprocess.defaultPhysConstants  Default physics constants copied from the original script.

phys_constants = struct;
phys_constants.W = 1.88e12; % Optical bandwidth (Hz)
phys_constants.nu = 3e8/(1590e-9); % Optical frequency (Hz)
phys_constants.q = 1.6e-19; % fundamental charge
phys_constants.evPp = 0.8; % ~ energy per photon @ 1550
phys_constants.h = 6.626e-34; % plancks constant
end

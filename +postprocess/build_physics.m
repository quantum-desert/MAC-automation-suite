function package = build_physics(physics_cfg, phys_constants, constants)
% build_physics  Build physics package from a named config struct.
%
% INPUTS
%   physics_cfg    struct with named fields, e.g.
%                  .date
%                  .kappa
%                  .kappa_I
%                  .eta_signal_col_CWDM
%                  .P_SPDC
%                  .NE
%                  .P_b
%                  .comments   (optional)
%   phys_constants struct of physical constants
%   constants      struct of experiment constants
%
% OUTPUT
%   package        struct containing raw inputs plus derived quantities

    arguments
        physics_cfg (1,1) struct
        phys_constants (1,1) struct
        constants (1,1) struct
    end

    % Copy all user-supplied fields into package
    package = physics_cfg;

    % Required fields
    requiredFields = { ...
        'kappa', ...
        'kappa_I', ...
        'eta_signal_col_CWDM', ...
        'P_SPDC', ...
        'NE', ...
        'P_b'};

    for k = 1:numel(requiredFields)
        f = requiredFields{k};
        if ~isfield(package, f)
            error('build_physics:MissingField', ...
                'Missing required physics config field: %s', f);
        end
    end

    % Optional defaults
    if ~isfield(package, 'date')
        package.date = NaT;
    end
    if ~isfield(package, 'comments')
        package.comments = "";
    end

    % Normalize SPDC power back to crystal
    package.P_SPDC = package.P_SPDC / package.eta_signal_col_CWDM;

    % Electrical noise power
    package.P_NE = package.NE * ...
        phys_constants.h * phys_constants.nu * phys_constants.W;

    % Photon numbers per mode
    package.NS = package.P_SPDC / ...
        (phys_constants.h * phys_constants.nu * phys_constants.W);

    package.NB = package.P_b / ...
        (phys_constants.h * phys_constants.nu * phys_constants.W);

    % Symbol timing / modes per symbol
    % consisten with SNR definition....
    package.Rb_modeBasis = constants.Rb;
    package.T = 1 / package.Rb_modeBasis;
    package.Modes = phys_constants.W * package.T;

    % Theoretical SNRs
    package.SNR_Q = 4 * ...
        package.kappa * ...
        package.kappa_I * ...
        package.NS * package.Modes / ...
        package.NB;

    package.SNR_C = 2 * ...
        package.kappa * ...
        package.NS * package.Modes / ...
        package.NB;

end

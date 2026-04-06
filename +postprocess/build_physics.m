function package = build_physics(filename,phys_constants,constants)
% PURPOSE: read from measurement database to build phys package

% Physics File structure:
% DATA,VALUE\n
% date [] : physics package measurement date
% kappa [%] : channel transmissivity
% kappa_I [%] : idler transmissivity
% eta_signal_col_CWDM [%] : transmissivity of signal col + CWDM
% P_SPDC [W] : SPDC power measured post CWDM
% NE [Photon #/Mode] : Electrical noise floor effective photon number
% P_b [W] : Optical noise power
% comments : information about measurment for documentation

% INPUT: filename corresponding to specific measurement dataset
% OUTPUT: structure containing relevant physical parameters

% unpack
data = readlines(filename,'LineEnding','\n');
for l=1:length(data)
    s = split(data(l),',');
    param=s(1);
    if(l==1) % extract date
        val = datetime(s(2),'InputFormat','MM-dd-yy');
    else
        val=str2double(s(2));
    end
    
    package.(param) = val;
end

package.P_SPDC=package.P_SPDC/package.eta_signal_col_CWDM; % @ crystal normalization        
package.P_NE = package.NE*phys_constants.h*phys_constants.nu*phys_constants.W;
package.NS = package.P_SPDC/(phys_constants.h*phys_constants.nu*phys_constants.W); % number of photons per mode
package.NB = package.P_b/(phys_constants.h*phys_constants.nu*phys_constants.W); % number of photons per mode
package.T=1/constants.Rb; % bit duration (1 symbol)
package.Modes=phys_constants.W*package.T; % number of modes per bit

% Calculate theoretical SNR(s)
% Note: These use (M) modes = to one symbol
package.SNR_Q=  4*...
                package.kappa*...
                package.kappa_I*...
                package.NS*package.Modes...
                /package.NB;

package.SNR_C=  2*...
                package.kappa*...
                package.NS...
                *package.Modes...
                /package.NB;
end

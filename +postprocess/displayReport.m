function summary = displayReport(tank_S1, tank_S2, phys1, phys2)
% postprocess.displayReport  Preserve the original console reporting pattern.

summary = struct();
summary.S1 = struct('P_E_uW', phys1.P_NE*1e6, 'SNRe', tank_S1.fit.SNRe, 'SNR_C', phys1.SNR_C, 'SNR_Q', phys1.SNR_Q);
summary.S2 = struct('P_E_uW', phys2.P_NE*1e6, 'SNRe', tank_S2.fit.SNRe, 'SNR_C', phys2.SNR_C, 'SNR_Q', phys2.SNR_Q);

disp('---- Report Package: Channel 1 ----')
disp(strcat('Effective P_E=',num2str(phys1.P_NE*1e6),'uW'));
disp(strcat('S1 SNRe: ',num2str(tank_S1.fit.SNRe)));
disp(strcat('Classical SNR: ',num2str(phys1.SNR_C)));
disp(strcat('Quantum SNR: ',num2str(phys1.SNR_Q)));
disp(' ');

disp('---- Report Package: Channel 2 ----')
disp(strcat('Effective P_E=',num2str(phys2.P_NE*1e6),'uW'));
disp(strcat('S2 SNRe: ',num2str(tank_S2.fit.SNRe)));
disp(strcat('Classical SNR: ',num2str(phys2.SNR_C)));
disp(strcat('Quantum SNR: ',num2str(phys2.SNR_Q)));
end

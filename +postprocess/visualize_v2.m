function visualize_v2(tank,constants) %#ok<INUSD>
% postprocess.visualize_v2  Lightweight plotting wrapper for the refactor.
%
% The uploaded source only exposed fragments of the original plotting code,
% so this version keeps plotting optional and limited to fields already
% produced by the unchanged processing functions.

% TIME DOMAIN PLOT
figure; hold on;
lim=3e3;
lim_ds = floor(lim/tank.report.M);
plot(tank.t_homo(1:lim),tank.A_homo(1:lim),LineWidth=2,DisplayName='Homodyne (Raw)');
plot(tank.t_homo(1:lim),tank.A_homo_filt(1:lim),LineWidth=2,DisplayName='Homodyne (Filt.)');
plot(tank.t_mod(1:lim),tank.A_mod_d(1:lim),LineWidth=2,DisplayName='Modulation');
s=scatter(tank.dst(1:lim_ds),tank.dsA(1:lim_ds),DisplayName='Downsampled');
xlim([min(tank.t_mod(1:lim)) max(tank.t_mod(1:lim))]);

s.MarkerFaceColor='m';
title(strcat('Time Domain: ',tank.label));
xlabel('Time(s)');
ylabel('Amplitude (V)');
legend;


% FREQUENCY DOMAIN PLOT
plot_ft(tank.report.Fs, tank.A_mod, tank.A_homo, tank.A_homo_filt,tank.label);

% figure('Name', sprintf('Postprocess %s', tank.label));
% subplot(2,1,1);
% plot(tank.t_homo, tank.A_homo);
% hold on;
% if isfield(tank, 'A_homo_filt')
%     plot(tank.t_homo(1:length(tank.A_homo_filt)), tank.A_homo_filt);
% end
% xlabel('t');
% ylabel('A');
% title(sprintf('%s raw / filtered homodyne', tank.label));
% legend({'raw','filtered'}, 'Location', 'best');
% 
% subplot(2,1,2);
% if isfield(tank, 'dst') && isfield(tank, 'dsA')
%     stem(tank.dst, tank.dsA, '.');
%     hold on;
% end
% if isfield(tank, 'fit') && isfield(tank.fit, 'Xp') && isfield(tank.fit, 'Xm')
%     histogram(tank.fit.Xp, 'Normalization', 'count');
%     hold on;
%     histogram(tank.fit.Xm, 'Normalization', 'count');
%     legend({'downsampled','Xp','Xm'}, 'Location', 'best');
% end
% xlabel('sample / value');
% ylabel('count');
% title(sprintf('%s downsample / histogram', tank.label));
end

function r = fft_calc(x,fs)
    % Compute FFT
    N = length(x);             % Number of samples
    X = fft(x);                % Perform FFT
    % Magnitude (two-sided), then convert to single-sided
    P2 = abs(X)/N;
    P1 = P2(1:floor(N/2)+1);
    if mod(N,2)==0
        P1(2:end-1) = 2*P1(2:end-1); % even N: double interior bins
    else
        P1(2:end)   = 2*P1(2:end);   % odd N
    end

    % Frequency axis (Hz)
    f = fs*(0:floor(N/2))/N;
    r=[f'./1e3,log(P1)];

    

end


function r = plot_ft(Fs,A_mod,A_S,A_S_filt,tle)
    % plotting FFT of actual signals
    ft_mod=fft_calc(A_mod,Fs);
    ft_analog=fft_calc(A_S,Fs);
    ft_filtered=fft_calc(A_S_filt,Fs);
    
    figure; hold on;
    % plot mod FFT
    plot(ft_mod(:,1),ft_mod(:,2),DisplayName='Modulation');
    
    % plot analog signal FFT
    % plot(ft_analog(:,1),ft_analog(:,2),DisplayName='Unfiltered BH');
    
    % plot filtered analog FFT
    plot(ft_filtered(:,1),ft_filtered(:,2),DisplayName='Boxcar Filtered BH');
    
    % xline(f_d/1e3,'--r',LineWidth=1,DisplayName='Dither Frequency');
    
    % styling
    xlim([0 100]); % limit to BW of TIS
    ylim([min(ft_filtered(:,2))-1 0]);
    xlabel('f (Hz)'); ylabel('Amp. (dB)');
    title(strcat('FT of RX Signals: ',tle));
    legend;

end

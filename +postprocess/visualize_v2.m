function visualize_v2(tank,constants) %#ok<INUSD>
% postprocess.visualize_v2  Lightweight plotting wrapper for the refactor.
%
% The uploaded source only exposed fragments of the original plotting code,
% so this version keeps plotting optional and limited to fields already
% produced by the unchanged processing functions.

% TIME DOMAIN PLOT
figure; hold on;
lim=1e3;
lim_ds = floor(lim/tank.report.M);
plot(tank.t_homo(1:lim),tank.A_homo(1:lim),LineWidth=2,DisplayName='Homodyne (Raw)');
plot(tank.t_homo(1:lim),tank.A_homo_filt(1:lim),LineWidth=2,DisplayName='Homodyne (Filt.)');
plot(tank.t_mod(1:lim),tank.A_mod_d(1:lim)./10,LineWidth=2,DisplayName='Modulation');
s=scatter(tank.dst(1:lim_ds),tank.dsA(1:lim_ds),DisplayName='Downsampled');
xlim([min(tank.t_mod(1:lim)) max(tank.t_mod(1:lim))]);

s.MarkerFaceColor='m';
title(strcat('Time Domain: ',tank.label));
xlabel('Time(s)');
ylabel('Amplitude (V)');
legend;

% histograms
% plot gaussian fits and data
figure; hold on;
n=150;
hp=histogram(tank.fit.Xp,'NumBins',n/2,'DisplayName','X^+');
hm=histogram(tank.fit.Xm,'NumBins',n/2,'DisplayName','X^-');

% plot fits
hpf = plot(tank.fit.f_p);
hpf.YData = hpf.YData*max(hp.Values)/max(hpf.YData);
hpf.LineWidth = 2; hpf.Color = constants.purple;

hmf = plot(tank.fit.f_m);
hmf.YData = hmf.YData*max(hm.Values)/max(hmf.YData);
hmf.LineWidth = 2; hmf.Color = constants.orange;

xline(mean(tank.fit.Xp),'DisplayName','\mu^+')
xline(mean(tank.fit.Xm),'DisplayName','\mu^-')

legend;
title(strcat('Histogram + Fits: ',tank.label));

% styling
set(hp,'FaceColor',constants.purple);
set(hp,'FaceAlpha',1);
set(hm,'FaceColor',constants.orange);
set(hm,'FaceAlpha',.6);


% FREQUENCY DOMAIN PLOT
plot_ft(tank.report.Fs, tank.A_mod, tank.A_homo, tank.A_homo_filt,tank.label);

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

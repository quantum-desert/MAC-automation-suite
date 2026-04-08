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
function r = fft_calc(x, fs,SNR)
    N = length(x);
    X = fft(x);

    % Single-sided amplitude spectrum
    P2 = abs(X) / N;
    P1 = P2(1:floor(N/2)+1);
    if mod(N,2) == 0
        P1(2:end-1) = 2 * P1(2:end-1);
    else
        P1(2:end) = 2 * P1(2:end);
    end

    f = fs * (0:floor(N/2)) / N;
    df = f(2) - f(1);  % Hz per bin

    if(SNR)
    % --- SNR Estimation ---
    bw_hz       = 8;                          % desired bandwidth (Hz)
    half_bw     = bw_hz / 2;
    guard_hz    = bw_hz;                      % guard band around peak (exclude from noise)

    % Power spectrum (amplitude^2)
    P1_pwr = P1 .^ 2;

    % 1) Find peak within the BW window
    [~, peak_idx] = max(P1_pwr);
    f_peak = f(peak_idx);

    % 2) Bins inside the signal BW
    sig_mask = (f >= f_peak - half_bw) & (f <= f_peak + half_bw);

    % 3) Noise bins: within a wider window but outside the guard band
    noise_window_hz = 5 * bw_hz;             % look ±5x BW around peak for noise
    noise_mask = (f >= f_peak - noise_window_hz) & ...
                 (f <= f_peak + noise_window_hz) & ...
                 ~((f >= f_peak - guard_hz) & (f <= f_peak + guard_hz));

    % 4) Signal power = sum of bins in BW
    P_signal = sum(P1_pwr(sig_mask));

    % 5) Noise floor: mean power per bin × number of signal bins
    %    (normalises noise to the same BW as the signal)
    n_sig_bins   = sum(sig_mask);
    P_noise_per_bin = median(P1_pwr(noise_mask));    P_noise      = P_noise_per_bin * n_sig_bins;

    % 6) SNR in dB
    SNR_dB_vrms = 10 * log10(P_signal / P_noise);

    fprintf('Frequency resolution : %.4f Hz/bin\n', df);
    fprintf('Peak frequency       : %.4f Hz\n',     f_peak);
    fprintf('Signal BW            : %.1f Hz (%d bins)\n', bw_hz, n_sig_bins);
    % fprintf('SNR                  : %.2f dB\n',     SNR_dB);
    fprintf('SNR                  : %.2f (linear v_rms)\n', sqrt(P_signal / P_noise));
    end
    % Original output (keep your log-magnitude for plotting)
    r = [f' / 1e3, log(P1)];
end
% function r = fft_calc(x,fs)
%     % Compute FFT
%     N = length(x);             % Number of samples
%     X = fft(x);                % Perform FFT
%     % Magnitude (two-sided), then convert to single-sided
%     P2 = abs(X)/N;
%     P1 = P2(1:floor(N/2)+1);
%     if mod(N,2)==0
%         P1(2:end-1) = 2*P1(2:end-1); % even N: double interior bins
%     else
%         P1(2:end)   = 2*P1(2:end);   % odd N
%     end
% 
%     % Frequency axis (Hz)
%     f = fs*(0:floor(N/2))/N;
%     r=[f'./1e3,log(P1)];
% 
% 
% 
% end


function r = plot_ft(Fs,A_mod,A_S,A_S_filt,tle)
    % plotting FFT of actual signals
    ft_mod=fft_calc(A_mod,Fs,false);
    ft_analog=fft_calc(A_S,Fs,false);
    ft_filtered=fft_calc(A_S_filt,Fs,true);
    
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

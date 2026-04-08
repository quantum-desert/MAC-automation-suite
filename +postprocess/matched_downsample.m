function tank_r = matched_downsample(constants,tank,deterministic)
% ---- apply matched filter

% assign local
tank_r = tank;

if(deterministic)
% apply low pass filter
[b,a] = butter(3, constants.Rb/tank.report.Fn,'low');     % 3rd order low-pass
tank_r.A_homo_filt = filter(b,a,tank_r.A_homo);

else
% apply boxcar filter -> spectrally matched filter
haf=ones(1, tank_r.report.M) / (tank_r.report.M);     % moving avg. boxcar filter
tank_r.A_homo_filt = filter(haf,1,tank_r.A_homo); % apply filter
end

% truncate to account for phase delay from filter
lag=floor(tank_r.report.M/2);
tank_r.A_homo_filt = tank_r.A_homo_filt(1+lag:end);
tank_r.A_mod_d = tank_r.A_mod_d(1:end-lag);
% TODO: do we need to optimize lag first?

% downsample
% filter delay offset
W = floor(tank_r.report.M/2);

% prevent ds overflow
end_idx = min(floor(tank_r.report.M/2+tank_r.report.M*tank_r.report.N),floor(length(tank_r.A_homo_filt))); 

% ---- optimize start phase

% scan over 2 bits worth
N_phase = 2*tank_r.report.M;

W = linspace(1,N_phase,N_phase);
SNR = zeros(size(W));

% downsample index for A_mod_d
% sample_index_arr = floor(tank_r.report.M/2):tank_r.report.M:end_idx;
sample_index_arr = floor(tank_r.report.M/2):tank_r.report.M:end_idx;

% downsample digital mod
tank_r.ds_mod_A = tank_r.A_mod_d(sample_index_arr);

% TODO: find first rising edge and downsample there

% TODO
Xp = [];
Xm = [];
for w=1:length(W)
    % define sampling index w/ phase offset
    sample_index_arr = W(w):tank_r.report.M:end_idx;

    % downsample (amplitude)
    tank_r.dsA = tank_r.A_homo_filt(sample_index_arr);

    % distribute according to gt
    p_idx=1; m_idx=1;
    Xp=[];
    Xm=[];

    for t=1:length(tank_r.dsA)-1
        if(tank_r.ds_mod_A(t))
            Xp(p_idx)=tank_r.dsA(t); %#ok<AGROW>
            p_idx=p_idx+1;
        else
            Xm(m_idx)=tank_r.dsA(t); %#ok<AGROW>
            m_idx=m_idx+1;
        end
    end
    
    % calculate SNR
    SNR(w) = (abs(mean(Xp)-mean(Xm)))^2/(4*std(Xp)^2);
end

figure; hold on;
stem(SNR);
xlabel('Start \phi');
ylabel('SNR');
title(strcat('Sampling \phi Optimization: ',tank_r.label));



% extract best sampling phase
[maxSNR,bestPhaseIdx] = max(SNR); %#ok<ASGLU>
bestPhase = W(bestPhaseIdx);

% ---- Apply best sampling phase
% define sampling index w/ phase offset
sample_index_arr = bestPhase:tank_r.report.M:end_idx;

% downsample (time)
tank_r.dst = tank_r.t_homo(sample_index_arr);

% downsample (amplitude)
tank_r.dsA = tank_r.A_homo_filt(sample_index_arr);

% ---- Fitting
% apply fits
tank_r.fit = struct;

% distribute according to gt
tank_r.fit.Xp = zeros(size(Xp));
tank_r.fit.Xm = zeros(size(Xm));
p_idx=1; m_idx=1;

for t=1:length(tank_r.dsA)-1
    if(tank_r.ds_mod_A(t))
        tank_r.fit.Xp(p_idx)=tank_r.dsA(t);
        p_idx=p_idx+1;
    else
        tank_r.fit.Xm(m_idx)=tank_r.dsA(t);
        m_idx=m_idx+1;
    end
end

% store best SNR
tank_r.fit.SNRe = (abs(mean(tank_r.fit.Xp)-mean(tank_r.fit.Xm)))^2/(4*std(tank_r.fit.Xp)^2);

% define frequency domain SNR
tank_r.fit.SNRf = tank_r.fit.SNRe*sqrt(constants.BW_t/constants.RBW); % (predicted) frequency domain SNR

% define fixed bin width
bw=1e-5;

 % plus ()
 
[counts_p, edges_p] = histcounts(tank_r.fit.Xp,'BinWidth',bw);
binCenters_p = (edges_p(1:end-1) + edges_p(2:end)) / 2;
[tank_r.fit.f_p, ~] = fit(binCenters_p', counts_p', 'gauss1');

% minus ()
[counts_m, edges_m] = histcounts(tank_r.fit.Xm,'BinWidth',bw);
binCenters_m = (edges_m(1:end-1) + edges_m(2:end)) / 2;
[tank_r.fit.f_m, ~] = fit(binCenters_m', counts_m', 'gauss1');


% store some parameters
tank_r.report.ds_len = length(tank_r.dsA);
end

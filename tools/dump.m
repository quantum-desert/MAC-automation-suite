%% manual filter sweep - non causal
%
% set flags
% % verbose=false;
% % S1
% % sweep through boxcar filter for each channel
% % filt_options = linspace(0.1,2,60);
% %
% % set up plotting
% % figure; hold on; ax=gca;
% % theme light;
% % ylim([-50 10]);
% % xlim([0 60]);
% %
% % set causal LP
% % cfg.s1.pipeline.filter.mode = 'fft_lp_ratio';
% %
% % SNRr = zeros(size(filt_options));
% %
% % for r = 1:numel(filt_options)
% %     set LP cutoff
% %     cfg.s1.pipeline.filter.ratio = filt_options(r);
% %
% %     run processing
% %     out.s1 = run_single_dataset(cfg.paths.s1_run_dir, cfg.s1, 'S1',verbose);
% %
% %     store SNRe
% %     SNRr(r) = out.s1.snre;
% %
% %     plot fft
% %     plot_fft_from_outsx(ax,out.s1,strcat('fc ratio=',num2str(cfg.s1.pipeline.filter.ratio)));
% %
% %     drawnow;          % force UI refresh now
% %     pause(1);       % wait ~1 second before next call
% %
% % end
% % visualize SNRe trend
% % figure;
% % hold on; theme light;
% % plot(filt_options,SNRr,LineWidth=2);
% % yline(out.s1.snr_c,'--','DisplayName','SNRc',LineWidth=2);
% % title('Non-causal Brick Wall Filtering; LP Sweep')
% % xlabel('fc');
% % ylabel('SNRe');

% debugging
% plot S2 time
figure; hold on;
slc = 2e3;
slc_ds = floor(slc/cfg.s2.pipeline.M);
slice_filt = out.s2.debug.filtered(1:slc);
slice_raw = out.s2.debug.raw(1:slc);
slice_at = out.s2.debug.after_trim(1:slc);
ds_slice = out.s2.debug.ds.homo(1:slc_ds);


t = linspace(1,slc,slc);
t_ds = (1 + cfg.s2.pipeline.phase) : cfg.s2.pipeline.M : slc;
t_ds = t_ds(t_ds <= slc-1);
plot(t,slice_filt,'DisplayName','Filtered');
plot(t,slice_at.*20,'DisplayName','After Trim');
scatter(t_ds,ds_slice.*20,'DisplayName','DS');
legend;
theme light;
ylim([min(slice_filt) max(slice_filt)]);


% plot s2 hist
figure; hold on;
histogram(out.s2.debug.class.xp,NumBins=4e1);
histogram(out.s2.debug.class.xm,NumBins=4e1);

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


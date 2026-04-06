function label = lookupChannelLabel(cfg, source)
% lecroy.lookupChannelLabel  Resolve human label for C1/C2/... from config.

if isfield(cfg.acquisition, 'channelLabels') && isfield(cfg.acquisition.channelLabels, char(source))
    label = string(cfg.acquisition.channelLabels.(char(source)));
else
    label = string(source);
end
end

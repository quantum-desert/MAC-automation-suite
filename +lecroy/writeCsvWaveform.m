function writeCsvWaveform(filename, channelData, cfg)
% lecroy.writeCsvWaveform  Write two-column CSV compatible with readmatrix(...,'NumHeaderLines',4).

arguments
    filename {mustBeTextScalar}
    channelData struct
    cfg struct
end

fid = fopen(filename, 'w');
if fid < 0
    error('lecroy:writeCsvWaveform:OpenFailed', 'Could not open %s for writing.', filename);
end
c = onCleanup(@() fclose(fid));

for i = 1:numel(cfg.storage.csvHeaderLines)
    fprintf(fid, '%s\n', cfg.storage.csvHeaderLines(i));
end

for i = 1:numel(channelData.time)
    fprintf(fid, '%.15g,%.15g\n', channelData.time(i), channelData.amplitude(i));
end
end

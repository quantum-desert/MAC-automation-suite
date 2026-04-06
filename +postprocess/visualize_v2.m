function visualize_v2(tank,constants) %#ok<INUSD>
% postprocess.visualize_v2  Lightweight plotting wrapper for the refactor.
%
% The uploaded source only exposed fragments of the original plotting code,
% so this version keeps plotting optional and limited to fields already
% produced by the unchanged processing functions.

figure('Name', sprintf('Postprocess %s', tank.label));
subplot(2,1,1);
plot(tank.t_homo, tank.A_homo);
hold on;
if isfield(tank, 'A_homo_filt')
    plot(tank.t_homo(1:length(tank.A_homo_filt)), tank.A_homo_filt);
end
xlabel('t');
ylabel('A');
title(sprintf('%s raw / filtered homodyne', tank.label));
legend({'raw','filtered'}, 'Location', 'best');

subplot(2,1,2);
if isfield(tank, 'dst') && isfield(tank, 'dsA')
    stem(tank.dst, tank.dsA, '.');
    hold on;
end
if isfield(tank, 'fit') && isfield(tank.fit, 'Xp') && isfield(tank.fit, 'Xm')
    histogram(tank.fit.Xp, 'Normalization', 'count');
    hold on;
    histogram(tank.fit.Xm, 'Normalization', 'count');
    legend({'downsampled','Xp','Xm'}, 'Location', 'best');
end
xlabel('sample / value');
ylabel('count');
title(sprintf('%s downsample / histogram', tank.label));
end

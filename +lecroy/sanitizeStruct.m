function out = sanitizeStruct(in)
% lecroy.sanitizeStruct  Convert strings/datetimes recursively for jsonencode.

if isstruct(in)
    out = struct();
    f = fieldnames(in);
    for i = 1:numel(f)
        out.(f{i}) = lecroy.sanitizeStruct(in.(f{i}));
    end
elseif isstring(in)
    if isscalar(in)
        out = char(in);
    else
        out = cellstr(in(:));
    end
elseif isdatetime(in)
    out = char(in);
elseif iscell(in)
    out = cellfun(@lecroy.sanitizeStruct, in, 'UniformOutput', false);
else
    out = in;
end
end

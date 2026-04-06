function out = sanitizeInspectMeta(meta)
% lecroy.sanitizeInspectMeta  Convert inspect-value structs into JSON-safe structs.

fields = fieldnames(meta);
out = struct();
for i = 1:numel(fields)
    f = fields{i};
    v = meta.(f);
    out.(f) = struct('raw', char(string(v.raw)), 'numeric', v.numeric);
end
end

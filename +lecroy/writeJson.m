function writeJson(filename, data)
% lecroy.writeJson  Pretty-print JSON to disk.

jsonText = jsonencode(data, PrettyPrint=true);
fid = fopen(filename, 'w');
if fid < 0
    error('lecroy:writeJson:OpenFailed', 'Could not open %s for writing.', filename);
end
c = onCleanup(@() fclose(fid));
fwrite(fid, jsonText, 'char');
end

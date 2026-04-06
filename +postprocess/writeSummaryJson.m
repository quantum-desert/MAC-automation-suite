function writeSummaryJson(path, summary)
json = jsonencode(summary, 'PrettyPrint', true);
fid = fopen(path, 'w');
cleanup = onCleanup(@() fclose(fid));
fwrite(fid, json, 'char');
end

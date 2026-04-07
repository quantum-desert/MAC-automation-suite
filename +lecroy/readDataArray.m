function data = readDataArray(session, source, blockName, dataType)
% lecroy.readDataArray  Read an INSPECT? data block and parse numeric array.
%
% Uses the INSPECT? query with DATA_ARRAY_1 (or another array block). This is
% simpler than parsing a full WF? binary block and aligns with the manual's
% documented ability to return normalized FLOAT data directly.

arguments
    session struct
    source {mustBeTextScalar}
    blockName {mustBeTextScalar} = "DATA_ARRAY_1"
    dataType {mustBeTextScalar} = "FLOAT"
end

cmd = sprintf('%s:INSPECT? "%s",%s', char(source), char(blockName), char(dataType));
rsp = lecroy.query(session, cmd);


% Strip everything before the first colon inside the quoted INSPECT payload.
% Example response shape: C1:INSPECT "DATA_ARRAY_1: 1.0, 2.0, ..."
payload = char(rsp);
quoteIdx = strfind(payload, '"');
if ~isempty(quoteIdx)
    payload = payload(quoteIdx(1)+1:end);
    if ~isempty(payload) && payload(end) == '"'
        payload = payload(1:end-1);
    end
end
colonIdx = strfind(payload, ':');
if ~isempty(colonIdx)
    payload = payload(colonIdx(1)+1:end);
end

nums = regexp(payload, '[-+]?\d*\.?\d+(?:[eE][-+]?\d+)?', 'match');
data = str2double(nums(:));
if isempty(data)
    error('lecroy:readDataArray:EmptyResponse', ...
        'No numeric samples were parsed from %s response.', char(source));
end
end

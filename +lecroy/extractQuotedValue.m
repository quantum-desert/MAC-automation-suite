function out = extractQuotedValue(textIn)
% lecroy.extractQuotedValue  Extract the content after the first colon.

s = char(string(textIn));
q = strfind(s,'"');
if ~isempty(q)
    s = s(q(1)+1:end);
    if ~isempty(s) && s(end) == '"'
        s = s(1:end-1);
    end
end
c = strfind(s, ':');
if ~isempty(c)
    s = strtrim(s(c(1)+1:end));
end
out = string(s);
end

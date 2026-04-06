function value = extractFirstNumber(textIn)
% lecroy.extractFirstNumber  Extract first floating-point token from text.

textIn = char(string(textIn));
match = regexp(textIn, '[-+]?\d*\.?\d+(?:[eE][-+]?\d+)?', 'match', 'once');
if isempty(match)
    value = NaN;
else
    value = str2double(match);
end
end

function value = queryNumeric(session, cmd)
% lecroy.queryNumeric  Query and parse first numeric token.

rsp = lecroy.query(session, cmd);
value = lecroy.extractFirstNumber(rsp);
if isnan(value)
    error('lecroy:queryNumeric:ParseFailed', ...
        'Could not parse numeric value from response: %s', rsp);
end
end

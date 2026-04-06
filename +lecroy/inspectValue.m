function out = inspectValue(session, source, variable)
% lecroy.inspectValue  Query one INSPECT? value and return both raw and numeric forms.

arguments
    session struct
    source {mustBeTextScalar}
    variable {mustBeTextScalar}
end

cmd = sprintf('%s:INSPECT? "%s"', char(source), char(variable));
rsp = lecroy.query(session, cmd);
out = struct();
out.source = string(source);
out.variable = string(variable);
out.raw = rsp;
out.numeric = lecroy.extractFirstNumber(rsp);
end

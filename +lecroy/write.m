function write(session, cmd)
% lecroy.write  Send a command string.

arguments
    session struct
    cmd {mustBeTextScalar}
end

cmd = string(cmd);
if session.backend == "visadev"
    cmd=char(cmd);
    writeline(session.io, cmd);
else
    fprintf(session.io, '%s', char(cmd));
end
end

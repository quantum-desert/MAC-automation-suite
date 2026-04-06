function write(session, cmd)
% lecroy.write  Send a command string.

arguments
    session struct
    cmd {mustBeTextScalar}
end

cmd = string(cmd);
if session.backend == "visadev"
    writeline(session.io, char(cmd));
else
    fprintf(session.io, '%s', char(cmd));
end
end

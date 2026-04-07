function rsp = query(session, cmd)
% lecroy.query  Send command/query and read a textual response.

arguments
    session struct
    cmd {mustBeTextScalar}
end

lecroy.write(session, cmd);

if session.backend == "visadev"
    rsp = string(strip(readline(session.io)));
else
    rsp = string(strtrim(fscanf(session.io)));
end



end

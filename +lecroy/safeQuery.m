function rsp = safeQuery(session, cmd)
% lecroy.safeQuery  Query wrapper that degrades to missing on failure.
try
    rsp = lecroy.query(session, cmd);
catch
    rsp = missing;
end
end

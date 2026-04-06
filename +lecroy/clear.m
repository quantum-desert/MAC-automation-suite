function clear(session)
% lecroy.clear  Clear device buffers/session state.

if session.backend == "visadev"
    flush(session.io);
else
    clrdevice(session.io);
end
end

function session = connect(cfg)
% lecroy.connect  Open VISA connection to a LeCroy scope.

arguments
    cfg struct
end
resource = cfg.connection.resource;
preferVisadev = isfield(cfg.connection,'preferVisadev') && cfg.connection.preferVisadev;

if preferVisadev && exist('visadev','file') == 2
    io = visadev(resource)
    io.Timeout = cfg.connection.timeoutSeconds;
    if isprop(io,'ByteOrder')
        io.ByteOrder = 'little-endian';
    end
    configureTerminator(io, char(cfg.connection.readTerminator));
    session.backend = "visadev";
else
    visaVendors = {'ni','keysight','tek'};
    io = [];
    lastErr = [];
    for k = 1:numel(visaVendors)
        try
            io = visa(visaVendors{k}, resource); %#ok<TNMLP>
            io.Timeout = cfg.connection.timeoutSeconds;
            io.InputBufferSize = max(2^20, 8*2^20);
            io.OutputBufferSize = max(2^16, 2*2^16);
            io.ByteOrder = 'littleEndian';
            io.Terminator = char(cfg.connection.readTerminator);
            fopen(io);
            break;
        catch err
            lastErr = err;
            io = [];
        end
    end
    if isempty(io)
        error('lecroy:connect:VisaOpenFailed', ...
            'Could not open VISA resource "%s". Last error: %s', resource, lastErr.message);
    end
    session.backend = "visa";
end

session.io = io;
session.resource = string(resource);
session.createdAt = datetime('now');

% Open for visadev is implicit; for visa toolbox it has already been fopen'd.
if session.backend == "visadev"
    try
        flush(io);
    catch
    end
end

if cfg.connection.clearOnConnect
    try
        lecroy.clear(session);
    catch
    end
end

end

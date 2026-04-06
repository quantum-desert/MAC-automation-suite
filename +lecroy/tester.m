% tester
clear all;
resource = "USB0::0x05FF::0x1023::4609N02990::0::INSTR";
io = visadev(resource)
configureTerminator(io,"LF");

cmd = "*IDN?";
writeline(io,cmd);
response=readline(io)
% % tester
clear all;
resource = "USB0::0x05FF::0x1023::4609N02990::0::INSTR";
io = visadev(resource);
writeline(io,"STOP")
% readline(io)


% 
% out = lecroy_waveform_all_parser(io, "C1")
% 
% %%
% plot(out.t(1:1e3),out.volts(1:1e3));


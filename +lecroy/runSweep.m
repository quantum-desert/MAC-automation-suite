function history = runSweep(cfg)
% lecroy.runSweep  Convenience wrapper around the Brain object.
brain = lecroy.Brain(cfg);
history = brain.run();
end

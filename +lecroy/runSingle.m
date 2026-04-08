function history = runSingle(cfg,session)
% lecroy.runSweep  Convenience wrapper around the Brain object.
brain = skull.Brain(cfg,session);
history = brain.runSingle();
end

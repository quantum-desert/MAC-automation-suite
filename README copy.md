# LeCroy acquisition + post-processing package (MATLAB)

This package now includes three pieces:

- the original VISA-based single-run acquisition package
- a **minimal refactor** of the uploaded MATLAB post-processing script into callable functions
- a **Brain** object that runs the entire acquisition sweep for a configurable amount of time

## Main entry points

- `lecroy.acquireRun(cfg)` – one acquisition run
- `postprocess.processRun(runFolder, cfg)` – one post-processing pass
- `lecroy.runSweep(cfg)` – repeated acquisition/process loop using `lecroy.Brain`

## Brain timer control

The sweep runtime is configured in the main config file:

```matlab
cfg = lecroy.defaultConfig();
cfg.brain.runDurationSeconds = 300;
cfg.brain.pauseBetweenRunsSeconds = 1;
```

The Brain object keeps launching runs until the elapsed wall-clock time exceeds `runDurationSeconds`.

## Post-processing refactor scope

The post-processing refactor is intentionally conservative:

- the original constant definitions are preserved in config helpers
- the original processing order is preserved
- `preprocess_data`, `matched_downsample`, and `build_physics` were moved into separate files with only minimal edits needed to make them callable
- filename construction was moved into `postprocess.buildRunFilenames`
- the original console report was moved into `postprocess.displayReport`

The one area that could not be reproduced verbatim from the uploaded snippet was `visualize_v2`, because only partial plotting code was available from the uploaded text. A lightweight replacement is included, and plotting is optional by config.

## Files added for the refactor

- `+postprocess/defaultConfig.m`
- `+postprocess/processRun.m`
- `+postprocess/preprocess_data.m`
- `+postprocess/matched_downsample.m`
- `+postprocess/build_physics.m`
- `+postprocess/displayReport.m`
- `+lecroy/Brain.m`
- `+lecroy/runSweep.m`
- `examples/example_run_sweep.m`

## Important note

The refactor tries to avoid changing your processing logic, but I could only work from the uploaded text snippet rather than a full runnable repo tree. The core processing functions were reconstructed from the available code fragments; the plotting function was the least complete source fragment and is therefore the least certain part of the refactor.

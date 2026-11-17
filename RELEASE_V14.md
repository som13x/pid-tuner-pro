# PID Tuner Pro v1.4 Preview

## Multi-Model Robust Auto Tune from Loop History

- Select at least two real Step Test records from the **same** loop.
- Require stored, finite measured fit quality R² >= 0.90, NRMSE <= 0.10; never synthesize fit scores.
- Require identical nonempty operating-point text and consistent process gain sign.
- Validate physical FOPDT parameters and reject duplicate test IDs.
- Run time-domain robust optimization and frequency-domain stability analysis in a Flutter isolate (`compute`).
- Show shortlisted feasible PB/Ti candidates, scenario count, and worst-case IAE.
- Add six validation tests.

## Engineering limitations

- Operating points are currently free-text and exact-match, not normalized engineering quantities. No inference that different texts represent equivalent regimes.
- RobustAutoTune searches time-domain feasibility first; StabilityStudio frequency-checks only the top 20 candidates, so feasible alternatives may be missed.
- Bounding-box K/T/L corners are hypothetical scenarios, not statistical confidence intervals.
- Simulation and margin checks are advisory; do not apply settings to an operating plant without engineering validation and authorized commissioning.
- No Dart/Flutter SDK in authoring environment: source compilation and tests have NOT been executed.

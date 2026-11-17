# PID Tuner Pro v2.7 — RL-like Signal Filter / External Tracking Lab

## What was added

A new **RL / Tracking Lab** button is available in each loop project.
When a previously identified K/T/L model exists, the lab uses its
FOPDT parameters; otherwise the inputs are explicitly marked as demo data.

Two **independent** signal paths are available:

1. **RL-like input monitor:** a synthetic external signal with a step and
   sinusoidal noise is passed through an optional first-order low-pass
   filter. The filter is initialized on the first sample and uses exact
   discretization alpha = exp(-dt/T). Time constant zero disables it.
   In this demo the filtered external signal is **NOT used** as PI PV or
   to reset the integrator. Its purpose is to show how independent signal
   filtering changes amplitude and delay.

2. **External actuator MV tracking:** compare the same ideal normalized PI
   controller without tracking and with feedback from the previous-scan
   downstream *actual actuator MV*. Actual MV follows requested MV through
   a synthetic first-order actuator lag. With tracking enabled the
   controller integral uses the simplified back-calculation term:

       I[k+1] += (dt / trackingTime) * (actualMV[k] - commandedMV[k])

   This makes it an illustrative anti-windup/reset model, not a precise
   implementation of any vendor control block.

A compare view plots PV/SP, controller demanded MV against actual
actuator MV, and the independent RL-like signal before/after the lag.
It reports IAE, peak PV error and travel of commanded MV. More tracking
is **not** presumed better: the metrics show the actual result for the
chosen synthetic scenario.

## Important boundaries

**CENTUM VP RL1/RL2 terminal semantics are not inferred.** Their meanings
depend on the specific block, its configuration, and the signal source.
For example, if RL1 receives a flow PV from a different controller, that
does not make it a measured physical actuator output and it MUST NOT be
silently treated as external reset feedback.

- Filtering the RL input is **not** equivalent to filtering FIC.PV before
  the FIC algorithm, the output tracking (BKCAL), or the external reset path.
- The tracking model requires feedback of actual actuator MV in the
  normalized 0–100% range. When tracking is enabled but the signal is
  missing or out of range, simulation fails explicitly.
- Tracking time must be at least the simulation sample time. A tracking
  correction is applied to the *next scan* only, preserving current-scan
  command continuity.
- The model does not emulate CENTUM VP RL terminal functions, tracking
  algorithms, ratio/link control, scan timing, write permission, or
  firmware behavior.
- No DCS network connection or controller parameter writes are present.

## Tests

Core tests validate independent first-order RL filtering, zero-lag bypass,
tracking input errors, direction of the back-calculation effect, negative
process gain, finite outputs, and scenario validation. Flutter smoke
tests validate the new screen and model-provenance warning.

Run from the repository:

    dart pub get
    dart test
    dart analyze lib test
    cd flutter_example
    flutter pub get
    flutter test
    flutter analyze --no-fatal-infos
    flutter build apk --debug --split-per-abi

Review any real CENTUM VP RL usage against vendor control-block manuals
and plant-specific function block documentation before connecting signals.

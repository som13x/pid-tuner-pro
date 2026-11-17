# PID Tuner Pro v3.4 — OptiControls Level Controller Tuning

**Source of this implementation:** Jacques Smuts, "Level Controller Tuning",
OptiControls Control Notes, 16 December 2011:
https://blog.opticontrols.com/level-control-loop-tuning/

This release **replaces the selectable SIMC integrating rule** with the
published OptiControls method. It DOES NOT silently reclassify historical
SIMC/λ records as OptiControls.

## Settings

For a confirmed integrating level process, the recommendation is
"Level Controller Tuning (OptiControls)". The Settings form now asks:

- Controlled variable (level or another measured integrating process)
- Confirmation that actual step-test behavior is **integrating**
- **PI** or **PID** variant of OptiControls Level Controller Tuning
- **Stability Margin (SM)**, default **2.0**, must satisfy **SM ≥ 2.0**
- Step Test: manual IPDT ramp or CSV IPDT trend

The former λ field and SIMC selector are retired from new Settings.
Older Settings referring to SIMC can be loaded, but are blocked from
new tuning. Settings shows a migration notice and requires the operator
to review and save the new OptiControls method explicitly.

## Published formulas and units

Calculate normalized integration rate:

    slope_change = slope_after - slope_before
    DS_percent_per_sec = slope_change * 100 / (PV_high - PV_low)
    dCO_percent = (MV_after - MV_before) * 100 / (MV_high - MV_low)
    ri = DS_percent_per_sec / dCO_percent

Here `ri` (equivalent to IPDT Ki) is in
`(%PV / second) / (%MV)`; `td` is measured effective process dead
time in **seconds**, strictly greater than zero. Use the magnitude
`abs(ri)` in the tuning correlations; use the original sign to
identify the direction of controller action for engineering verification.

OptiControls **PI** correlation:

    Kc = 0.9 / (SM * abs(ri) * td)
    Ti = 3.33 * SM * td
    Td = 0

OptiControls **PID** correlation:

    Kc = 1.2 / (SM * abs(ri) * td)
    Ti = 2 * SM * td
    Td = td / 2

`Ti` and `Td` are both **seconds** in this app. If the DCS uses
minutes, convert. For a controller using PB: `PB = 100/Kc`.
These are published tuning rules for an **interacting PID algorithm**,
and may work differently with noninteracting or parallel controller
forms. The article explains that parallel conversion needs
appropriate changes to integral and derivative parameters.
The app reports normalized engineering estimates, **not verified
native DCS settings**. Actual controller algorithm, scaling,
integration form, units, direction, tracking, limits and noise
sensitivity require independent verification.

## Step Test

The integrating process Step Test remains the dedicated IPDT
measurement pathway. It estimates `ri` from the **difference between
post-step and pre-step PV slopes** divided by MV change and estimates
`td` from the dead time (manual input or CSV fit). Steady-state PV1,
FOPDT gain K and t63% are **not** used. CSV quality scores and
warnings remain available.

OptiControls recommends: tune an inner flow controller first if the
level loop is in cascade; minimize uncontrolled inlet/outlet
disturbances; wait for a stable initial PV slope; make a step that is
large enough to produce a clear slope change, about 5–10% where
safe and authorized; measure the later slope; restore the vessel to a
safe operating level. This is *not* an authorization to alter a
running plant. Actual operator-approved test limits override
all generic examples.

OptiControls explicitly warns that **surge tank/level-averaging**
applications need a different rule to limit downstream flow
variability. This specific method targets comparatively fast
recovery from disturbances.

## Persistence / compatibility

Safari IndexedDB stores Settings (`stabilityMargin`,
`levelControlMode`, confirmation flag and acquisition method) and
append-only IPDT identification records with the settings snapshot.
Historical SIMC/λ records retain their original method and formula
provenance; prior tuning values are never relabeled. No IndexedDB
schema migration or destructive deletion is necessary.

## Validation / deployment

CI runs Dart tests, Flutter widget/database tests and Flutter web
release build. After successful release, the same Safari URL is used:

https://som13x.github.io/pid-tuner-pro/

Results have no live DCS connection and must **not** be copied into
a plant PID block without verification.

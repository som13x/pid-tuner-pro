# PID Tuner Pro v2.9 — Manual Step Test (offline FOPDT estimate)

## User-facing changes

**Step Test · FOPDT** now has two tabs:

1. **CSV / тренд** — all existing functionality remains: import CSV/TXT
   or paste columns time,mv,pv; fit FOPDT, report regression metrics,
   verify fit quality and save the model only when the CSV-specific
   quality criteria are met.
2. **Ручной ввод** — use measured pre/post-step MV and PV in engineering
   units, explicit low/high spans for both variables, and time
   observations from the moment the MV step was applied.

Two manual time methods are provided:

- **Known dead time L and t63**:
  \`T = t63 - L\`, where t63 is time from the MV step to the
  63.212% response level, not time since the PV first moved.
- **Two points t28 and t63**: t28 is the time from the MV step to
  \`1 - exp(-1/3)\` (28.3469%) of the final PV change;
  t63 is time from the MV step to \`1 - exp(-1)\` (63.2121%).
  \`T = 1.5 * (t63 - t28)\`; \`L = t63 - T\`.
  Rejects noncausal crossings that imply negative L.

The algorithm computes raw engineering gain
\`K_eng = (PV_after-PV_before)/(MV_after-MV_before)\`.
The stored normalized FOPDT gain, as expected by Auto Tune, is:

    K = ((PV_after - PV_before)/(PV_high - PV_low))
        / ((MV_after - MV_before)/(MV_high - MV_low))

This respects nonzero low spans, supports negative process gain, and
uses the same normalized gain convention as the other offline models.

## Result and provenance

The manual result displays K/T/L, engineering gain and normalized
PV/MV step sizes. A predicted response curve is synthetic; it is
**not** actual measurement points.

Manual input **cannot** produce valid regression R², NRMSE, RMSE,
real step quality checks, or independent process verification. No
fabricated fit quality is displayed or stored. The model is saved with:

- source \`Manual Step 63.2%\` or \`Manual Step 28.3/63.2%\`
- source input evidence, scales, times, and \`qualityMetricsAvailable=false\`
- null R² and NRMSE, \`requiresEngineeringReview=true\`
- the existing per-loop append-only history and SQLite identifications

Before saving, the user must explicitly confirm that values were
observed on a single sustained step and that engineering verification
is still required. Before opening Auto Tune for a manual model,
another explicit confirmation appears. **Auto Tune remains an offline
simulation, not a recommendation to change actual DCS settings.**

The current SQLite and JSON backup schemas already permit nullable
regression metrics and preserve the event JSON, so no schema migration
or change to existing CSV records is needed.

## Testing

- Dart tests: manual normalization, negative gain, method parity,
  nonzero span lows, synthetic response, invalid spans, noncausal
  time observations.
- Flutter tests: two Step Test tabs, method switch, explicit consent,
  persistence of manual evidence, NULL fit quality, no fake metrics.
- GitHub CI: core tests+analysis, Flutter tests+analysis and Android
  debug APK build.

## Engineering limits

This is **estimate-from-manual-observations**, not automated execution
of a plant step or a verified digital twin. Valid FOPDT assumptions
include an isolated MV step, near-steady starting/ending PV, a
constant operating point, and an approximately first-order dominant
response. If these assumptions do not hold, the output is not
reliable. Confirm plant safety/permits before any real step.

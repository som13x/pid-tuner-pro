# PID Tuner Pro v2.8 — Cascade Circuit Studio preview

## New Android interface

Use the **Circuit Studio** action from a loop's card or launch a
demo from the top app bar. The screen has three tabs:

- **Схема:** interactive pan/zoom diagram with TIC1, FIC1, LAG and AS-M;
  live, observational and filtered signals have different colors.
- **Связи:** enable/disable the supported typed links. Invalid links,
  multiple sources to one input, and an undriven LAG output are rejected.
- **Тренды:** configure two *separate* synthetic FOPDT plants, PI tuning,
  LAG and actuator time constants, step scenarios and disturbances.
  Compare TIC SP/PV, FIC SV/PV, commanded/actual MV, and monitor RL signals.

A project-attached schematic can be saved to the existing append-only
SQLite event history and will be restored when reopening the project.
It is included in v2.3's JSON backup because the backup already preserves
all project events. Demo mode without a project is session-only.

## Wiring rules

| Source | Destination | Simulated behaviour |
|---|---|---|
| TIC1.MV | FIC1.SV | **Live cascade connection:** TIC output drives FIC setpoint |
| FIC1.PV | LAG.IN | Supplies the LAG monitor filter |
| LAG.OUT | TIC1.RL1 | Observational monitor only |
| FIC1.PV | TIC1.RL1 | Observational direct-input alternative to LAG.OUT |
| AS-M.MV | FIC1.RL1 | Observational monitor of synthetic actuator output |

The first four connections in the user-interface sketch are enabled
by default (TIC.MV→FIC.SV, FIC.PV→LAG.IN, LAG.OUT→TIC.RL1,
AS-M.MV→FIC1.RL1). The direct-PV-to-RL option is available as an
alternative to using LAG. Both sources **cannot** drive TIC1.RL1
simultaneously.

**Never assume an RL input is an external reset or PID tracking input.**
The real function of RL1/RL2 depends on the exact Yokogawa function
block, operating mode and block configuration. This preview deliberately
does not feed any RL monitor line back into either PID algorithm.

## Calculation scope

The offline simulation connects:

    TIC.SP → TIC (ideal PI) → TIC.MV → FIC.SV
    FIC.SV → FIC (ideal PI) → FIC.MV → AS-M lag
    AS-M.MV → inner FOPDT → flow PV
    flow PV → outer FOPDT → temperature PV

All signals are normalized to percent span and initialized at 50%.
The measured flow can receive a synthetic step disturbance. These are
two distinct processes: a model identified for a *single* loop is
**not** automatically reused for either branch in the cascade.

The optional LAG monitors FIC.PV without altering TIC's or FIC's
control calculation. When the live TIC.MV → FIC.SV link is disabled,
FIC.SV remains fixed at 50%, making a disconnected experiment possible.

No cyclic arbitrary graph execution, user-created new block types,
true finger-based node dragging, connection to DCS, live data capture,
or validated hardware-specific PID behavior is included yet.
Pan and pinch-zoom of the diagram are supported.

## Safety and verification

- No live DCS reads/writes or configuration deployment.
- Values, including PB and Ti, are not plant-ready tuning recommendations.
- RL links are labeled monitor-only and intentionally isolated from
  PID reset/tracking until exact block semantics have been established.
- Every persistent graph is validated when saved and restored.
- Graph version 1 is explicit; unsupported versions/ports are rejected.
- New Dart tests verify typing and topology, connection-driven
  simulation, RL noninterference, negative process gains and invalid
  scenarios. Flutter tests verify saved diagrams and UI switch controls.
- CI runs all core and Flutter tests, analyzes both packages and builds
  split debug Android APKs.

**This is an engineering sandbox, not a CENTUM VP firmware replica.**

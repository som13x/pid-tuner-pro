# PID Tuner Pro v3.5 — OptiControls manual four-point Step Test

## Reason for change

The v3.4 manual IPDT Step Test asked for the post-step PV slope from
two points and requested the pre-step PV slope as a direct numeric
input. That omitted the four-point procedure used in Jacques Smuts's
**Level Controller Tuning** article (OptiControls, 2011).

Source: https://blog.opticontrols.com/level-control-loop-tuning/

The source explicitly says to measure **PV1 and PV2 on Slope 1**
and **PV3 and PV4 on Slope 2** and to compute the difference between
the slopes using the measured elapsed intervals T1 and T2.

## New manual Step Test fields

Use time in **seconds relative to the MV step time t=0**:

- Slope 1 (before step): PV1 at t1 and PV2 at t2, t1 < t2 <= 0.
- Slope 2 (after dead time): PV3 at t3 and PV4 at t4,
  measured dead time L < t3 < t4.
- Controller output MV0, MV1, MV and PV span low/high.
- Measured dead time L, from the time between MV step and the
  intersection of the extrapolated Slope 1 / Slope 2 lines.

All four PV values are in the **engineering units of the PV span**.
Do **not** try to wait for PV to settle to a constant when the process
is truly integrating.

The app computes:

    T1 = t2 - t1
    T2 = t4 - t3
    slope1 = (PV2 - PV1) / T1
    slope2 = (PV4 - PV3) / T2
    DS = slope2 - slope1
    DS_pct_per_sec = 100 * DS / (PV_span_high - PV_span_low)
    dMV_pct = 100 * (MV1 - MV0) / (MV_span_high - MV_span_low)
    ri = DS_pct_per_sec / dMV_pct

The ri result carries its **sign**, in units 1/second, to help
verify controller action. OptiControls PI/PID tuning calculations
from v3.4 take its magnitude for proportional gain:

    PI:  Kc = 0.9 / (SM * |ri| * L)
         Ti = 3.33 * SM * L ; Td = 0
    PID: Kc = 1.2 / (SM * |ri| * L)
         Ti = 2 * SM * L ; Td = L / 2

SM >= 2. PID values assume the interacting controller algorithm and
require independent transformation for other PID implementations.

## Error prevention and history

- No sample plant values are pre-filled in measurement fields.
- Impossible timing order, a too-small MV step, out-of-span values,
  invalid engineering scales and near-zero slope change are rejected.
- Result shows measured T1/T2, both slopes, DS, ri and L.
- IndexedDB saves **all four PV values and all four timestamps** with
  the Settings snapshot and the calculated IPDT model.
- **Existing historic two-point IPDT results are not modified**.
- CSV integrating identification and other FOPDT tests are unchanged.

This is a calculation aid, not authorization to conduct a level step
test on live process equipment. Ensure operator approval, sufficient
capacity margin and a site-specific safe return procedure.

Browser preview after green CI and publishing:
https://som13x.github.io/pid-tuner-pro/

# PID Tuner Pro v2.4 — DCS Controller Profiles (preview)

## Scope

This increment adds a controller-profile catalogue to the existing offline
Flutter application. Profiles can be selected when creating a control loop
or changed later from the loop card. A profile change is appended to the loop's
audit history; old K/T/L identifications and existing tuning reports are not
rewritten.

Auto Tune still optimizes **ideal normalized PI** using proportional band
PB (%), integral time Ti (s) and Kc = 100 / PB. Each candidate and its
baseline now carries a DCS-labelled equivalent. The selected profile and
engineering limitations are stored inside saved Auto Tune JSON reports.

**This is not a DCS-specific control algorithm or validated firmware model.**
Do not use any displayed equivalent as a direct instruction to write to a live
controller.

## Supported profiles

| System | Block | Tuning label | Display rule |
|---|---|---|---|
| Yokogawa CENTUM VP | PID | PB (%) | PB |
| Siemens PCS 7 | PIDConL | GAIN (normalized equivalent) | 100 / PB |
| ABB 800xA AC 800M | PidCC | Gain (normalized equivalent) | 100 / PB |

All proportional-gain equivalents assume PV and MV are normalized to the
same 0–100% span. With engineering-unit scaling, vendor gain may differ.
Ti is carried as seconds. D action is currently **not optimized** (Td=0
for PI candidates). Suggested control action derives from the sign of the
identified process gain and must be checked against block configuration.

ABB 800xA may host control systems other than AC 800M and algorithm choices
other than PidCC. Siemens PIDConL has specific normalization and proportional
setpoint weighting options. Yokogawa offers PID, I-PD, PI-D, and automatic
algorithm selection. Those vendor-specific details are **not simulated** in
the v2.4 optimization and have to be verified separately.

## Source documentation

- Yokogawa: https://www.yokogawa.com/library/resources/white-papers/pid-tuning-in-distributed-control-systems/
- Siemens PCS 7 PIDConL: https://www.automation.siemens.com/sce-static/learning-training-documents/pcs7/v9-0/p01-06-control-loop-v9-tud-0719-en.pdf
- ABB System 800xA, AC 800M Binary and Analog Handling:
  https://library.e.abb.com/public/01044bb4edcc4608b3a61391722b72fe/3BSE035981-600_A_en_System_800xA_Control_6.0_AC_800M_Binary_and_Analog_Handling.pdf

## Compatibility and tests

Profile identifiers are represented using the existing SQLite vendor/block
fields; no schema migration or loss of previous project data is required.
Unknown legacy controllers remain explicitly unsupported and are not silently
converted to Yokogawa.

Core tests cover profiles, PB/GAIN round-trips, guardrails and unsupported
blocks. Flutter tests cover unchanged FOPDT identification, append-only
profile-change audit entries, SQLite persistence and legacy compatibility.

## Implementation limits

- No live DCS connection, import of DCS configuration, or parameter writes.
- No validated ABB / Siemens digital twin, no gain scaling from actual
  engineering ranges, and no vendor anti-windup/algorithm emulation.
- Simulation remains a generic normalized model even with a DCS profile.
- Robust tuning remains model-dependent; requires validated Step Tests and
  authorized site-specific engineering review before plant use.

# PID Tuner Pro v3.2 — Safari Settings and Step Test

## Workflow

The Safari preview presents two tabs: **Settings** first, **Step Test**
second. Step Test is accessible after the user saves a valid configuration.

Settings collects:
- Loop name / TAG (required), comments
- DCS: Yokogawa CENTUM VP PID, ABB 800xA PidCC, Siemens PCS 7
  PIDConL, Honeywell Experion PKS PID, Emerson DeltaV PID
- Controlled variable: flow, pressure, temperature, level or other
- Suggested and selected *PI* tuning correlations
- Selected Step Test data acquisition: known L and 63.21% time,
  28.35% and 63.21% time, or CSV trend
- Method-specific instructions and cautions

Step Test uses the saved data acquisition method and allows manual
MV/PV measurements or CSV trend fitting. It displays K/T/L and
provisional DCS-formatted PI parameters and saves the result to IndexedDB.

## Database

Safari stores settings in browser IndexedDB database
pid-tuner-pro-step-test, with schema version 1.
The settings object store holds the active configuration; the
identifications object store is append-only and stores each model,
time, method, evidence, optional measured fit metrics, preliminary
PI result and snapshot of original settings. Original CSV text is
also saved for CSV results. Writes are confirmed only after their
database transaction completes. Data are restored on reload.

This is local Safari storage, **not** remotely synchronized; site
data deletion, storage eviction, private browsing or switching devices
can remove data. Browser backup/export is not implemented yet.

## Correlations and safety

All correlations are theoretical ideal **PI**, not full PID:
- Conservative IMC/Lambda: Kc = T / (|K|(lambda + L)), Ti = T
- Open-loop Ziegler–Nichols: Kc = 0.9 T / (|K| L), Ti = 3.33 L
- Open-loop Cohen–Coon:
  Kc = (T / (|K| L)) (0.9 + L/(12T));
  Ti = L(30 + 3L/T)/(9 + 20L/T)

Derivative time Td = 0. The vendor selection changes the parameter
presentation: Yokogawa CENTUM VP PB% = 100/Kc; the other systems
show normalized gain equivalents. These are not certified native
block settings. Actual PID block type, parameters, scaling, algorithm,
direction, integrator tracking, units and plant constraints must
be checked. Level regulation may be integrating; normal FOPDT PI
tuning is blocked until self-regulating behaviour is confirmed.

Step Test procedures are generic and require site-specific approval,
risk review and safe operating limits. No DCS writes are performed.

## Delivery

CI checks Dart tests and Flutter widget tests, builds Safari Web
and deploys files to the gh-pages branch. The site URL after successful
publication is https://som13x.github.io/pid-tuner-pro/.

Android and the native iPhone app are unchanged.

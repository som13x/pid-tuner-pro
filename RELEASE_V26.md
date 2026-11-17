# PID Tuner Pro v2.6 — PV filter and bumpless control preview

## New controls in Closed-Loop Simulation
- **PV filter, seconds**: optional first-order lag on controller PV:
  \`PV_f[k] = alpha * PV_f[k-1] + (1-alpha) * PV[k]\`,
  where \`alpha = exp(-dt/tau)\`. A zero time constant disables it.
  The first sample initializes the filter to the current measured PV.
- **D filter, seconds**: existing derivative low-pass constant, now editable
  independently of the PV filter.
- **Controller action**: choose Reverse or Direct; default recommendation is
  based on identified process gain (positive K => Reverse, negative K => Direct)
  and must be verified against actual valve action.
- **PV plot selector**: show either raw measured PV or filtered controller PV.
  SP reference remains visible; performance metrics remain based on raw PV.

## Algorithm and transfer behavior
PID, PI-D and I-PD retain distinct proportional and derivative inputs.
All paths use filtered PV for feedback when the PV lag is enabled.

For the first MAN => AUTO scan, the integral state is initialized from the
manual output and the current P/D contributions. Integration is skipped for
that transfer scan to maintain the existing MV; subsequent scans resume
normal conditional integration and configured actuator slew limiting.

## Tests
Core tests check zero-filter equivalence, exact exponential lag, attenuation
of alternating PV noise, config validation, first-scan zero-bump transfer
across three PID structures, and filtered PV availability through
ClosedLoopStudio comparisons. Flutter widget tests verify the new UI fields
and explicit direction selection. CI runs Dart/Flutter tests and produces
debug Android APKs.

## Engineering warnings
- PV filtering adds phase lag and can **worsen** stability or disturbance
  rejection, particularly with significant dead time.
- This is not the same as filtering a CENTUM VP RL terminal or implementing
  external-reset feedback. Those paths need distinct modeling and testing.
- This simulation is a generic normalized PID approximation. It is not
  verified Yokogawa, Siemens or ABB firmware behavior.
- MAN/AUTO transfer only simulates the algorithm's internal output tracking.
  Valve dynamics, external tracking, interlocks, scan scheduling, clamping
  and real DCS mode transitions have not been validated.
- No connection or writes to industrial systems exist. Never deploy proposed
  gains to an operating controller without proper identification and
  approved engineering trials.

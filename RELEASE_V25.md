# PID Tuner Pro v2.5 — PID algorithm selection (preview)

The Simulation Studio now provides a structure selector:
- **PID**: proportional, integral and derivative terms act on error.
- **PI-D**: proportional and integral on error; derivative on PV.
- **I-PD**: integral on error; proportional and derivative on PV.
- **Compare all**: overlay the three structures in the same normalized FOPDT simulation.

The selected structure filters both the metrics table and plotted response.
Switching the selection does not discard the latest simulation run.

**AUTO/MAN is an operating mode, not a PID structure.** In particular,
the CENTUM VP vendor-specific "automatic" algorithm option is not
implemented by this selector.

## Engineering scope

This uses the existing generic discrete positional controller simulator.
It is an **engineering approximation**, not a firmware-validated Yokogawa,
Siemens, or ABB PID algorithm. In particular, vendor-specific reset,
tracking, derivative filter, setpoint weighting, scaling and algorithm
switching have not been calibrated against an actual DCS block.

Additional unit tests verify the proportional/derivative setpoint kick
distinctions and bumpless MAN to AUTO transition. A Flutter widget test
checks the algorithm selector and the explicit mode warning.

No external DCS communication or writes are performed.

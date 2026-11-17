# PID Tuner Pro v1.6 Preview

Added `lib/centum_pid_simulator.dart` with a discrete positional PID engineering model:
- PID, PI-D, I-PD structures with filtered derivative.
- Direct/reverse control action.
- Manual/auto transfer with output tracking, output bounds, MV slew limit, conditional anti-windup.
- Unit tests for transfer, action, slew/saturation, setpoint kick and invalid parameters.

**Important:** This is a generic engineering approximation, NOT a verified byte-for-byte Yokogawa CENTUM VP PID implementation. The real block's algorithms, tuning units, tracking/anti-reset-windup and mode semantics must be verified against the actual CENTUM VP manual and controller configuration before use. No plant connection or write functionality. Dart/Flutter toolchains unavailable in build environment, so tests have not been executed.

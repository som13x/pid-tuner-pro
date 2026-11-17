import 'dart:math' as math;

/// Engineering approximation, NOT a validated CENTUM VP firmware replica.
/// All signals are normalized to percent of span. PB is percent, Ti/Td seconds.
enum PidStructure { pid, piD, iPd }
enum ControllerMode { manual, auto }
enum ControllerAction { reverse, direct }

class CentumPidConfig {
  final double pb, ti, td, dt, mvMin, mvMax, maxMvRate;
  final double derivativeFilterSeconds;
  /// First-order low-pass on PV before P, I and D calculations. 0 disables.
  final double pvFilterSeconds;
  final PidStructure structure;
  final ControllerAction action;
  const CentumPidConfig({
    required this.pb, required this.ti, this.td = 0, this.dt = 0.1,
    this.mvMin = 0, this.mvMax = 100, this.maxMvRate = double.infinity,
    this.derivativeFilterSeconds = 1,
    this.pvFilterSeconds = 0,
    this.structure = PidStructure.pid,
    this.action = ControllerAction.reverse,
  });
  void validate() {
    if (!pb.isFinite || pb <= 0 || !ti.isFinite || ti <= 0 ||
        !td.isFinite || td < 0 || !dt.isFinite || dt <= 0 ||
        !mvMin.isFinite || !mvMax.isFinite || mvMin >= mvMax ||
        maxMvRate.isNaN || maxMvRate <= 0 ||
        !derivativeFilterSeconds.isFinite || derivativeFilterSeconds <= 0 ||
        !pvFilterSeconds.isFinite || pvFilterSeconds < 0) {
      throw ArgumentError('Invalid PID configuration');
    }
  }
}

class PidSnapshot {
  final double mv, requestedMv, p, i, d, error, filteredPv;
  final bool saturated, rateLimited;
  final ControllerMode mode;
  const PidSnapshot(this.mv, this.requestedMv, this.p, this.i, this.d,
      this.error, this.saturated, this.rateLimited, this.mode,
      this.filteredPv);
}

/// Discrete positional PID, conditional anti-windup, filtered derivative,
/// slew-limited output and bumpless MAN->AUTO tracking.
/// SP/PV are in engineering-normalized percent. `reverse` means increasing
/// PV reduces MV. `direct` means increasing PV increases MV.
class CentumPidSimulator {
  final CentumPidConfig config;
  late double _mv, _integral, _previousPv, _previousError, _filteredD;
  double _filteredPv = 0;
  bool _pvFilterInitialized = false;
  bool _initialized = false;
  ControllerMode _mode = ControllerMode.manual;

  CentumPidSimulator(this.config, {double initialMv = 50}) {
    config.validate();
    if (!initialMv.isFinite) throw ArgumentError('Invalid initial MV');
    _mv = initialMv.clamp(config.mvMin, config.mvMax).toDouble();
    _integral = 0;
    _previousPv = 0;
    _previousError = 0;
    _filteredD = 0;
  }

  double get mv => _mv;
  ControllerMode get mode => _mode;

  PidSnapshot step({required double sp, required double pv,
      required ControllerMode mode, double? manualMv}) {
    if (!sp.isFinite || !pv.isFinite || (manualMv != null && !manualMv.isFinite)) {
      throw ArgumentError('Non-finite controller input');
    }
    final c = config;
    // The first sample initializes the filter at measured PV. This avoids
    // introducing an artificial start-up error from an assumed 0% PV.
    if (!_pvFilterInitialized) {
      _filteredPv = pv;
      _pvFilterInitialized = true;
    } else if (c.pvFilterSeconds == 0) {
      _filteredPv = pv;
    } else {
      final pvAlpha = math.exp(-c.dt / c.pvFilterSeconds);
      _filteredPv = pvAlpha * _filteredPv + (1 - pvAlpha) * pv;
    }
    final usedPv = _filteredPv;
    final sign = c.action == ControllerAction.reverse ? 1.0 : -1.0;
    final error = sign * (sp - usedPv);
    final kp = 100 / c.pb;
    final pInput = c.structure == PidStructure.iPd ? -sign * usedPv : error;
    final p = kp * pInput;
    final derivativeInput = c.structure == PidStructure.pid ? error : -sign * usedPv;
    if (!_initialized) {
      _previousPv = usedPv;
      _previousError = error;
      _initialized = true;
    }
    final previousDerivativeInput = c.structure == PidStructure.pid
        ? _previousError : -sign * _previousPv;
    final rawDerivative = kp * c.td *
        (derivativeInput - previousDerivativeInput) / c.dt;
    final alpha = math.exp(-c.dt / c.derivativeFilterSeconds);
    _filteredD = alpha * _filteredD + (1 - alpha) * rawDerivative;
    final d = c.td == 0 ? 0.0 : _filteredD;
    _previousPv = usedPv;
    _previousError = error;

    if (mode == ControllerMode.manual) {
      final target = (manualMv ?? _mv).clamp(c.mvMin, c.mvMax).toDouble();
      _mv = target;
      _integral = _mv - p - d; // track manual output for bumpless transfer
      _mode = mode;
      return PidSnapshot(_mv, target, p, _integral, d, error,
          false, false, mode, usedPv);
    }
    final enteringAuto = _mode != ControllerMode.auto;
    if (enteringAuto) {
      // Track the actual manual output against the CURRENT P and D terms.
      // Do not integrate on the transfer scan: first AUTO MV remains exactly
      // the same even if SP/PV changed while in MAN.
      _integral = _mv - p - d;
    }
    _mode = mode;
    final increment = enteringAuto ? 0.0 : kp / c.ti * error * c.dt;
    final proposedI = _integral + increment;
    final requested = p + proposedI + d;
    final bounded = requested.clamp(c.mvMin, c.mvMax).toDouble();
    final maxDelta = c.maxMvRate * c.dt;
    final delta = (bounded - _mv).clamp(-maxDelta, maxDelta).toDouble();
    final next = (_mv + delta).clamp(c.mvMin, c.mvMax).toDouble();
    final constrained = (requested - next).abs() > 1e-9;
    // Integrate only if not constrained, or when moving back towards the
    // achievable MV. This is a simplified conditional anti-windup scheme.
    if (!constrained || increment * (requested - next) < 0) {
      _integral = proposedI;
    }
    _mv = next;
    return PidSnapshot(_mv, requested, p, _integral, d, error,
        (bounded - requested).abs() > 1e-9,
        (bounded - next).abs() > 1e-9, mode, usedPv);
  }
}

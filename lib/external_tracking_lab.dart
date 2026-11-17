import 'dart:math' as math;

import 'auto_tune.dart';
import 'centum_pid_simulator.dart';

/// An *independent* first-order filter for a generic external input labelled
/// "RL-like" in the laboratory. The source may be an arbitrary measured signal;
/// it is NOT assumed to represent actuator MV, PID error, or CENTUM VP RL1/RL2.
class RlSignalLag {
  final double dt, tauSeconds;
  double? _state;

  RlSignalLag({required this.dt, required this.tauSeconds}) {
    if (!dt.isFinite || dt <= 0 ||
        !tauSeconds.isFinite || tauSeconds < 0) {
      throw ArgumentError('Invalid RL-like signal lag');
    }
  }

  double step(double input) {
    if (!input.isFinite) throw ArgumentError.value(input, 'input');
    final previous = _state;
    if (previous == null || tauSeconds == 0) {
      return _state = input;
    }
    final a = math.exp(-dt / tauSeconds);
    return _state = a * previous + (1 - a) * input;
  }
}

/// Synthetic experiment with two INDEPENDENT paths:
/// 1. a low-pass filter on an RL-like external signal, for visual inspection;
/// 2. optional external-reset *back-calculation* using actual actuator MV.
///
/// The RL-like filtered signal is NEVER fed into the reset feedback law.
/// The algorithm is generic and not a validated DCS terminal representation.
class ExternalTrackingScenario {
  final Plant plant;
  final double pb, ti, dt, duration;
  final double initialSp, initialPv, initialMv;
  final double spStepAt, spStep;
  final double rlStepAt, rlStep, rlNoiseAmplitude, rlLagSeconds;
  final double actuatorTauSeconds, trackingTimeSeconds;
  final double mvRateLimit;

  const ExternalTrackingScenario({
    this.plant = const Plant(gain: 0.8, tau: 12, delay: 2),
    this.pb = 120, this.ti = 20, this.dt = 0.2, this.duration = 160,
    this.initialSp = 50, this.initialPv = 50, this.initialMv = 50,
    this.spStepAt = 30, this.spStep = 5,
    this.rlStepAt = 45, this.rlStep = 10,
    this.rlNoiseAmplitude = 2, this.rlLagSeconds = 2,
    this.actuatorTauSeconds = 4, this.trackingTimeSeconds = 4,
    this.mvRateLimit = 5,
  });

  void validate() {
    plant.validate();
    final values = [
      pb, ti, dt, duration, initialSp, initialPv, initialMv,
      spStepAt, spStep, rlStepAt, rlStep, rlNoiseAmplitude,
      rlLagSeconds, actuatorTauSeconds, trackingTimeSeconds, mvRateLimit,
    ];
    if (values.any((v) => !v.isFinite) ||
        pb <= 0 || ti <= 0 || dt <= 0 || duration <= 0 ||
        duration / dt > 12000 || dt > plant.tau / 2 ||
        spStepAt < 0 || spStepAt > duration ||
        rlStepAt < 0 || rlStepAt > duration ||
        rlNoiseAmplitude < 0 || rlLagSeconds < 0 ||
        actuatorTauSeconds < 0 ||
        trackingTimeSeconds < dt || mvRateLimit <= 0 ||
        initialMv < 0 || initialMv > 100) {
      throw ArgumentError('Invalid tracking laboratory scenario');
    }
  }
}

class TrackingPoint {
  final double seconds, sp, measuredPv, requestedMv, actualMv;
  final double rawRlLike, filteredRlLike;
  const TrackingPoint(this.seconds, this.sp, this.measuredPv,
      this.requestedMv, this.actualMv, this.rawRlLike, this.filteredRlLike);
}

class TrackingMetrics {
  final double iae, maxAbsError, mvTravel, maxMvRate;
  const TrackingMetrics(this.iae, this.maxAbsError, this.mvTravel,
      this.maxMvRate);
}

class TrackingRun {
  final bool externalTracking;
  final List<TrackingPoint> points;
  final TrackingMetrics metrics;
  const TrackingRun(this.externalTracking, this.points, this.metrics);
}

class ExternalTrackingLab {
  static List<TrackingRun> compare(ExternalTrackingScenario s) {
    s.validate();
    return [simulate(s, externalTracking: false),
      simulate(s, externalTracking: true)];
  }

  static TrackingRun simulate(ExternalTrackingScenario s, {
    required bool externalTracking,
  }) {
    s.validate();
    final pid = CentumPidSimulator(CentumPidConfig(
      pb: s.pb, ti: s.ti, dt: s.dt,
      maxMvRate: s.mvRateLimit,
      action: s.plant.gain > 0
          ? ControllerAction.reverse : ControllerAction.direct,
      externalTrackingTimeSeconds: externalTracking
          ? s.trackingTimeSeconds : 0,
    ), initialMv: s.initialMv);
    final rlLag = RlSignalLag(dt: s.dt, tauSeconds: s.rlLagSeconds);
    final actuatorA = s.actuatorTauSeconds == 0
        ? 0.0 : math.exp(-s.dt / s.actuatorTauSeconds);
    final processA = math.exp(-s.dt / s.plant.tau);
    final count = (s.duration / s.dt).ceil();
    final points = <TrackingPoint>[];
    final history = <double>[];

    var actual = s.initialMv;
    var processState = s.initialPv;
    var previousRequested = s.initialMv;
    var iae = 0.0, maxError = 0.0, travel = 0.0, maxRate = 0.0;

    for (var k = 0; k <= count; k++) {
      final t = k * s.dt;
      final sp = s.initialSp + (t >= s.spStepAt ? s.spStep : 0.0);
      final rawRl = 50.0 + (t >= s.rlStepAt ? s.rlStep : 0.0) +
          s.rlNoiseAmplitude * math.sin(2 * math.pi * t / 1.6);
      final filteredRl = rlLag.step(rawRl);

      // The PI controller sees the process PV, NOT the independent RL signal.
      // Tracking, when enabled, uses downstream ACTUAL actuator position
      // from the previous scan to avoid a same-scan algebraic loop.
      final snap = pid.step(sp: sp, pv: processState,
        mode: ControllerMode.auto,
        externalTrackingMv: externalTracking ? actual : null);

      // The actuator may be slower than the controller's demand.
      actual = actuatorA * actual + (1 - actuatorA) * snap.mv;

      if (![snap.mv, actual, processState, filteredRl].every((v) => v.isFinite)) {
        throw StateError('Numerical divergence in tracking laboratory');
      }
      final error = sp - processState;
      if (k > 0) {
        iae += error.abs() * s.dt;
        final d = (snap.mv - previousRequested).abs();
        travel += d;
        maxRate = math.max(maxRate, d / s.dt);
      }
      maxError = math.max(maxError, error.abs());
      points.add(TrackingPoint(t, sp, processState,
        snap.mv, actual, rawRl, filteredRl));
      previousRequested = snap.mv;
      history.add(actual);
      if (k == count) break;

      // Linear interpolation of delayed REAL actuator MV.
      final index = k - s.plant.delay / s.dt;
      double delayedMv;
      if (index < 0) {
        delayedMv = s.initialMv;
      } else {
        final lo = index.floor();
        final hi = math.min(lo + 1, history.length - 1);
        final f = index - lo;
        delayedMv = history[lo] * (1 - f) + history[hi] * f;
      }
      final target = s.initialPv +
          s.plant.gain * (delayedMv - s.initialMv);
      processState = processA * processState + (1 - processA) * target;
    }

    return TrackingRun(externalTracking, List.unmodifiable(points),
      TrackingMetrics(iae, maxError, travel, maxRate));
  }
}

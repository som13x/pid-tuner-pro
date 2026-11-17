import 'dart:math' as math;
import 'auto_tune.dart';
import 'centum_pid_simulator.dart';

/// Two parallel valve branches discharging into a common measured header.
/// All flows and MV values are normalized engineering units, not m3/h.
/// A valve is held in MAN and experiences an imposed mechanical oscillation.
/// B valve controls combined flow. This is NOT a certified LNG plant model.
enum CompensationStrategy { pi, filteredPv, measuredFeedforward }

class DualValveScenario {
  final Plant branchA, branchB;
  final CentumPidConfig controllerB;
  final CompensationStrategy strategy;
  final double dt, duration, initialMvA, initialMvB;
  final double initialFlowA, initialFlowB, setpoint;
  final double faultAt, faultAmplitude, faultPeriod;
  final double pvFilterSeconds, feedforwardFraction;
  const DualValveScenario({
    required this.branchA, required this.branchB, required this.controllerB,
    this.strategy = CompensationStrategy.pi,
    this.dt = 0.2, this.duration = 240,
    this.initialMvA = 50, this.initialMvB = 50,
    this.initialFlowA = 50, this.initialFlowB = 50, this.setpoint = 100,
    this.faultAt = 40, this.faultAmplitude = 5, this.faultPeriod = 60,
    this.pvFilterSeconds = 2, this.feedforwardFraction = 1,
  });
  void validate() {
    branchA.validate(); branchB.validate(); controllerB.validate();
    final finite = [dt, duration, initialMvA, initialMvB, initialFlowA,
      initialFlowB, setpoint, faultAt, faultAmplitude, faultPeriod,
      pvFilterSeconds, feedforwardFraction];
    if (finite.any((v) => !v.isFinite) || dt <= 0 || duration <= 0 ||
        duration / dt > 100000 || faultAt < 0 || faultAmplitude < 0 ||
        faultPeriod <= 0 || pvFilterSeconds <= 0 ||
        feedforwardFraction < 0 || feedforwardFraction > 1 ||
        (controllerB.dt - dt).abs() > 1e-10 ||
        dt > math.min(branchA.tau, branchB.tau) / 2 ||
        branchB.gain == 0 ||
        initialMvB < controllerB.mvMin || initialMvB > controllerB.mvMax ||
        initialMvA < 0 || initialMvA > 100 ||
        faultAmplitude > math.min(initialMvA, 100 - initialMvA)) {
      throw ArgumentError('Invalid dual-valve scenario');
    }
    // Positive A/B gains and reverse controller are the supported case.
    if (branchA.gain <= 0 || branchB.gain <= 0 ||
        controllerB.action != ControllerAction.reverse) {
      throw ArgumentError('Expected positive branch gains and reverse action');
    }
  }
}

class DualValvePoint {
  final double t, sp, flowA, flowB, totalFlow, mvA, mvB, filteredPv, ffMv;
  const DualValvePoint(this.t, this.sp, this.flowA, this.flowB,
      this.totalFlow, this.mvA, this.mvB, this.filteredPv, this.ffMv);
}

class DualValveMetrics {
  final double iae, maxAbsError, totalMvBTravel, maxMvBRate;
  const DualValveMetrics(this.iae, this.maxAbsError,
      this.totalMvBTravel, this.maxMvBRate);
}

class DualValveRun {
  final CompensationStrategy strategy;
  final List<DualValvePoint> points;
  final DualValveMetrics metrics;
  const DualValveRun(this.strategy, this.points, this.metrics);
}

class DualValveLngSimulator {
  static DualValveRun simulate(DualValveScenario s) {
    s.validate();
    final pid = CentumPidSimulator(s.controllerB, initialMv: s.initialMvB);
    final historyA = <double>[];
    final historyB = <double>[];
    final points = <DualValvePoint>[];
    var a = s.initialFlowA, b = s.initialFlowB;
    var filteredPv = a + b;
    var previousMvB = s.initialMvB;
    var iae = 0.0, maxError = 0.0, travel = 0.0, maxRate = 0.0;
    final alphaA = math.exp(-s.dt / s.branchA.tau);
    final alphaB = math.exp(-s.dt / s.branchB.tau);
    final alphaFilter = math.exp(-s.dt / s.pvFilterSeconds);
    final n = (s.duration / s.dt).ceil();
    for (var k = 0; k <= n; k++) {
      final t = k * s.dt;
      final fault = t < s.faultAt ? 0.0 :
          s.faultAmplitude * math.sin(2 * math.pi * (t - s.faultAt) / s.faultPeriod);
      final mvA = s.initialMvA + fault;
      final total = a + b;
      filteredPv = alphaFilter * filteredPv + (1 - alphaFilter) * total;
      // Feedforward is a measured branch-flow compensation in MV units.
      // The PI output tracks the baseline; FF is applied downstream and
      // actuator constraints are applied to the *combined* command.
      final deltaA = a - s.initialFlowA;
      final ff = s.strategy == CompensationStrategy.measuredFeedforward
          ? -s.feedforwardFraction * deltaA / s.branchB.gain : 0.0;
      final pvForPi = s.strategy == CompensationStrategy.filteredPv
          ? filteredPv : total;
      final snap = pid.step(sp: s.setpoint, pv: pvForPi,
          mode: ControllerMode.auto);
      // FF is limited together with PI output. The internal PID does not
      // track the post-FF actuator, so anti-windup is only approximate.
      final requestedB = snap.mv + ff;
      final boundedB = requestedB.clamp(s.controllerB.mvMin,
          s.controllerB.mvMax).toDouble();
      final maxDelta = s.controllerB.maxMvRate * s.dt;
      final mvB = (previousMvB + (boundedB - previousMvB)
          .clamp(-maxDelta, maxDelta)).toDouble();
      final err = s.setpoint - total;
      if (![a, b, total, mvB].every((v) => v.isFinite)) {
        throw StateError('Non-finite dual-valve simulation');
      }
      if (k > 0) {
        iae += err.abs() * s.dt;
        final d = (mvB - previousMvB).abs();
        travel += d;
        maxRate = math.max(maxRate, d / s.dt);
      }
      maxError = math.max(maxError, err.abs());
      points.add(DualValvePoint(t, s.setpoint, a, b, total, mvA, mvB,
          filteredPv, ff));
      previousMvB = mvB;
      historyA.add(mvA); historyB.add(mvB);
      if (k == n) break;
      final delayedA = _delayed(historyA, k - s.branchA.delay / s.dt,
          s.initialMvA);
      final delayedB = _delayed(historyB, k - s.branchB.delay / s.dt,
          s.initialMvB);
      a = alphaA * a + (1 - alphaA) * (s.initialFlowA +
          s.branchA.gain * (delayedA - s.initialMvA));
      b = alphaB * b + (1 - alphaB) * (s.initialFlowB +
          s.branchB.gain * (delayedB - s.initialMvB));
    }
    return DualValveRun(s.strategy, List.unmodifiable(points),
        DualValveMetrics(iae, maxError, travel, maxRate));
  }

  static double _delayed(List<double> history, double index, double initial) {
    if (index < 0) return initial;
    final lo = index.floor();
    final hi = math.min(lo + 1, history.length - 1);
    final f = index - lo;
    return history[lo] * (1 - f) + history[hi] * f;
  }
}

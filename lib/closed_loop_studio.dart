import 'dart:math' as math;
import 'auto_tune.dart';
import 'centum_pid_simulator.dart';

/// Offline closed-loop FOPDT experiment. No DCS communications.
class LoopScenario {
  final double duration, dt, initialPv, initialMv, initialSp;
  final double disturbanceAt, disturbanceMagnitude;
  final double spChangeAt, spChange;
  final double manualUntil, manualMv;
  const LoopScenario({
    this.duration = 240, this.dt = 0.2,
    this.initialPv = 50, this.initialMv = 50, this.initialSp = 50,
    this.disturbanceAt = 40, this.disturbanceMagnitude = 6,
    this.spChangeAt = double.infinity, this.spChange = 0,
    this.manualUntil = 0, this.manualMv = 50,
  });
  void validate() {
    final finite = [duration, dt, initialPv, initialMv, initialSp,
      disturbanceAt, disturbanceMagnitude, spChange, manualUntil, manualMv];
    if (finite.any((v) => !v.isFinite) || duration <= 0 || dt <= 0 ||
        disturbanceAt < 0 || manualUntil < 0 || manualUntil > duration ||
        spChangeAt.isNaN || spChangeAt < 0 || spChangeAt == double.negativeInfinity) {
      throw ArgumentError('Invalid loop scenario');
    }
  }
}

class LoopPoint {
  final double t, sp, pv, mv, disturbance;
  final ControllerMode mode;
  final bool saturated, rateLimited;
  const LoopPoint(this.t, this.sp, this.pv, this.mv, this.disturbance,
      this.mode, this.saturated, this.rateLimited);
}

class LoopMetrics {
  final double iae, ise, maxAbsError, totalMvTravel, maxObservedMvRate;
  final double saturationSeconds, rateLimitSeconds, finalError;
  const LoopMetrics(this.iae, this.ise, this.maxAbsError,
      this.totalMvTravel, this.maxObservedMvRate, this.saturationSeconds,
      this.rateLimitSeconds, this.finalError);
}

class LoopRun {
  final Plant plant;
  final CentumPidConfig controller;
  final List<LoopPoint> points;
  final LoopMetrics metrics;
  const LoopRun(this.plant, this.controller, this.points, this.metrics);
}

class ClosedLoopStudio {
  /// The disturbance is additive at the measured process output.
  /// Delay uses linearly interpolated past actuator values.
  static LoopRun simulate(Plant plant, CentumPidConfig config,
      [LoopScenario scenario = const LoopScenario()]) {
    plant.validate();
    config.validate();
    scenario.validate();
    if ((config.dt - scenario.dt).abs() > 1e-10) {
      throw ArgumentError('Controller and scenario sample times must match');
    }
    if (scenario.dt > plant.tau / 2) {
      throw ArgumentError('Time step too large relative to plant tau');
    }
    if (scenario.initialMv < config.mvMin || scenario.initialMv > config.mvMax ||
        scenario.manualMv < config.mvMin || scenario.manualMv > config.mvMax) {
      throw ArgumentError('Initial/manual MV outside actuator limits');
    }
    final pid = CentumPidSimulator(config, initialMv: scenario.initialMv);
    final count = (scenario.duration / scenario.dt).ceil();
    final history = <double>[];
    final points = <LoopPoint>[];
    final a = math.exp(-scenario.dt / plant.tau);
    var processState = scenario.initialPv;
    var pv = scenario.initialPv;
    var lastMv = scenario.initialMv;
    var iae = 0.0, ise = 0.0, maxError = 0.0, travel = 0.0;
    var maxRate = 0.0, saturated = 0.0, rateLimited = 0.0;
    for (var k = 0; k <= count; k++) {
      final t = k * scenario.dt;
      final sp = scenario.initialSp + (t >= scenario.spChangeAt ? scenario.spChange : 0);
      final disturbance = t >= scenario.disturbanceAt ? scenario.disturbanceMagnitude : 0.0;
      pv = processState + disturbance;
      final mode = t < scenario.manualUntil ? ControllerMode.manual : ControllerMode.auto;
      final snap = pid.step(sp: sp, pv: pv, mode: mode,
          manualMv: mode == ControllerMode.manual ? scenario.manualMv : null);
      final error = sp - pv;
      if (![pv, snap.mv, error].every((x) => x.isFinite)) {
        throw StateError('Numerically unstable loop simulation');
      }
      if (k > 0) {
        iae += error.abs() * scenario.dt;
        ise += error * error * scenario.dt;
        final delta = (snap.mv - lastMv).abs();
        travel += delta;
        maxRate = math.max(maxRate, delta / scenario.dt);
        if (snap.saturated) saturated += scenario.dt;
        if (snap.rateLimited) rateLimited += scenario.dt;
      }
      maxError = math.max(maxError, error.abs());
      points.add(LoopPoint(t, sp, pv, snap.mv, disturbance,
          mode, snap.saturated, snap.rateLimited));
      lastMv = snap.mv;
      history.add(snap.mv);
      if (k == count) break;
      // At time t, plant receives MV(t-delay). Prehistory is initial MV.
      final delayedIndex = k - plant.delay / scenario.dt;
      double delayedMv;
      if (delayedIndex < 0) {
        delayedMv = scenario.initialMv;
      } else {
        final lo = delayedIndex.floor();
        final hi = math.min(lo + 1, history.length - 1);
        final f = delayedIndex - lo;
        delayedMv = history[lo] * (1 - f) + history[hi] * f;
      }
      final target = scenario.initialPv +
          plant.gain * (delayedMv - scenario.initialMv);
      processState = a * processState + (1 - a) * target;
    }
    return LoopRun(plant, config, List.unmodifiable(points), LoopMetrics(
        iae, ise, maxError, travel, maxRate, saturated, rateLimited,
        points.last.sp - points.last.pv));
  }

  static List<LoopRun> compareStructures(Plant plant, CentumPidConfig config,
      [LoopScenario scenario = const LoopScenario()]) =>
      PidStructure.values.map((structure) => simulate(plant,
        CentumPidConfig(pb: config.pb, ti: config.ti, td: config.td,
          dt: config.dt, mvMin: config.mvMin, mvMax: config.mvMax,
          maxMvRate: config.maxMvRate,
          derivativeFilterSeconds: config.derivativeFilterSeconds,
          structure: structure, action: config.action), scenario)).toList();
}

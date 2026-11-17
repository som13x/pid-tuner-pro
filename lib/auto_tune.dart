import 'dart:math' as math;

/// Offline PI optimizer. All PV/MV values are in normalized percent of span.
/// A positive process gain requires reverse action: e = SP - PV.
class Plant {
  final double gain, tau, delay;
  const Plant({required this.gain, required this.tau, required this.delay});
  void validate() {
    if (!gain.isFinite || gain == 0 || !tau.isFinite || tau <= 0 ||
        !delay.isFinite || delay < 0) {
      throw ArgumentError('Invalid FOPDT plant');
    }
  }
}

class TuneConfig {
  final double pbMin, pbMax, tiMin, tiMax;
  final double maxMvRate, maxAbsPvError;
  final double disturbance, disturbanceAt, duration, dt;
  final double pv0, sp, mv0, mvMin, mvMax;
  final double baselinePb, baselineTi;
  final double minRecoveryWindow, recoveryBand;
  final int coarseSteps, refinementSteps;
  const TuneConfig({
    this.pbMin = 40, this.pbMax = 250,
    this.tiMin = 5, this.tiMax = 80,
    this.maxMvRate = 5, this.maxAbsPvError = 10,
    this.disturbance = 6, this.disturbanceAt = 30,
    this.duration = 300, this.dt = 0.2,
    this.pv0 = 50, this.sp = 50, this.mv0 = 50,
    this.mvMin = 0, this.mvMax = 100,
    this.baselinePb = 120, this.baselineTi = 20,
    this.minRecoveryWindow = 15, this.recoveryBand = 1,
    this.coarseSteps = 11, this.refinementSteps = 7,
  });
  void validate() {
    final values = [pbMin,pbMax,tiMin,tiMax,maxMvRate,maxAbsPvError,
      disturbance,disturbanceAt,duration,dt,pv0,sp,mv0,mvMin,mvMax,
      baselinePb,baselineTi,minRecoveryWindow,recoveryBand];
    if (values.any((x) => !x.isFinite) || pbMin <= 0 || pbMax < pbMin ||
        tiMin <= 0 || tiMax < tiMin || maxMvRate <= 0 ||
        maxAbsPvError <= 0 || duration <= 0 || dt <= 0 ||
        disturbanceAt < 0 || disturbanceAt >= duration ||
        mvMin >= mvMax || mv0 < mvMin || mv0 > mvMax ||
        baselinePb <= 0 || baselineTi <= 0 || minRecoveryWindow <= 0 ||
        recoveryBand <= 0 || coarseSteps < 2 || refinementSteps < 2) {
      throw ArgumentError('Invalid optimization configuration');
    }
  }
}

class Sample {
  final double time, pv, mv, sp;
  const Sample(this.time, this.pv, this.mv, this.sp);
}

class Metrics {
  final double iae, ise, totalVariation, maxError, maxMvRate;
  final double saturationSeconds, recoverySeconds, terminalError;
  final bool recovered, numericallyStable;
  const Metrics({required this.iae, required this.ise,
    required this.totalVariation, required this.maxError,
    required this.maxMvRate, required this.saturationSeconds,
    required this.recoverySeconds, required this.terminalError,
    required this.recovered, required this.numericallyStable});
}

class Candidate {
  final double pb, ti;
  final Metrics metrics;
  final bool feasible;
  final List<String> violations;
  final List<Sample> samples;
  const Candidate(this.pb, this.ti, this.metrics, this.feasible,
      this.violations, this.samples);
}

class TuneResult {
  final Candidate baseline;
  final List<Candidate> best;
  final int evaluated, feasibleCount;
  const TuneResult(this.baseline, this.best, this.evaluated, this.feasibleCount);
}

class AutoTune {
  final Plant plant;
  final TuneConfig config;
  AutoTune(this.plant, [this.config = const TuneConfig()]) {
    plant.validate();
    config.validate();
    if (config.dt > plant.tau / 2) {
      throw ArgumentError('Choose a smaller simulation time step');
    }
  }

  /// Simulates PI with proportional-on-error, actuator slew and saturation,
  /// conditional integration anti-windup, and exact first-order lag update.
  /// The disturbance is an additive step at the PV/process output.
  Candidate evaluate(double pb, double ti, {bool keepSamples = false}) {
    if (!pb.isFinite || !ti.isFinite || pb <= 0 || ti <= 0) {
      throw ArgumentError('PB and Ti must be positive and finite');
    }
    final c = config;
    final kp = 100 / pb;
    final action = plant.gain > 0 ? 1.0 : -1.0;
    final n = (c.duration / c.dt).ceil();
    final history = List<double>.filled(n + 2, c.mv0);
    final delaySteps = plant.delay / c.dt;
    final a = math.exp(-c.dt / plant.tau);
    var pv = c.pv0, mv = c.mv0, integral = 0.0;
    var iae = 0.0, ise = 0.0, tv = 0.0, maxErr = 0.0;
    var maxRate = 0.0, sat = 0.0, terminal = 0.0;
    var stable = true;
    var lastOutside = c.disturbanceAt;
    final samples = <Sample>[];

    for (var k = 0; k < n; k++) {
      final t = k * c.dt;
      final error = action * (c.sp - pv);
      final proportional = kp * error;
      final raw = c.mv0 + proportional + integral;
      final bounded = raw.clamp(c.mvMin, c.mvMax).toDouble();
      final allowed = c.maxMvRate * c.dt;
      final nextMv = (mv + (bounded - mv).clamp(-allowed, allowed))
          .clamp(c.mvMin, c.mvMax).toDouble();
      final delta = nextMv - mv;
      final rate = delta.abs() / c.dt;
      maxRate = math.max(maxRate, rate);
      tv += delta.abs();
      mv = nextMv;
      history[k] = mv;
      if (mv <= c.mvMin + 1e-9 || mv >= c.mvMax - 1e-9) sat += c.dt;

      // Conditional integration: don't wind up when command cannot follow
      // the desired direction, including slew-rate limitation.
      final di = kp / ti * error * c.dt;
      final constrained = (nextMv - raw).abs() > 1e-9;
      if (!constrained || di * (raw - nextMv) < 0) integral += di;

      // Delayed actuator signal, linearly interpolated in the MV history.
      final pos = k - delaySteps;
      double delayedMv;
      if (pos < 0) {
        delayedMv = c.mv0;
      } else {
        final low = pos.floor();
        final high = math.min(low + 1, k);
        final frac = pos - low;
        delayedMv = history[low] * (1 - frac) + history[high] * frac;
      }
      final disturbance = t >= c.disturbanceAt ? c.disturbance : 0.0;
      final target = c.pv0 + plant.gain * (delayedMv - c.mv0) + disturbance;
      pv = a * pv + (1 - a) * target;
      if (!pv.isFinite || !integral.isFinite || pv.abs() > 1e8) {
        stable = false;
        break;
      }
      if (t >= c.disturbanceAt) {
        final absError = (c.sp - pv).abs();
        iae += absError * c.dt;
        ise += absError * absError * c.dt;
        maxErr = math.max(maxErr, absError);
        terminal = absError;
        if (absError > c.recoveryBand) lastOutside = t + c.dt;
      }
      if (keepSamples) samples.add(Sample(t + c.dt, pv, mv, c.sp));
    }
    final recovery = math.max(0, lastOutside - c.disturbanceAt);
    final recovered = stable &&
        lastOutside <= c.duration - c.minRecoveryWindow &&
        terminal <= c.recoveryBand;
    final metrics = Metrics(iae: iae, ise: ise, totalVariation: tv,
      maxError: maxErr, maxMvRate: maxRate, saturationSeconds: sat,
      recoverySeconds: recovery, terminalError: terminal,
      recovered: recovered, numericallyStable: stable);
    final violations = <String>[];
    if (!stable) violations.add('Numerical divergence');
    if (maxErr > c.maxAbsPvError + 1e-9) violations.add('PV deviation limit');
    if (maxRate > c.maxMvRate + 1e-9) violations.add('MV slew limit');
    if (!recovered) violations.add('No recovery within horizon');
    return Candidate(pb, ti, metrics, violations.isEmpty, violations, samples);
  }

  /// Deterministic coarse grid + two local refinement rounds.
  /// Valve priority: least MV travel, with IAE as tie-breaker.
  TuneResult search({int top = 5}) {
    if (top < 1) throw ArgumentError('top must be positive');
    final c = config;
    final seen = <String, Candidate>{};
    void visit(double pb, double ti) {
      pb = pb.clamp(c.pbMin, c.pbMax).toDouble();
      ti = ti.clamp(c.tiMin, c.tiMax).toDouble();
      final key = '${pb.toStringAsFixed(7)}:${ti.toStringAsFixed(7)}';
      seen.putIfAbsent(key, () => evaluate(pb, ti));
    }
    for (var i = 0; i < c.coarseSteps; i++) {
      for (var j = 0; j < c.coarseSteps; j++) {
        visit(c.pbMin + (c.pbMax-c.pbMin)*i/(c.coarseSteps-1),
              c.tiMin + (c.tiMax-c.tiMin)*j/(c.coarseSteps-1));
      }
    }
    int compare(Candidate x, Candidate y) {
      final tv = x.metrics.totalVariation.compareTo(y.metrics.totalVariation);
      if (tv != 0) return tv;
      final iae = x.metrics.iae.compareTo(y.metrics.iae);
      if (iae != 0) return iae;
      final pb = x.pb.compareTo(y.pb);
      return pb != 0 ? pb : x.ti.compareTo(y.ti);
    }
    List<Candidate> feasible() => seen.values.where((x) => x.feasible).toList()..sort(compare);
    var dp = (c.pbMax-c.pbMin)/(c.coarseSteps-1);
    var di = (c.tiMax-c.tiMin)/(c.coarseSteps-1);
    for (var round = 0; round < 2; round++) {
      final seeds = feasible().take(5).toList();
      if (seeds.isEmpty) break;
      for (final seed in seeds) {
        for (var i = 0; i < c.refinementSteps; i++) {
          for (var j = 0; j < c.refinementSteps; j++) {
            visit(seed.pb + dp * (2*i/(c.refinementSteps-1)-1),
                  seed.ti + di * (2*j/(c.refinementSteps-1)-1));
          }
        }
      }
      dp /= 3;
      di /= 3;
    }
    final winners = feasible().take(top).map((x) =>
        evaluate(x.pb, x.ti, keepSamples: true)).toList();
    return TuneResult(evaluate(c.baselinePb, c.baselineTi,
        keepSamples: true), winners, seen.length, feasible().length);
  }
}

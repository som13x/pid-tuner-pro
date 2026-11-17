import 'dart:math' as math;

import 'step_identification.dart';

/// Integrating-plus-dead-time approximation:
/// G(s) = Ki * exp(-L*s) / s, with PV/MV normalised to 0..100%.
/// Ki units are (%PV/s)/(%MV), or 1/second.
class IntegratingPlant {
  final double gainPerSecond;
  final double delaySeconds;

  const IntegratingPlant({
    required this.gainPerSecond,
    required this.delaySeconds,
  });

  void validate() {
    if (!gainPerSecond.isFinite || gainPerSecond.abs() < 1e-12 ||
        !delaySeconds.isFinite || delaySeconds < 0) {
      throw ArgumentError('Invalid IPDT gain or dead time');
    }
  }
}

/// Direct measurements of the post-step ramp and (optionally nonzero)
/// pre-step PV slope, all in engineering units and seconds.
class IntegratingManualInput {
  final double mvBefore, mvAfter, pvAtT1, pvAtT2;
  final double t1Seconds, t2Seconds, delaySeconds;
  final double baselineSlopePerSecond;
  final double mvSpanLow, mvSpanHigh, pvSpanLow, pvSpanHigh;

  const IntegratingManualInput({
    required this.mvBefore,
    required this.mvAfter,
    required this.pvAtT1,
    required this.pvAtT2,
    required this.t1Seconds,
    required this.t2Seconds,
    required this.delaySeconds,
    this.baselineSlopePerSecond = 0,
    required this.mvSpanLow,
    required this.mvSpanHigh,
    required this.pvSpanLow,
    required this.pvSpanHigh,
  });
}

class IntegratingManualEstimate {
  final IntegratingPlant plant;
  final IntegratingManualInput input;
  final double beforeSlopeNormalized;
  final double afterSlopeNormalized;
  final double deltaMvNormalized;

  const IntegratingManualEstimate({
    required this.plant,
    required this.input,
    required this.beforeSlopeNormalized,
    required this.afterSlopeNormalized,
    required this.deltaMvNormalized,
  });

  Map<String, Object?> get evidence => {
    'method': 'manualIntegratingRamp',
    'mvBefore': input.mvBefore,
    'mvAfter': input.mvAfter,
    'pvAtT1': input.pvAtT1,
    'pvAtT2': input.pvAtT2,
    't1Seconds': input.t1Seconds,
    't2Seconds': input.t2Seconds,
    'delaySeconds': input.delaySeconds,
    'baselineSlopePerSecond': input.baselineSlopePerSecond,
    'baselineSlopeNormalized': beforeSlopeNormalized,
    'afterSlopeNormalized': afterSlopeNormalized,
    'deltaMvNormalized': deltaMvNormalized,
    'mvSpanLow': input.mvSpanLow,
    'mvSpanHigh': input.mvSpanHigh,
    'pvSpanLow': input.pvSpanLow,
    'pvSpanHigh': input.pvSpanHigh,
    'qualityMetricsAvailable': false,
    'requiresEngineeringReview': true,
  };
}

class IntegratingManualEstimator {
  const IntegratingManualEstimator();

  IntegratingManualEstimate estimate(IntegratingManualInput x) {
    final vals = [
      x.mvBefore, x.mvAfter, x.pvAtT1, x.pvAtT2,
      x.t1Seconds, x.t2Seconds, x.delaySeconds,
      x.baselineSlopePerSecond,
      x.mvSpanLow, x.mvSpanHigh, x.pvSpanLow, x.pvSpanHigh,
    ];
    if (vals.any((v) => !v.isFinite) ||
        x.mvSpanHigh <= x.mvSpanLow ||
        x.pvSpanHigh <= x.pvSpanLow ||
        x.mvBefore < x.mvSpanLow || x.mvBefore > x.mvSpanHigh ||
        x.mvAfter < x.mvSpanLow || x.mvAfter > x.mvSpanHigh ||
        x.pvAtT1 < x.pvSpanLow || x.pvAtT1 > x.pvSpanHigh ||
        x.pvAtT2 < x.pvSpanLow || x.pvAtT2 > x.pvSpanHigh ||
        x.delaySeconds < 0 || x.t1Seconds <= x.delaySeconds ||
        x.t2Seconds <= x.t1Seconds) {
      throw ArgumentError('Invalid IPDT step measurements or response times');
    }
    final deltaMvPct = 100 * (x.mvAfter - x.mvBefore) /
        (x.mvSpanHigh - x.mvSpanLow);
    if (deltaMvPct.abs() < 2) {
      throw ArgumentError('MV step must be at least 2% of its span');
    }
    final pvSpan = x.pvSpanHigh - x.pvSpanLow;
    final postSlopePct = 100 * (x.pvAtT2 - x.pvAtT1) /
        (pvSpan * (x.t2Seconds - x.t1Seconds));
    final baseSlopePct = 100 * x.baselineSlopePerSecond / pvSpan;
    final changeSlopePct = postSlopePct - baseSlopePct;
    if (changeSlopePct.abs() < 1e-10) {
      throw ArgumentError('PV ramp slope change is too small');
    }
    final plant = IntegratingPlant(
      gainPerSecond: changeSlopePct / deltaMvPct,
      delaySeconds: x.delaySeconds,
    );
    plant.validate();
    return IntegratingManualEstimate(
      plant: plant, input: x,
      beforeSlopeNormalized: baseSlopePct,
      afterSlopeNormalized: postSlopePct,
      deltaMvNormalized: deltaMvPct,
    );
  }
}

/// Measured CSV fit of a delayed ramp on top of the measured pre-step drift.
/// Uses explicit evidence, never a fabricated FOPDT steady-state gain.
class IntegratingIdentificationResult {
  final IntegratingPlant plant;
  final double stepAtSeconds, mvBefore, mvAfter;
  final double baselineSlopePctPerSecond, baselinePvAtStep;
  final double rSquared, normalizedRmse;
  final int fittedPoints;
  final List<TrendPoint> fittedCurve;

  const IntegratingIdentificationResult({
    required this.plant,
    required this.stepAtSeconds,
    required this.mvBefore,
    required this.mvAfter,
    required this.baselineSlopePctPerSecond,
    required this.baselinePvAtStep,
    required this.rSquared,
    required this.normalizedRmse,
    required this.fittedPoints,
    required this.fittedCurve,
  });

  bool get suitableForTuning =>
      fittedPoints >= 20 && rSquared >= 0.90 && normalizedRmse <= 0.10;
}

class IntegratingStepIdentifier {
  const IntegratingStepIdentifier();

  IntegratingIdentificationResult identify(List<TrendPoint> points,
      {double? manualStepAt}) {
    if (points.length < 40) {
      throw ArgumentError('At least 40 evenly sampled points required');
    }
    for (var i = 0; i < points.length; i++) {
      final p = points[i];
      if (![p.seconds, p.mv, p.pv].every((v) => v.isFinite) ||
          (i > 0 && p.seconds <= points[i - 1].seconds)) {
        throw ArgumentError('Invalid or unordered CSV');
      }
    }
    final dt = (points.last.seconds - points.first.seconds) /
        (points.length - 1);
    if (dt <= 0 ||
        List.generate(points.length - 1, (i) =>
          (points[i + 1].seconds - points[i].seconds - dt).abs())
        .any((d) => d > dt * .10)) {
      throw ArgumentError('Trend must have a uniform timebase');
    }
    final nPre = math.max(8, (5 / dt).ceil());
    if (nPre > points.length ~/ 3) {
      throw ArgumentError('Not enough pre-step samples');
    }
    final mv0 = points.take(nPre).map((p) => p.mv).reduce((a,b)=>a+b) / nPre;
    final threshold = 2.0;
    int? index;
    for (var i = nPre; i < points.length - 20; i++) {
      if ((points[i].mv - mv0).abs() >= threshold) {
        index = i;
        break;
      }
    }
    if (index == null) throw ArgumentError('No isolated MV step');
    final step = points[index].seconds;
    if (manualStepAt != null &&
        (!manualStepAt.isFinite || (manualStepAt - step).abs() > dt)) {
      throw ArgumentError('Manual step time does not match the trend');
    }
    final post = points.sublist(index);
    final mv1 = post.take(5).map((p) => p.mv).reduce((a,b)=>a+b) / 5;
    final dmv = mv1 - mv0;
    if (dmv.abs() < threshold ||
        post.any((p) => (p.mv - mv1).abs() >
          math.max(0.5, dmv.abs() * 0.08))) {
      throw ArgumentError('Step must be sustained without MV drift');
    }
    if (post.length < 25) throw ArgumentError('Insufficient ramp observations');

    // Regression on pre-step PV estimates initial drift, not just a mean.
    final pre = points.sublist(0, index);
    final tMid = pre.map((p) => p.seconds).reduce((a,b)=>a+b) / pre.length;
    final yMid = pre.map((p) => p.pv).reduce((a,b)=>a+b) / pre.length;
    var xx = 0.0, xy = 0.0;
    for (final p in pre) {
      xx += math.pow(p.seconds - tMid, 2).toDouble();
      xy += (p.seconds - tMid) * (p.pv - yMid);
    }
    if (xx < 1e-12) throw ArgumentError('Pre-step time range too short');
    final baselineSlope = xy / xx;
    final baselineAtStep = yMid + baselineSlope * (step - tMid);
    final horizon = post.last.seconds - step;
    final maxDelay = math.min(horizon * .4, (post.length - 20) * dt);
    final candidateCount = math.min(80, math.max(2, (maxDelay / dt).floor()));
    var bestSse = double.infinity, bestKi = 0.0, bestL = 0.0;
    for (var j = 0; j <= candidateCount; j++) {
      final l = maxDelay * j / candidateCount;
      var num = 0.0, den = 0.0;
      for (final p in post) {
        final x = dmv * math.max(0.0, p.seconds - step - l);
        final base = baselineAtStep +
          baselineSlope * (p.seconds - step);
        num += x * (p.pv - base);
        den += x * x;
      }
      if (den < 1e-12) continue;
      final ki = num / den;
      var sse = 0.0;
      for (final p in post) {
        final prediction = baselineAtStep +
            baselineSlope * (p.seconds - step) +
            ki * dmv * math.max(0.0, p.seconds - step - l);
        sse += math.pow(p.pv - prediction, 2).toDouble();
      }
      if (sse < bestSse) {
        bestSse = sse;
        bestKi = ki;
        bestL = l;
      }
    }
    // A self-regulating step response that has flattened out must NOT
    // be interpreted as an integrating ramp just because a line fits
    // part of the trend. Compare drift-compensated late-time slopes.
    double responseSlope(int first, int last) {
      final p0 = post[first], p1 = post[last];
      return (p1.pv - p0.pv) / (p1.seconds - p0.seconds) -
        baselineSlope;
    }
    final middleSlope = responseSlope(
      post.length ~/ 2, post.length * 3 ~/ 4);
    final finalSlope = responseSlope(
      post.length * 3 ~/ 4, post.length - 1);
    if (middleSlope.abs() > 1e-4 &&
        finalSlope.abs() < middleSlope.abs() * .25) {
      throw ArgumentError('PV response levels off; model may be FOPDT '
        'rather than an integrating IPDT process');
    }
    final plant = IntegratingPlant(
      gainPerSecond: bestKi,
      delaySeconds: bestL,
    );
    plant.validate();

    // Calculate fit quality on the compensated response, so a large
    // pre-existing PV ramp cannot hide a missing MV response.
    final compensated = post.map((p) => p.pv -
      baselineAtStep - baselineSlope * (p.seconds - step)).toList();
    final mean = compensated.reduce((a,b)=>a+b) / compensated.length;
    var sst = 0.0;
    for (final v in compensated) {
      sst += math.pow(v - mean, 2).toDouble();
    }
    if (sst < 1e-6) throw ArgumentError('PV slope change is too small');
    final r2 = 1 - bestSse / sst;
    final span = compensated.reduce(math.max) - compensated.reduce(math.min);
    final nrmse = math.sqrt(bestSse / post.length) /
      math.max(span.abs(), 1e-9);
    if (!r2.isFinite || !nrmse.isFinite) {
      throw ArgumentError('Unable to evaluate integrating fit quality');
    }
    final fitted = points.map((p) => TrendPoint(
      p.seconds, p.mv,
      baselineAtStep + baselineSlope * (p.seconds - step) +
        bestKi * dmv * math.max(0.0, p.seconds - step - bestL),
    )).toList(growable: false);
    return IntegratingIdentificationResult(
      plant: plant, stepAtSeconds: step, mvBefore: mv0, mvAfter: mv1,
      baselineSlopePctPerSecond: baselineSlope,
      baselinePvAtStep: baselineAtStep,
      rSquared: r2, normalizedRmse: nrmse,
      fittedPoints: post.length, fittedCurve: fitted,
    );
  }
}

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

/// OptiControls manual integration rate from four PV values and TWO intervals.
///
/// T1 is the elapsed time in MINUTES from PV1 to PV2 (Slope 1).
/// T2 is the elapsed time in MINUTES from PV3 to PV4 (Slope 2).
/// td (L) is also entered in MINUTES, not absolute timestamps.
///
/// Slope 1 = (PV2-PV1)/T1; Slope 2 = (PV4-PV3)/T2, in PV EU/min.
/// ri = [100 * (Slope 2-Slope 1) / PV span] / [% MV step], in 1/min.
///
/// IPDT core and DCS profiles use seconds, so the result is converted
/// ONCE: Ki (1/sec) = ri (1/min)/60 and L (sec) = td (min)*60.
class IntegratingManualInput {
  final double mvBefore, mvAfter;
  final double pv1, pv2, pv3, pv4;
  final double t1Minutes, t2Minutes, delayMinutes;
  final double mvSpanLow, mvSpanHigh, pvSpanLow, pvSpanHigh;

  const IntegratingManualInput({
    required this.mvBefore,
    required this.mvAfter,
    required this.pv1,
    required this.pv2,
    required this.pv3,
    required this.pv4,
    required this.t1Minutes,
    required this.t2Minutes,
    required this.delayMinutes,
    required this.mvSpanLow,
    required this.mvSpanHigh,
    required this.pvSpanLow,
    required this.pvSpanHigh,
  });
}

class IntegratingManualEstimate {
  final IntegratingPlant plant;
  final IntegratingManualInput input;
  /// Normalised %PV per second. Kept for other calculation consumers.
  final double beforeSlopeNormalized;
  final double afterSlopeNormalized;
  final double deltaSlopeNormalized;
  final double deltaMvNormalized;

  const IntegratingManualEstimate({
    required this.plant,
    required this.input,
    required this.beforeSlopeNormalized,
    required this.afterSlopeNormalized,
    required this.deltaSlopeNormalized,
    required this.deltaMvNormalized,
  });

  double get t1IntervalMinutes => input.t1Minutes;
  double get t2IntervalMinutes => input.t2Minutes;
  double get deadTimeMinutes => input.delayMinutes;
  double get beforeSlopePercentPerMinute => beforeSlopeNormalized * 60;
  double get afterSlopePercentPerMinute => afterSlopeNormalized * 60;
  double get deltaSlopePercentPerMinute => deltaSlopeNormalized * 60;
  double get integrationRatePerMinute => plant.gainPerSecond * 60;

  /// New, unit-labelled evidence; old timestamp-based records remain intact.
  Map<String, Object?> get evidence => {
    'method': 'opticontrolsManualMinuteIntervals',
    'formula': 'DS=(PV4-PV3)/T2-(PV2-PV1)/T1',
    'timeUnit': 'minute',
    'timeInputKind': 'elapsedInterval',
    'mvBefore': input.mvBefore,
    'mvAfter': input.mvAfter,
    'pv1': input.pv1,
    'pv2': input.pv2,
    'pv3': input.pv3,
    'pv4': input.pv4,
    'T1Minutes': input.t1Minutes,
    'T2Minutes': input.t2Minutes,
    'deadTimeMinutes': input.delayMinutes,
    'T1Seconds': input.t1Minutes * 60,
    'T2Seconds': input.t2Minutes * 60,
    'delaySeconds': plant.delaySeconds,
    'baselineSlopePctPerMinute': beforeSlopePercentPerMinute,
    'afterSlopePctPerMinute': afterSlopePercentPerMinute,
    'deltaSlopePctPerMinute': deltaSlopePercentPerMinute,
    'integrationRatePerMinute': integrationRatePerMinute,
    'baselineSlopeNormalized': beforeSlopeNormalized,
    'afterSlopeNormalized': afterSlopeNormalized,
    'deltaSlopeNormalized': deltaSlopeNormalized,
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
    final values = [
      x.mvBefore, x.mvAfter,
      x.pv1, x.pv2, x.pv3, x.pv4,
      x.t1Minutes, x.t2Minutes, x.delayMinutes,
      x.mvSpanLow, x.mvSpanHigh, x.pvSpanLow, x.pvSpanHigh,
    ];
    if (values.any((v) => !v.isFinite)) {
      throw ArgumentError('Все измерения и интервалы должны быть числами');
    }
    if (x.mvSpanHigh <= x.mvSpanLow || x.pvSpanHigh <= x.pvSpanLow) {
      throw ArgumentError('Верхняя граница шкалы должна быть больше нижней');
    }
    if (x.mvBefore < x.mvSpanLow || x.mvBefore > x.mvSpanHigh ||
        x.mvAfter < x.mvSpanLow || x.mvAfter > x.mvSpanHigh ||
        [x.pv1, x.pv2, x.pv3, x.pv4].any(
          (pv) => pv < x.pvSpanLow || pv > x.pvSpanHigh)) {
      throw ArgumentError('PV или MV выходит за указанную шкалу');
    }
    if (x.t1Minutes <= 0 || x.t2Minutes <= 0 || x.delayMinutes < 0) {
      throw ArgumentError('T1 и T2 должны быть > 0 минут, '
        'а запаздывание td не может быть отрицательным');
    }
    final deltaMvPercent = 100 * (x.mvAfter - x.mvBefore) /
        (x.mvSpanHigh - x.mvSpanLow);
    if (deltaMvPercent.abs() < 2) {
      throw ArgumentError('Ступень MV должна быть не меньше 2% шкалы');
    }
    final beforeSlopeEuPerMin = (x.pv2 - x.pv1) / x.t1Minutes;
    final afterSlopeEuPerMin = (x.pv4 - x.pv3) / x.t2Minutes;
    final pvSpan = x.pvSpanHigh - x.pvSpanLow;
    final beforeSlopePerMin = 100 * beforeSlopeEuPerMin / pvSpan;
    final afterSlopePerMin = 100 * afterSlopeEuPerMin / pvSpan;
    final dsPerMin = afterSlopePerMin - beforeSlopePerMin;
    if (dsPerMin.abs() < 1e-10) {
      throw ArgumentError('Изменение наклона PV слишком мало');
    }
    // Convert only at the boundary to the second-based IPDT model.
    final plant = IntegratingPlant(
      gainPerSecond: dsPerMin / deltaMvPercent / 60,
      delaySeconds: x.delayMinutes * 60,
    );
    plant.validate();
    return IntegratingManualEstimate(
      plant: plant, input: x,
      beforeSlopeNormalized: beforeSlopePerMin / 60,
      afterSlopeNormalized: afterSlopePerMin / 60,
      deltaSlopeNormalized: dsPerMin / 60,
      deltaMvNormalized: deltaMvPercent,
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

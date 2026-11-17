import 'dart:math' as math;

import 'package:test/test.dart';
import 'package:pid_tuner_pro_core/manual_step_identification.dart';

ManualStepInput example({
  ManualStepMethod method = ManualStepMethod.knownDelayAndT63,
  double? t28,
  double? delay = 3,
  double t63 = 18,
  double mvAfter = 50,
  double pvAfter = 950,
}) => ManualStepInput(
  mvBefore: 40, mvAfter: mvAfter,
  pvBefore: 800, pvAfter: pvAfter,
  mvSpanLow: 0, mvSpanHigh: 100,
  pvSpanLow: 0, pvSpanHigh: 1000,
  method: method, delaySeconds: delay,
  t28Seconds: t28, t63Seconds: t63,
);

void main() {
  test('one-point 63.2% estimate normalizes engineering units', () {
    final estimate = const ManualStepEstimator().estimate(example());
    expect(estimate.plant.gain, closeTo(1.5, 1e-12));
    expect(estimate.plant.tau, 15);
    expect(estimate.plant.delay, 3);
    expect(estimate.gainEngineering, 15);
    expect(estimate.normalizedMvChange, 10);
    expect(estimate.normalizedPvChange, 15);
    expect(estimate.evidence['qualityMetricsAvailable'], false);
    expect(estimate.evidence['measuredTrendAvailable'], false);
  });

  test('two response points infer both lag and dead time', () {
    final estimate = const ManualStepEstimator().estimate(example(
      method: ManualStepMethod.twoResponseTimes,
      delay: null, t28: 8));
    expect(estimate.plant.gain, closeTo(1.5, 1e-12));
    expect(estimate.plant.tau, closeTo(15, 1e-12));
    expect(estimate.plant.delay, closeTo(3, 1e-12));
    expect(estimate.evidence['t28Seconds'], 8);
  });

  test('negative process gain is supported without sign loss', () {
    final estimate = const ManualStepEstimator().estimate(example(
      pvAfter: 650));
    expect(estimate.plant.gain, closeTo(-1.5, 1e-12));
    expect(estimate.gainEngineering, -15);
    final reverseMv = const ManualStepEstimator().estimate(example(
      mvAfter: 30));
    expect(reverseMv.plant.gain, closeTo(-1.5, 1e-12));
    expect(reverseMv.normalizedMvChange, -10);
  });

  test('non-zero span lows preserve normalized gain', () {
    const input = ManualStepInput(
      mvBefore: 50, mvAfter: 60, pvBefore: 900, pvAfter: 1050,
      mvSpanLow: 20, mvSpanHigh: 120,
      pvSpanLow: 100, pvSpanHigh: 1100,
      t63Seconds: 18, delaySeconds: 3);
    final e = const ManualStepEstimator().estimate(input);
    expect(e.plant.gain, closeTo(1.5, 1e-12));
  });

  test('synthetic curve is explicitly model-generated, not samples', () {
    final estimate = const ManualStepEstimator().estimate(example());
    final curve = estimate.syntheticCurve(samples: 300);
    expect(curve.first.seconds, 0);
    expect(curve.first.pv, 800);
    expect(curve.last.pv, closeTo(950, 3));
    final point = curve.reduce((a, b) =>
      (a.seconds - 18).abs() < (b.seconds - 18).abs() ? a : b);
    expect(point.pv, closeTo(800 + 150 * (1 - math.exp(-1)), 2));
    expect(() => estimate.syntheticCurve(samples: 1), throwsArgumentError);
  });

  test('reject zero MV/PV change, invalid engineering spans and values', () {
    for (final input in [
      example(mvAfter: 40), example(pvAfter: 800),
      const ManualStepInput(
        mvBefore: 40, mvAfter: 50, pvBefore: 800, pvAfter: 950,
        mvSpanLow: 100, mvSpanHigh: 0,
        pvSpanLow: 0, pvSpanHigh: 1000,
        t63Seconds: 18, delaySeconds: 3),
      example(mvAfter: 105),
      example(pvAfter: double.infinity),
      example(t63: double.nan),
    ]) {
      expect(() => const ManualStepEstimator().estimate(input),
        throwsArgumentError);
    }
  });

  test('one-point method rejects missing/noncausal dead time', () {
    for (final delay in [null, -1.0, 18.0, 19.0]) {
      expect(() => const ManualStepEstimator().estimate(example(delay: delay)),
        throwsArgumentError);
    }
  });

  test('two-point method rejects noncausal or reversed crossings', () {
    for (final t28 in [null, -1.0, 0.0, 18.0, 20.0, 4.0]) {
      expect(() => const ManualStepEstimator().estimate(example(
        method: ManualStepMethod.twoResponseTimes,
        delay: null, t28: t28)), throwsArgumentError);
    }
  });
}

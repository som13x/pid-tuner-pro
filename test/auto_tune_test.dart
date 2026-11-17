import 'package:test/test.dart';
import '../lib/auto_tune.dart';

void main() {
  const plant = Plant(gain: 0.8, tau: 12, delay: 3);
  test('rejects invalid plant and ranges', () {
    expect(() => AutoTune(const Plant(gain: 0, tau: 12, delay: 3)), throwsArgumentError);
    expect(() => AutoTune(plant, const TuneConfig(pbMin: 0)), throwsArgumentError);
    expect(() => AutoTune(plant, const TuneConfig(dt: 20)), throwsArgumentError);
  });
  test('zero disturbance at equilibrium keeps PV and MV fixed', () {
    final engine = AutoTune(plant, const TuneConfig(disturbance: 0));
    final c = engine.evaluate(120, 20, keepSamples: true);
    expect(c.metrics.maxError, closeTo(0, 1e-9));
    expect(c.metrics.totalVariation, closeTo(0, 1e-9));
    expect(c.samples.last.pv, closeTo(50, 1e-9));
  });
  test('saturation and slew limit are respected', () {
    final engine = AutoTune(plant, const TuneConfig(
      disturbance: 20, maxMvRate: 1, maxAbsPvError: 10));
    final c = engine.evaluate(40, 5, keepSamples: true);
    expect(c.metrics.maxMvRate, lessThanOrEqualTo(5.000001));
    for (final s in c.samples) {
      expect(s.mv, inInclusiveRange(0, 100));
    }
    expect(c.feasible, isFalse);
    expect(c.violations, contains('PV deviation limit'));
  });
  test('search returns only feasible candidates within bounds', () {
    final engine = AutoTune(plant);
    final r = engine.search();
    expect(r.evaluated, greaterThanOrEqualTo(121));
    expect(r.baseline.pb, 120);
    expect(r.baseline.ti, 20);
    for (final c in r.best) {
      expect(c.feasible, isTrue);
      expect(c.pb, inInclusiveRange(40, 250));
      expect(c.ti, inInclusiveRange(5, 80));
      expect(c.metrics.maxError, lessThanOrEqualTo(10.000001));
      expect(c.metrics.maxMvRate, lessThanOrEqualTo(5.000001));
    }
    for (var i = 1; i < r.best.length; i++) {
      expect(r.best[i].metrics.totalVariation,
          greaterThanOrEqualTo(r.best[i-1].metrics.totalVariation - 1e-9));
    }
  });
  test('no feasible candidates is represented by empty result', () {
    final engine = AutoTune(plant, const TuneConfig(
      disturbance: 20, maxAbsPvError: 0.1, coarseSteps: 3,
      refinementSteps: 3));
    final r = engine.search();
    expect(r.best, isEmpty);
    expect(r.feasibleCount, 0);
  });
  test('negative plant gain uses direct action', () {
    final engine = AutoTune(const Plant(gain: -0.8, tau: 12, delay: 3));
    final c = engine.evaluate(120, 20, keepSamples: true);
    expect(c.metrics.numericallyStable, isTrue);
    expect(c.samples.every((s) => s.mv >= 0 && s.mv <= 100), isTrue);
  });
}

import 'dart:math' as math;

import 'package:test/test.dart';
import 'package:pid_tuner_pro_core/auto_tune.dart';
import 'package:pid_tuner_pro_core/centum_pid_simulator.dart';
import 'package:pid_tuner_pro_core/external_tracking_lab.dart';

void main() {
  test('RL-like filter has exact lag and no startup transient', () {
    final lag = RlSignalLag(dt: 0.2, tauSeconds: 2);
    expect(lag.step(50), 50);
    final expected = 50 + 20 * (1 - math.exp(-0.2 / 2));
    expect(lag.step(70), closeTo(expected, 1e-10));
    final bypass = RlSignalLag(dt: 0.2, tauSeconds: 0);
    expect(bypass.step(50), 50);
    expect(bypass.step(70), 70);
  });

  test('RL-like filter rejects bad parameters and nonfinite samples', () {
    expect(() => RlSignalLag(dt: 0, tauSeconds: 2), throwsArgumentError);
    expect(() => RlSignalLag(dt: 0.2, tauSeconds: -1), throwsArgumentError);
    expect(() => RlSignalLag(dt: 0.2, tauSeconds: double.nan),
        throwsArgumentError);
    final lag = RlSignalLag(dt: 0.2, tauSeconds: 2);
    expect(() => lag.step(double.infinity), throwsArgumentError);
  });

  test('tracking feedback is explicit and cannot silently read an RL input', () {
    final enabled = CentumPidSimulator(const CentumPidConfig(
      pb: 120, ti: 20, dt: 0.2, externalTrackingTimeSeconds: 1));
    expect(() => enabled.step(sp: 50, pv: 50,
        mode: ControllerMode.auto), throwsArgumentError);
    expect(() => enabled.step(sp: 50, pv: 50, mode: ControllerMode.auto,
        externalTrackingMv: double.nan), throwsArgumentError);
    expect(() => enabled.step(sp: 50, pv: 50, mode: ControllerMode.auto,
        externalTrackingMv: 150), throwsArgumentError);
    final disabled = CentumPidSimulator(
      const CentumPidConfig(pb: 120, ti: 20, dt: 0.2));
    expect(() => disabled.step(sp: 50, pv: 50, mode: ControllerMode.auto,
        externalTrackingMv: 50), throwsArgumentError);
  });

  test('back calculation responds to slow external actuator MV on next scan', () {
    final baseline = CentumPidSimulator(const CentumPidConfig(
      pb: 100, ti: 10, dt: 0.2));
    final tracking = CentumPidSimulator(const CentumPidConfig(
      pb: 100, ti: 10, dt: 0.2, externalTrackingTimeSeconds: 1));
    final firstBaseline = baseline.step(
      sp: 50, pv: 50, mode: ControllerMode.auto);
    final firstTracking = tracking.step(
      sp: 50, pv: 50, mode: ControllerMode.auto, externalTrackingMv: 50);
    expect(firstTracking.mv, firstBaseline.mv);
    final secondBaseline = baseline.step(
      sp: 60, pv: 50, mode: ControllerMode.auto);
    final secondTracking = tracking.step(
      sp: 60, pv: 50, mode: ControllerMode.auto, externalTrackingMv: 50);
    // Correction is applied after the command, never retroactively.
    expect(secondTracking.mv, closeTo(secondBaseline.mv, 1e-10));
    final thirdBaseline = baseline.step(
      sp: 60, pv: 50, mode: ControllerMode.auto);
    final thirdTracking = tracking.step(
      sp: 60, pv: 50, mode: ControllerMode.auto, externalTrackingMv: 50);
    expect(thirdTracking.mv, lessThan(thirdBaseline.mv));
  });

  test('tracking time must be zero or at least one sample time', () {
    for (final t in [-1.0, 0.1, double.nan, double.infinity]) {
      expect(() => CentumPidSimulator(CentumPidConfig(
        pb: 120, ti: 20, dt: 0.2, externalTrackingTimeSeconds: t)),
        throwsArgumentError);
    }
    final model = CentumPidSimulator(const CentumPidConfig(
      pb: 120, ti: 20, dt: 0.2, externalTrackingTimeSeconds: 0));
    expect(model.step(sp: 50, pv: 50, mode: ControllerMode.auto).mv,
      closeTo(50, 1e-9));
  });

  test('lab produces independent RL filter and two tracking scenarios', () {
    const scenario = ExternalTrackingScenario(duration: 80);
    final runs = ExternalTrackingLab.compare(scenario);
    expect(runs, hasLength(2));
    expect(runs[0].externalTracking, false);
    expect(runs[1].externalTracking, true);
    expect(runs[0].points.length, runs[1].points.length);
    final aroundStep = runs[0].points.firstWhere((p) => p.seconds >= 45);
    expect(aroundStep.rawRlLike - aroundStep.filteredRlLike,
        greaterThan(2));
    for (var i = 0; i < runs[0].points.length; i++) {
      final a = runs[0].points[i], b = runs[1].points[i];
      expect(a.rawRlLike, closeTo(b.rawRlLike, 1e-10));
      expect(a.filteredRlLike, closeTo(b.filteredRlLike, 1e-10));
      expect(a.requestedMv.isFinite && b.actualMv.isFinite, true);
    }
    expect(runs[0].metrics.iae.isFinite, true);
    expect(runs[1].metrics.iae.isFinite, true);
  });

  test('negative process gain uses direct controller action', () {
    final run = ExternalTrackingLab.simulate(
      const ExternalTrackingScenario(
        plant: Plant(gain: -0.8, tau: 12, delay: 2),
        duration: 40, spStepAt: 15, rlStepAt: 20),
      externalTracking: false);
    final before = run.points.firstWhere((p) => p.seconds >= 10).requestedMv;
    final after = run.points.firstWhere((p) => p.seconds >= 16).requestedMv;
    expect(after, lessThan(before));
  });

  test('lab validates duration, lag, tracking time and sample resolution', () {
    for (final s in [
      const ExternalTrackingScenario(duration: -1),
      const ExternalTrackingScenario(rlLagSeconds: -1),
      const ExternalTrackingScenario(trackingTimeSeconds: 0.1),
      const ExternalTrackingScenario(dt: 10),
      const ExternalTrackingScenario(rlNoiseAmplitude: double.infinity),
      const ExternalTrackingScenario(initialMv: 150),
    ]) {
      expect(() => ExternalTrackingLab.compare(s), throwsArgumentError);
    }
  });
}

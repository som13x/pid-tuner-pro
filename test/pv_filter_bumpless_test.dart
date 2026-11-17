import 'dart:math' as math;

import 'package:test/test.dart';
import 'package:pid_tuner_pro_core/centum_pid_simulator.dart';
import 'package:pid_tuner_pro_core/closed_loop_studio.dart';
import 'package:pid_tuner_pro_core/auto_tune.dart';

void main() {
  test('zero PV time constant leaves measurement untouched', () {
    final pid = CentumPidSimulator(const CentumPidConfig(
      pb: 120, ti: 15, pvFilterSeconds: 0));
    pid.step(sp: 50, pv: 50, mode: ControllerMode.manual);
    final snap = pid.step(sp: 50, pv: 80, mode: ControllerMode.manual);
    expect(snap.filteredPv, 80);
    expect(snap.error, closeTo(-30, 1e-12));
  });

  test('first-order PV lag uses exact exponential update', () {
    const dt = 0.2, tau = 2.0;
    final pid = CentumPidSimulator(const CentumPidConfig(
      pb: 120, ti: 20, dt: dt, pvFilterSeconds: tau));
    final first = pid.step(sp: 50, pv: 50, mode: ControllerMode.manual);
    expect(first.filteredPv, 50); // no artificial startup transient
    final second = pid.step(sp: 50, pv: 70, mode: ControllerMode.manual);
    final expected = 50 + (1 - math.exp(-dt / tau)) * 20;
    expect(second.filteredPv, closeTo(expected, 1e-11));
    expect(second.filteredPv, inInclusiveRange(50, 70));
    final third = pid.step(sp: 50, pv: 70, mode: ControllerMode.manual);
    expect(third.filteredPv, greaterThan(second.filteredPv));
    expect(third.filteredPv, lessThan(70));
  });

  test('PV filter reduces alternating measurement noise seen by controller', () {
    final filtered = CentumPidSimulator(const CentumPidConfig(
      pb: 100, ti: 30, dt: 0.2, pvFilterSeconds: 3));
    final raw = CentumPidSimulator(const CentumPidConfig(
      pb: 100, ti: 30, dt: 0.2));
    filtered.step(sp: 50, pv: 50, mode: ControllerMode.manual);
    raw.step(sp: 50, pv: 50, mode: ControllerMode.manual);
    double filteredPeak = 0, rawPeak = 0;
    for (var i = 0; i < 40; i++) {
      final pv = i.isEven ? 55.0 : 45.0;
      final f = filtered.step(sp: 50, pv: pv, mode: ControllerMode.manual);
      final u = raw.step(sp: 50, pv: pv, mode: ControllerMode.manual);
      filteredPeak = math.max(filteredPeak, f.error.abs());
      rawPeak = math.max(rawPeak, u.error.abs());
    }
    expect(rawPeak, closeTo(5, 1e-12));
    expect(filteredPeak, lessThan(1));
  });

  test('MAN to AUTO output exactly matches manually tracked MV', () {
    for (final structure in PidStructure.values) {
      final pid = CentumPidSimulator(CentumPidConfig(
        pb: 80, ti: 3, td: 2, dt: 0.2, pvFilterSeconds: 2,
        structure: structure, maxMvRate: 0.5), initialMv: 30);
      pid.step(sp: 50, pv: 50, mode: ControllerMode.manual,
        manualMv: 63);
      pid.step(sp: 10, pv: 80, mode: ControllerMode.manual,
        manualMv: 63);
      final auto = pid.step(sp: 90, pv: 30,
        mode: ControllerMode.auto);
      expect(auto.mv, closeTo(63, 1e-8), reason: structure.name);
      expect(auto.mode, ControllerMode.auto);
      expect(auto.filteredPv.isFinite, true);
      // Subsequent scans are limited by configured MV rate.
      final next = pid.step(sp: 90, pv: 30, mode: ControllerMode.auto);
      expect((next.mv - auto.mv).abs(), lessThanOrEqualTo(0.1 + 1e-8));
    }
  });

  test('PV time constant must be finite and non-negative', () {
    for (final invalid in [-0.01, double.nan, double.infinity]) {
      expect(() => CentumPidSimulator(CentumPidConfig(
        pb: 120, ti: 20, pvFilterSeconds: invalid)),
        throwsArgumentError);
    }
  });

  test('closed-loop output exposes raw and filtered PV separately', () {
    final config = CentumPidConfig(
      pb: 120, ti: 20, dt: 0.2, pvFilterSeconds: 2,
      derivativeFilterSeconds: 1);
    final runs = ClosedLoopStudio.compareStructures(
      const Plant(gain: 0.8, tau: 12, delay: 2),
      config, const LoopScenario(
        duration: 10, dt: 0.2,
        disturbanceAt: 1, disturbanceMagnitude: 6));
    expect(runs, hasLength(3));
    for (final run in runs) {
      expect(run.controller.pvFilterSeconds, 2);
      final stepPoint = run.points.firstWhere((p) => p.t >= 1);
      expect(stepPoint.pv - stepPoint.filteredPv, greaterThan(4));
      expect(run.points.last.pv.isFinite, true);
    }
  });
}

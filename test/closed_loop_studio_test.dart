import 'package:test/test.dart';
import 'package:pid_tuner_pro_core/auto_tune.dart';
import 'package:pid_tuner_pro_core/centum_pid_simulator.dart';
import 'package:pid_tuner_pro_core/closed_loop_studio.dart';

void main() {
  const plant = Plant(gain: 1, tau: 12, delay: 2);
  const config = CentumPidConfig(pb: 120, ti: 20, dt: 0.2, maxMvRate: 5);
  test('closed-loop returns finite traces and metrics', () {
    final run = ClosedLoopStudio.simulate(plant, config);
    expect(run.points.length, 1201);
    expect(run.metrics.iae.isFinite, isTrue);
    expect(run.points.every((p) => p.pv.isFinite && p.mv.isFinite), isTrue);
  });
  test('three structures are comparable', () {
    final runs = ClosedLoopStudio.compareStructures(plant, config);
    expect(runs.length, 3);
    expect(runs.map((r) => r.controller.structure).toSet().length, 3);
  });
  test('disturbance produces a measurable PV deviation', () {
    const scenario = LoopScenario(duration: 80, dt: 0.2,
      disturbanceAt: 20, disturbanceMagnitude: 8);
    final run = ClosedLoopStudio.simulate(plant, config, scenario);
    expect(run.points.firstWhere((p) => p.t >= 20).pv, greaterThan(55));
  });
  test('manual to auto transition retains controller output at switch', () {
    const scenario = LoopScenario(duration: 30, dt: 0.2,
      manualUntil: 10, manualMv: 45, disturbanceAt: 20);
    final run = ClosedLoopStudio.simulate(plant, config, scenario);
    final atSwitch = run.points.firstWhere((p) => p.t >= 10);
    expect((atSwitch.mv - 45).abs(), lessThanOrEqualTo(1.01));
  });
  test('invalid sampling mismatch is rejected', () {
    expect(() => ClosedLoopStudio.simulate(plant, config,
      const LoopScenario(dt: 0.1)), throwsArgumentError);
  });
  test('actuator rate limit is respected in automatic operation', () {
    final run = ClosedLoopStudio.simulate(plant, config);
    expect(run.metrics.maxObservedMvRate, lessThanOrEqualTo(5.000001));
  });
}

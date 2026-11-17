import 'package:test/test.dart';
import 'package:pid_tuner_pro_core/auto_tune.dart';
import 'package:pid_tuner_pro_core/centum_pid_simulator.dart';
import 'package:pid_tuner_pro_core/closed_loop_studio.dart';

void main() {
  const plant = Plant(gain: 1, tau: 15, delay: 3);
  const config = CentumPidConfig(pb: 120, ti: 20, dt: 0.2);
  test('all three structures produce finite trajectories and metrics', () {
    final runs = ClosedLoopStudio.compareStructures(plant, config);
    expect(runs.length, 3);
    for (final run in runs) {
      expect(run.points.length, greaterThan(100));
      expect(run.metrics.iae.isFinite, isTrue);
      expect(run.metrics.totalMvTravel.isFinite, isTrue);
      expect(run.points.every((p) => p.pv.isFinite && p.mv.isFinite), isTrue);
    }
  });
  test('MAN/AUTO and rate limit are represented in time series', () {
    final run = ClosedLoopStudio.simulate(plant,
      const CentumPidConfig(pb: 120, ti: 20, dt: 0.2, maxMvRate: 1),
      const LoopScenario(duration: 60, manualUntil: 10, disturbanceAt: 15));
    expect(run.points.first.mode, ControllerMode.manual);
    expect(run.points.last.mode, ControllerMode.auto);
    expect(run.metrics.maxObservedMvRate, lessThanOrEqualTo(1.00001));
  });
  test('invalid sample time is rejected', () {
    expect(() => ClosedLoopStudio.simulate(plant,
      const CentumPidConfig(pb: 120, ti: 20, dt: 0.1)), throwsArgumentError);
  });
}

import 'package:test/test.dart';
import 'package:pid_tuner_pro_core/auto_tune.dart';
import 'package:pid_tuner_pro_core/centum_pid_simulator.dart';
import 'package:pid_tuner_pro_core/dual_valve_lng.dart';

void main() {
  const a = Plant(gain: 1, tau: 7, delay: 2);
  const b = Plant(gain: 1, tau: 10, delay: 2);
  const pid = CentumPidConfig(pb: 120, ti: 20, dt: 0.2, maxMvRate: 5);
  test('two branches sum to measured header flow', () {
    final r = DualValveLngSimulator.simulate(const DualValveScenario(
        branchA: a, branchB: b, controllerB: pid));
    expect(r.points.length, 1201);
    expect(r.points.every((p) =>
        (p.totalFlow - p.flowA - p.flowB).abs() < 1e-9), isTrue);
  });
  test('mechanical fault moves A while A remains externally imposed', () {
    final r = DualValveLngSimulator.simulate(const DualValveScenario(
        branchA: a, branchB: b, controllerB: pid));
    expect(r.points.first.mvA, 50);
    expect(r.points.any((p) => p.t > 40 && p.mvA != 50), isTrue);
  });
  test('B actuator rate limit is respected', () {
    final r = DualValveLngSimulator.simulate(const DualValveScenario(
        branchA: a, branchB: b, controllerB: pid,
        strategy: CompensationStrategy.measuredFeedforward));
    expect(r.metrics.maxMvBRate, lessThanOrEqualTo(5.000001));
  });
  test('feedforward produces a nonzero correction after disturbance', () {
    final r = DualValveLngSimulator.simulate(const DualValveScenario(
        branchA: a, branchB: b, controllerB: pid,
        strategy: CompensationStrategy.measuredFeedforward));
    expect(r.points.any((p) => p.t > 50 && p.ffMv.abs() > 0.01), isTrue);
  });
  test('no fault produces zero error and zero feedforward', () {
    final r = DualValveLngSimulator.simulate(const DualValveScenario(
        branchA: a, branchB: b, controllerB: pid, faultAmplitude: 0,
        strategy: CompensationStrategy.measuredFeedforward));
    expect(r.metrics.iae, lessThan(1e-7));
    expect(r.points.every((p) => p.ffMv == 0), isTrue);
  });
  test('invalid gains or sampling are rejected', () {
    expect(() => DualValveLngSimulator.simulate(const DualValveScenario(
        branchA: a, branchB: Plant(gain: -1, tau: 10, delay: 2),
        controllerB: pid)), throwsArgumentError);
    expect(() => DualValveLngSimulator.simulate(const DualValveScenario(
        branchA: a, branchB: b, controllerB: pid, dt: 0.1)), throwsArgumentError);
  });
}

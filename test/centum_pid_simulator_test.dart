import 'package:test/test.dart';
import 'package:pid_tuner_pro_core/centum_pid_simulator.dart';

void main() {
  test('manual to auto transfer is bumpless at steady PV', () {
    final sim = CentumPidSimulator(const CentumPidConfig(pb: 120, ti: 20), initialMv: 37);
    sim.step(sp: 50, pv: 50, mode: ControllerMode.manual, manualMv: 37);
    final result = sim.step(sp: 50, pv: 50, mode: ControllerMode.auto);
    expect(result.mv, closeTo(37, 1e-8));
  });

  test('reverse and direct action have opposite response', () {
    double response(ControllerAction action) {
      final sim = CentumPidSimulator(CentumPidConfig(pb: 100, ti: 20, action: action));
      sim.step(sp: 50, pv: 50, mode: ControllerMode.manual);
      return sim.step(sp: 55, pv: 50, mode: ControllerMode.auto).mv;
    }
    // First AUTO scan tracks MV; compare next scan after error persists.
    final reverse = CentumPidSimulator(const CentumPidConfig(pb: 100, ti: 20));
    final direct = CentumPidSimulator(const CentumPidConfig(pb: 100, ti: 20, action: ControllerAction.direct));
    for (final s in [reverse, direct]) {
      s.step(sp: 50, pv: 50, mode: ControllerMode.manual);
      s.step(sp: 50, pv: 50, mode: ControllerMode.auto);
    }
    expect(reverse.step(sp: 55, pv: 50, mode: ControllerMode.auto).mv, greaterThan(50));
    expect(direct.step(sp: 55, pv: 50, mode: ControllerMode.auto).mv, lessThan(50));
    expect(response(ControllerAction.reverse), isA<double>());
  });

  test('rate limiting and saturation', () {
    final sim = CentumPidSimulator(const CentumPidConfig(
      pb: 40, ti: 5, dt: 0.1, mvMin: 10, mvMax: 60, maxMvRate: 5));
    sim.step(sp: 50, pv: 50, mode: ControllerMode.manual, manualMv: 50);
    sim.step(sp: 50, pv: 50, mode: ControllerMode.auto);
    final s = sim.step(sp: 100, pv: 0, mode: ControllerMode.auto);
    expect(s.mv, closeTo(50.5, 1e-8));
    expect(s.rateLimited, isTrue);
    for (var i = 0; i < 100; i++) {
      sim.step(sp: 100, pv: 0, mode: ControllerMode.auto);
    }
    expect(sim.mv, lessThanOrEqualTo(60));
  });

  test('I-PD has no proportional setpoint kick', () {
    final sim = CentumPidSimulator(const CentumPidConfig(
      pb: 100, ti: 20, structure: PidStructure.iPd));
    sim.step(sp: 50, pv: 50, mode: ControllerMode.manual);
    sim.step(sp: 50, pv: 50, mode: ControllerMode.auto);
    final a = sim.step(sp: 60, pv: 50, mode: ControllerMode.auto);
    expect(a.p, closeTo(-50, 1e-8));
    expect(a.mv - 50, lessThan(1));
  });

  test('invalid tuning rejected', () {
    expect(() => CentumPidSimulator(const CentumPidConfig(pb: 0, ti: 20)), throwsArgumentError);
  });
}

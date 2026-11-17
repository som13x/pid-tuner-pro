import 'package:test/test.dart';
import 'package:pid_tuner_pro_core/centum_pid_simulator.dart';

PidSnapshot response(PidStructure structure, {double td = 0}) {
  final sim = CentumPidSimulator(CentumPidConfig(
    pb: 100, ti: 20, td: td, dt: 0.1,
    derivativeFilterSeconds: 0.1, structure: structure));
  sim.step(sp: 50, pv: 50, mode: ControllerMode.manual, manualMv: 50);
  sim.step(sp: 50, pv: 50, mode: ControllerMode.auto);
  return sim.step(sp: 60, pv: 50, mode: ControllerMode.auto);
}

void main() {
  test('PI-D and I-PD suppress derivative kick on setpoint change', () {
    final pid = response(PidStructure.pid, td: 2);
    final piD = response(PidStructure.piD, td: 2);
    final iPd = response(PidStructure.iPd, td: 2);
    expect(pid.d, greaterThan(0));
    expect(piD.d, closeTo(0, 1e-9));
    expect(iPd.d, closeTo(0, 1e-9));
  });

  test('I-PD avoids proportional setpoint kick while PI-D retains it', () {
    final pid = response(PidStructure.pid);
    final piD = response(PidStructure.piD);
    final iPd = response(PidStructure.iPd);
    expect(pid.p, closeTo(10, 1e-9));
    expect(piD.p, closeTo(10, 1e-9));
    expect(iPd.p, closeTo(-50, 1e-9));
  });

  test('AUTO and MAN are modes, not PID structure selectors', () {
    final sim = CentumPidSimulator(const CentumPidConfig(
      pb: 120, ti: 20, structure: PidStructure.iPd));
    final manual = sim.step(sp: 50, pv: 50,
      mode: ControllerMode.manual, manualMv: 37);
    final auto = sim.step(sp: 50, pv: 50, mode: ControllerMode.auto);
    expect(manual.mode, ControllerMode.manual);
    expect(auto.mode, ControllerMode.auto);
    expect(auto.mv, closeTo(37, 1e-9));
  });
}

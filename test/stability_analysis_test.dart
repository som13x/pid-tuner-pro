import 'dart:math' as math;
import 'package:test/test.dart';
import 'package:pid_tuner_pro_core/auto_tune.dart';
import 'package:pid_tuner_pro_core/robust_tune.dart';
import 'package:pid_tuner_pro_core/stability_analysis.dart';

void main() {
  test('gain crossover has unit magnitude', () {
    final a=PiFopdtStability(const Plant(gain:.8,tau:12,delay:3),
      pb:120,ti:20);
    final m=a.analyze();
    expect(a.at(m.gainCrossoverRadSec).magnitude,closeTo(1,1e-9));
    expect(m.phaseCrossoverRadSec,isNotNull);
    expect(a.at(m.phaseCrossoverRadSec!).phaseDegrees,closeTo(-180,1e-6));
  });
  test('negative plant gain has same margins with correct action', () {
    final pos=PiFopdtStability(const Plant(gain:.8,tau:12,delay:3),
      pb:120,ti:20).analyze();
    final neg=PiFopdtStability(const Plant(gain:-.8,tau:12,delay:3),
      pb:120,ti:20).analyze();
    expect(neg.phaseMarginDegrees,closeTo(pos.phaseMarginDegrees,1e-9));
    expect(neg.gainMarginDb,closeTo(pos.gainMarginDb!,1e-9));
  });
  test('zero dead time has no finite phase crossover', () {
    final m=PiFopdtStability(const Plant(gain:.8,tau:12,delay:0),
      pb:120,ti:20).analyze();
    expect(m.phaseCrossoverRadSec,isNull);
    expect(m.gainMarginDb,isNull);
  });
  test('high proportional gain can violate strict phase margin', () {
    final plant=const Plant(gain:1,tau:12,delay:5);
    final low=PiFopdtStability(plant,pb:250,ti:20).analyze();
    final high=PiFopdtStability(plant,pb:10,ti:20).analyze();
    expect(high.phaseMarginDegrees,lessThan(low.phaseMarginDegrees));
    expect(high.passes,isFalse);
  });
  test('Bode grid frequencies ascend and phase includes delay', () {
    final a=PiFopdtStability(const Plant(gain:1,tau:10,delay:2),
      pb:100,ti:10);
    final b=a.bode(count:5);
    expect(b.length,5);
    expect(b.first.omega,closeTo(.001,1e-12));
    expect(b.last.omega,closeTo(100,1e-8));
    expect(b.last.phaseRadians,lessThan(-math.pi));
  });
  test('ensemble check returns one margin per scenario', () {
    final e=ModelEnsemble.build([
      const PlantObservation(Plant(gain:.7,tau:10,delay:2),
        label:'a',rSquared:.99,normalizedRmse:.02),
      const PlantObservation(Plant(gain:.9,tau:16,delay:5),
        label:'b',rSquared:.98,normalizedRmse:.03),
    ]);
    final r=checkRobustStability(e,120,20);
    expect(r.scenarios.length,e.scenarios.length);
    expect(r.worstPhaseMarginDegrees,
      lessThanOrEqualTo(r.scenarios.first.phaseMarginDegrees));
  });
  test('invalid parameters rejected', () {
    expect(()=>PiFopdtStability(const Plant(gain:1,tau:10,delay:1),
      pb:0,ti:10),throwsArgumentError);
  });
}

import 'package:test/test.dart';
import 'package:pid_tuner_pro_core/auto_tune.dart';
import 'package:pid_tuner_pro_core/robust_tune.dart';
import 'package:pid_tuner_pro_core/stability_analysis.dart';
import 'package:pid_tuner_pro_core/combined_robust_optimization.dart';

void main() {
  final ensemble=ModelEnsemble.build([
    PlantObservation(const Plant(gain:1,tau:12,delay:2),
      label:'A',rSquared:.97,normalizedRmse:.03),
    PlantObservation(const Plant(gain:1.15,tau:16,delay:3),
      label:'B',rSquared:.96,normalizedRmse:.04),
  ]);
  test('every returned candidate satisfies both domains', () {
    final result=CombinedRobustOptimizer(ensemble,config:const TuneConfig(
      coarseSteps:3,refinementSteps:3,duration:80,dt:.2,
      disturbanceAt:10)).search(top:3);
    expect(result.evaluated,greaterThanOrEqualTo(9));
    expect(result.scenarioCount,greaterThanOrEqualTo(2));
    expect(result.best.every((c)=>c.feasible),isTrue);
    expect(result.feasibleCount,greaterThanOrEqualTo(result.best.length));
  });
  test('strict frequency limits reject all returned candidates', () {
    final result=CombinedRobustOptimizer(ensemble,
      config:const TuneConfig(coarseSteps:3,refinementSteps:3,
        duration:80,disturbanceAt:10),
      limits:const StabilityLimits(minimumPhaseMarginDegrees:179,
        minimumGainMarginDb:200)).search(top:2);
    expect(result.best,isEmpty);
    expect(result.frequencyRejected,result.evaluated);
  });
  test('rejects invalid top', () {
    expect(()=>CombinedRobustOptimizer(ensemble).search(top:0),throwsArgumentError);
  });
}

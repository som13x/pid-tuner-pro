import 'package:test/test.dart';
import 'package:pid_tuner_pro_core/auto_tune.dart';
import 'package:pid_tuner_pro_core/robust_tune.dart';
import 'package:pid_tuner_pro_core/stability_analysis.dart';
import 'package:pid_tuner_pro_core/stability_studio.dart';

void main() {
  final ensemble = ModelEnsemble.build([
    const PlantObservation(Plant(gain:0.7,tau:10,delay:2),
      label:'test A',rSquared:0.99,normalizedRmse:0.03),
    const PlantObservation(Plant(gain:0.9,tau:16,delay:5),
      label:'test B',rSquared:0.98,normalizedRmse:0.04),
  ]);
  test('baseline margins include every scenario', () {
    final studio = StabilityStudio(ensemble);
    final c = RobustAutoTune(ensemble).evaluate(120,20);
    final report = studio.assess(c);
    expect(report.margins.scenarios.length,ensemble.scenarios.length);
    expect(report.pb,120);
    expect(report.ti,20);
  });
  test('strict frequency limits reject without overriding time-domain status', () {
    final studio = StabilityStudio(ensemble,
      limits:const StabilityLimits(minimumPhaseMarginDegrees:179,
        minimumGainMarginDb:120));
    final c = RobustAutoTune(ensemble).evaluate(120,20);
    final report = studio.assess(c);
    expect(report.frequencyDomainFeasible,isFalse);
    expect(report.feasible,isFalse);
    expect(report.timeDomainFeasible,c.feasible);
  });
  test('Bode points finite and ordered', () {
    final points = StabilityStudio(ensemble).bode(ensemble.nominal,120,20);
    expect(points.length,160);
    expect(points.first.omega,lessThan(points.last.omega));
    expect(points.every((p)=>p.magnitude.isFinite && p.phaseRadians.isFinite),isTrue);
  });
  test('shortlist validates size', () {
    expect(()=>StabilityStudio(ensemble).run(shortlist:0),throwsArgumentError);
  });
  test('report preserves baseline and evaluates requested shortlist', () {
    final config = TuneConfig(coarseSteps:3,refinementSteps:3,dt:0.2);
    final report = StabilityStudio(ensemble,config:config).run(shortlist:3);
    expect(report.baseline.pb,120);
    expect(report.scenarioCount,ensemble.scenarios.length);
    expect(report.candidates.length,lessThanOrEqualTo(3));
    expect(report.evaluated,greaterThanOrEqualTo(9));
  });
}

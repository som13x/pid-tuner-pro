import 'package:test/test.dart';
import 'package:pid_tuner_pro_core/engineering_workflow.dart';
import 'package:pid_tuner_pro_core/auto_tune.dart';
import 'package:pid_tuner_pro_core/step_identification.dart';

IdentificationResult fakeResult({double k=.8, double tau=12,
    double delay=3, double r2=.99, double nrmse=.01}) =>
  IdentificationResult(plant: Plant(gain:k,tau:tau,delay:delay),
    stepAt: 10,mvBefore: 50,mvAfter: 60,pvBefore: 50,
    rmse: .1,rSquared: r2,normalizedRmse: nrmse,fittedPoints: 60);

StepTestRecord record(String id, String op, IdentificationResult result) =>
  StepTestRecord(id:id, operatingPoint:op, source:'test.csv',
    identification:result, recordedAt:DateTime.utc(2026,11,17));

void main() {
  const workflow = EngineeringWorkflow();
  test('requires two accepted tests', () {
    expect(() => workflow.analyse([record('1','A',fakeResult())]),
      throwsStateError);
  });
  test('rejects duplicate identifiers', () {
    expect(() => workflow.analyse([
      record('same','A',fakeResult()),record('same','A',fakeResult())]),
      throwsArgumentError);
  });
  test('rejects mixed operating points by default', () {
    expect(() => workflow.analyse([
      record('1','A',fakeResult()),record('2','B',fakeResult())]),
      throwsStateError);
  });
  test('excludes failed-quality tests', () {
    expect(() => workflow.analyse([
      record('1','A',fakeResult()),
      record('2','A',fakeResult(r2:.4))]),throwsStateError);
  });
  test('end-to-end ensemble and report JSON', () {
    final result=workflow.analyse([
      record('1','A',fakeResult()),
      record('2','A',fakeResult(k:.82,tau:13,delay:3.2)),
      record('3','A',fakeResult(r2:.5))],
      config: const TuneConfig(coarseSteps:3,refinementSteps:3,
        duration:120,disturbanceAt:20),shortlist:2);
    expect(result.included.length,2);
    expect(result.excluded.length,1);
    expect(result.ensemble.scenarios,isNotEmpty);
    expect(result.toJson()['schemaVersion'],1);
    expect(result.analysis.candidates.length,lessThanOrEqualTo(2));
  });
}

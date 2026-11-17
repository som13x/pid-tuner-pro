import 'package:test/test.dart';
import '../lib/auto_tune.dart';
import '../lib/robust_tune.dart';

PlantObservation observation(String name,double k,double tau,double delay,
    {double r2=.98,double nrmse=.02}) => PlantObservation(
  Plant(gain:k,tau:tau,delay:delay),label:name,
  rSquared:r2,normalizedRmse:nrmse);

void main() {
  test('ensemble includes observations, nominal, and all corners', () {
    final e=ModelEnsemble.build([
      observation('1',.7,10,2),observation('2',.9,16,5)]);
    expect(e.scenarios.length,greaterThanOrEqualTo(9));
    expect(e.minGain,.7);
    expect(e.maxTau,16);
    expect(e.maxDelay,5);
    expect(e.scenarios.any((p)=>p.gain==.9&&p.tau==10&&p.delay==5),isTrue);
  });
  test('rejects insufficient quality observations', () {
    expect(()=>ModelEnsemble.build([
      observation('1',.8,12,3),
      observation('bad',.9,12,3,r2:.5)]),throwsStateError);
  });
  test('rejects sign-changing process', () {
    expect(()=>ModelEnsemble.build([
      observation('1',.8,12,3),observation('2',-.8,12,3)]),
      throwsStateError);
  });
  test('robust candidate fails if one scenario violates PV limit', () {
    final e=ModelEnsemble.build([
      observation('1',.8,12,3),observation('2',1.0,14,4)]);
    final engine=RobustAutoTune(e,const TuneConfig(
      disturbance:20,maxAbsPvError:1,coarseSteps:3,refinementSteps:3));
    final c=engine.evaluate(120,20);
    expect(c.feasible,isFalse);
    expect(c.violations.any((v)=>v.contains('PV deviation limit')),isTrue);
  });
  test('search respects bounds and worst-case MV rate', () {
    final e=ModelEnsemble.build([
      observation('1',.75,11,2),observation('2',.85,13,4)]);
    final r=RobustAutoTune(e,const TuneConfig(
      coarseSteps:5,refinementSteps:3)).search(top:3);
    expect(r.evaluated,greaterThanOrEqualTo(25));
    expect(r.scenarioCount,greaterThanOrEqualTo(9));
    for(final c in r.best) {
      expect(c.feasible,isTrue);
      expect(c.pb,inInclusiveRange(40,250));
      expect(c.ti,inInclusiveRange(5,80));
      expect(c.worstRate,lessThanOrEqualTo(5.000001));
      expect(c.worstError,lessThanOrEqualTo(10.000001));
    }
    for(var i=1;i<r.best.length;i++) {
      expect(r.best[i].worstTravel,
        greaterThanOrEqualTo(r.best[i-1].worstTravel-1e-8));
    }
  });
  test('zero disturbance does not demand actuator travel', () {
    final e=ModelEnsemble.build([
      observation('1',.8,12,3),observation('2',.9,14,4)]);
    final c=RobustAutoTune(e,const TuneConfig(disturbance:0)).evaluate(120,20);
    expect(c.worstTravel,closeTo(0,1e-8));
    expect(c.feasible,isTrue);
  });
}

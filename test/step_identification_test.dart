import 'dart:math' as math;
import 'package:test/test.dart';
import 'package:pid_tuner_pro_core/step_identification.dart';

List<TrendPoint> synthetic({double gain=.8,double tau=12,double delay=3,
  double step=10,double noise=0}) {
  return List.generate(301,(i) {
    final t=i.toDouble(), stepAt=20.0;
    final x=t-stepAt-delay;
    final pv=50+(x>0?gain*step*(1-math.exp(-x/tau)):0)+
        noise*math.sin(t*1.7);
    return TrendPoint(t,t>=stepAt?60:50,pv);
  });
}
void main() {
  const identifier=StepIdentifier();
  test('identifies positive FOPDT step', () {
    final r=identifier.identify(synthetic());
    expect(r.plant.gain,closeTo(.8,.05));
    expect(r.plant.tau,closeTo(12,1));
    expect(r.plant.delay,closeTo(3,1));
    expect(r.suitableForAutoTune,isTrue);
  });
  test('identifies negative process gain', () {
    final r=identifier.identify(synthetic(gain:-.6));
    expect(r.plant.gain,closeTo(-.6,.05));
  });
  test('tolerates small deterministic measurement noise', () {
    final r=identifier.identify(synthetic(noise:.02));
    expect(r.plant.gain,closeTo(.8,.05));
  });
  test('manual step time identifies same plant', () {
    final r=identifier.identify(synthetic(), manualStepAt: 20);
    expect(r.plant.gain,closeTo(.8,.05));
    expect(r.stepAt,20);
  });
  test('manual step time rejects wrong time', () {
    expect(()=>identifier.identify(synthetic(), manualStepAt: 25), throwsArgumentError);
  });
  test('rejects no MV step', () {
    final data=synthetic().map((p)=>TrendPoint(p.seconds,50,p.pv)).toList();
    expect(()=>identifier.identify(data),throwsArgumentError);
  });
  test('rejects multiple MV steps', () {
    final data=synthetic().map((p)=>TrendPoint(p.seconds,
      p.seconds>=80?65:p.mv,p.pv)).toList();
    expect(()=>identifier.identify(data),throwsArgumentError);
  });
  test('rejects nonuniform timestamps', () {
    final data=synthetic();
    data[10]=TrendPoint(10.5,data[10].mv,data[10].pv);
    expect(()=>identifier.identify(data),throwsArgumentError);
  });
}

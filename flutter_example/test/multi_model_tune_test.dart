import 'package:flutter_test/flutter_test.dart';
import 'package:pid_tuner_pro_demo/model_management.dart';
import 'package:pid_tuner_pro_demo/multi_model_tune.dart';

StoredIdentification model(int id, {String loop='FIC', String? point='flow=1400',
    double? r2=.98, double? nrmse=.03, double k=1}) =>
  StoredIdentification(id:id,loopId:loop,source:'Step Test CSV',
    createdAt:'2026-11-17T00:00:00Z',k:k,tau:12+id.toDouble(),
    delay:2,rSquared:r2,nrmse:nrmse,operatingPoint:point,active:false);

void main() {
  test('accepts two measured compatible step tests', () {
    final selection=MultiModelSelection.validate([model(1),model(2)],loopId:'FIC');
    expect(selection.ensemble().observations.length,2);
    expect((buildMultiModelArguments(selection)['models'] as List).length,2);
  });
  test('rejects missing fit quality rather than inventing it', () {
    expect(()=>MultiModelSelection.validate([model(1,r2:null),model(2)],loopId:'FIC'),throwsStateError);
  });
  test('rejects mismatched operating points', () {
    expect(()=>MultiModelSelection.validate([model(1),model(2,point:'flow=800')],loopId:'FIC'),throwsStateError);
  });
  test('rejects cross-loop selection', () {
    expect(()=>MultiModelSelection.validate([model(1),model(2,loop:'TIC')],loopId:'FIC'),throwsStateError);
  });
  test('rejects sign reversal', () {
    expect(()=>MultiModelSelection.validate([model(1),model(2,k:-1)],loopId:'FIC'),throwsStateError);
  });
  test('rejects repeated tests', () {
    expect(()=>MultiModelSelection.validate([model(1),model(1)],loopId:'FIC'),throwsStateError);
  });
}

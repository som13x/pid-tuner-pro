import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:pid_tuner_pro_demo/project_store.dart';

void main() {
  LoopProject sample() => LoopProject(id: 'fic80b', tag: 'FIC-80B',
    description: 'LNG', vendor: 'Yokogawa', controllerBlock: 'PID',
    createdAt: DateTime.utc(2026));

  test('identification is attached to the correct loop and survives reload', () async {
    final dir = await Directory.systemTemp.createTemp('pid_workflow_');
    try {
      final store = ProjectStore(File('${dir.path}/projects.json'));
      final other = LoopProject(id: 'other', tag: 'PIC-1', description: '',
        vendor: 'Generic', controllerBlock: 'PID', createdAt: DateTime.utc(2026));
      final fitted = sample().withIdentification(model: {'K': 0.8, 'T': 12, 'L': 3},
        source: 'csv', rSquared: .97, nrmse: .03);
      await store.save([fitted, other]);
      final loaded = await store.load();
      expect(loaded.first.identifiedModel!['T'], 12);
      expect(loaded.first.history.single['type'], 'identification');
      expect(loaded.last.identifiedModel, isNull);
    } finally { await dir.delete(recursive: true); }
  });

  test('tuning report requires an identified model', () {
    expect(() => sample().withTuneReport({'best': []}), throwsStateError);
  });

  test('tuning history retains the model snapshot', () {
    final fit = sample().withIdentification(model: {'K': .8, 'T': 12, 'L': 3},
      source: 'csv', rSquared: .95, nrmse: .04);
    final tuned = fit.withTuneReport({'best': [{'pbPercent': 120.0}]});
    expect(tuned.history.length, 2);
    expect((tuned.history.last['model'] as Map)['K'], .8);
  });

  test('invalid identified model is rejected', () {
    expect(() => sample().withIdentification(
      model: {'K': 0, 'T': 12, 'L': 3}, source: 'csv',
      rSquared: .99, nrmse: .01), throwsArgumentError);
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:pid_tuner_pro_demo/model_management.dart';
import 'package:pid_tuner_pro_demo/project_store.dart';
import 'package:pid_tuner_pro_demo/sqlite_project_store.dart';

void main() {
  late PidDatabase db;
  setUp(() async { db = await PidDatabase.inMemory(); });
  tearDown(() async { await db.close(); });

  LoopProject loop(String id) => LoopProject(id: id, tag: id,
    description: 'Test', vendor: 'Generic', controllerBlock: 'PI',
    createdAt: DateTime.utc(2026, 1, 1));

  test('multiple identifications can be selected independently', () async {
    var p = loop('FIC-1').withIdentification(model: {'K': 0.8, 'T': 12, 'L': 3}, source: 'first');
    await db.save([p]);
    p = p.withIdentification(model: {'K': 1.2, 'T': 18, 'L': 5}, source: 'second');
    await db.save([p]);
    final history = await db.modelsFor('FIC-1');
    expect(history, hasLength(2));
    await db.selectActiveModel('FIC-1', history.last.id);
    expect((await db.load()).single.identifiedModel!['K'], 0.8);
    expect((await db.modelsFor('FIC-1')).last.active, true);
  });

  test('cannot activate model from a different loop', () async {
    await db.save([loop('A').withIdentification(model: {'K': 1, 'T': 10, 'L': 2}, source: 'a'), loop('B')]);
    final id = (await db.modelsFor('A')).single.id;
    await expectLater(db.selectActiveModel('B', id), throwsStateError);
  });

  test('operating point is stored with the identification', () async {
    await db.save([loop('A').withIdentification(model: {'K': 1, 'T': 10, 'L': 2}, source: 'a')]);
    final id = (await db.modelsFor('A')).single.id;
    await db.updateOperatingPoint('A', id, 'Flow 1200; MV 50%');
    expect((await db.modelsFor('A')).single.operatingPoint, 'Flow 1200; MV 50%');
  });
}

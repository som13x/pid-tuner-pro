import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:pid_tuner_pro_demo/project_store.dart';
import 'package:pid_tuner_pro_demo/sqlite_project_store.dart';

LoopProject sample() => LoopProject(id: 'fic80b', tag: 'FIC-80B',
  description: 'LNG', vendor: 'Yokogawa CENTUM VP',
  controllerBlock: 'PID', createdAt: DateTime.utc(2026, 11, 17));

void main() {
  test('SQLite saves identification and tune history in order', () async {
    final db = await PidDatabase.inMemory();
    try {
      final base = sample();
      await db.save([base]);
      final identified = base.withIdentification(
        model: {'K': 0.8, 'T': 12, 'L': 3}, source: 'CSV',
        rSquared: 0.99, nrmse: 0.02);
      await db.save([identified]);
      await db.save([identified.withTuneReport({'pb': 120, 'ti': 20})]);
      final loaded = (await db.load()).single;
      expect(loaded.identifiedModel!['K'], 0.8);
      expect(loaded.history.map((e) => e['type']),
        ['identification', 'autoTune']);
    } finally { await db.close(); }
  });

  test('Duplicate IDs roll back the transaction', () async {
    final db = await PidDatabase.inMemory();
    try {
      await db.save([sample()]);
      await expectLater(db.save([sample(), sample()]), throwsArgumentError);
      expect((await db.load()).length, 1);
    } finally { await db.close(); }
  });

  test('Legacy JSON imports only once and preserves source', () async {
    final dir = await Directory.systemTemp.createTemp('pid_migrate_');
    final db = await PidDatabase.inMemory();
    try {
      final legacy = File('${dir.path}/projects.json');
      await ProjectStore(legacy).save([sample().withIdentification(
        model: {'K': 0.8, 'T': 12, 'L': 3}, source: 'Step Test',
        rSquared: 0.99, nrmse: 0.01)]);
      expect(await db.importLegacyIfEmpty(legacy), isTrue);
      expect(await db.importLegacyIfEmpty(legacy), isFalse);
      expect((await db.load()).single.history.length, 1);
      expect(await legacy.exists(), isTrue);
    } finally { await db.close(); await dir.delete(recursive: true); }
  });

  test('History cannot be silently rewritten', () async {
    final db = await PidDatabase.inMemory();
    try {
      final identified = sample().withIdentification(
        model: {'K': 0.8, 'T': 12, 'L': 3}, source: 'CSV',
        rSquared: 0.99, nrmse: 0.01);
      await db.save([identified]);
      await expectLater(db.save([sample()]), throwsStateError);
      expect((await db.load()).single.history.length, 1);
    } finally { await db.close(); }
  });
}

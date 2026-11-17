import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pid_tuner_pro_demo/model_management.dart';
import 'package:pid_tuner_pro_demo/project_backup.dart';
import 'package:pid_tuner_pro_demo/project_store.dart';
import 'package:pid_tuner_pro_demo/sqlite_project_store.dart';

LoopProject loop(String id) => LoopProject(
  id: id, tag: id, description: 'LNG flow loop',
  vendor: 'Yokogawa CENTUM VP', controllerBlock: 'PID',
  createdAt: DateTime.utc(2026, 11, 17),
);

Future<void> populate(PidDatabase db) async {
  var p = loop('FIC-80B').withIdentification(
    model: {'K': 0.8, 'T': 12, 'L': 3}, source: 'Step Test CSV',
    rSquared: 0.98, nrmse: 0.03,
  );
  p = p.withIdentification(
    model: {'K': 1.2, 'T': 18, 'L': 5}, source: 'Measured CSV',
    rSquared: 0.97, nrmse: 0.04,
  );
  await db.save([p.withTuneReport({'pbPercent': 120, 'tiSeconds': 20})]);
  final models = await db.modelsFor('FIC-80B');
  // Select the older model, not the latest one.
  await db.selectActiveModel('FIC-80B', models.last.id);
  await db.updateOperatingPoint('FIC-80B', models.last.id,
    'Flow=1400 m3/h; MV=48%; mode=AUTO');
}

void main() {
  test('round-trip preserves every model, provenance, active model, and events', () async {
    final origin = await PidDatabase.inMemory();
    final target = await PidDatabase.inMemory();
    try {
      await populate(origin);
      final data = await origin.exportProjectBackup();
      final preview = inspectProjectBackup(data);
      expect(preview.loops, 1);
      expect(preview.identifications, 2);
      expect(preview.events, 3);
      final restored = await target.restoreProjectBackup(data);
      expect(restored.events, 3);
      final models = await target.modelsFor('FIC-80B');
      expect(models.length, 2);
      final active = models.singleWhere((m) => m.active);
      expect(active.k, 0.8);
      expect(active.operatingPoint, contains('1400'));
      expect(active.source, 'Step Test CSV');
      expect(active.rSquared, 0.98);
      final projects = await target.load();
      expect(projects.single.identifiedModel!['K'], 0.8);
      expect(projects.single.history.last['type'], 'autoTune');
      final original = jsonDecode(data) as Map<String, dynamic>;
      final roundTrip = jsonDecode(await target.exportProjectBackup()) as Map<String, dynamic>;
      expect(roundTrip['loops'], original['loops']);
    } finally {
      await origin.close();
      await target.close();
    }
  });

  test('restore never overwrites a populated database by default', () async {
    final db = await PidDatabase.inMemory();
    try {
      await db.save([loop('old')]);
      final other = await PidDatabase.inMemory();
      late final String exported;
      try {
        await other.save([loop('new')]);
        exported = await other.exportProjectBackup();
      } finally {
        await other.close();
      }
      await expectLater(db.restoreProjectBackup(exported), throwsStateError);
      expect((await db.load()).single.id, 'old');
      await db.restoreProjectBackup(exported, replaceExisting: true);
      expect((await db.load()).single.id, 'new');
    } finally { await db.close(); }
  });

  test('invalid version and duplicate IDs rejected before any database changes', () async {
    final db = await PidDatabase.inMemory();
    try {
      await db.save([loop('safe')]);
      final original = jsonDecode(await db.exportProjectBackup()) as Map<String, dynamic>;
      final wrongVersion = Map<String, dynamic>.from(original)..['schemaVersion'] = 99;
      expect(() => inspectProjectBackup(jsonEncode(wrongVersion)), throwsFormatException);
      final duplicate = Map<String, dynamic>.from(original)
        ..['loops'] = [original['loops'][0], original['loops'][0]];
      await expectLater(db.restoreProjectBackup(jsonEncode(duplicate),
        replaceExisting: true), throwsFormatException);
      expect((await db.load()).single.id, 'safe');
    } finally { await db.close(); }
  });

  test('invalid model and multiple active models are rejected', () async {
    final db = await PidDatabase.inMemory();
    try {
      await populate(db);
      final doc = jsonDecode(await db.exportProjectBackup()) as Map<String, dynamic>;
      final loop = (doc['loops'] as List).single as Map<String, dynamic>;
      final models = loop['identifications'] as List;
      models[0]['T'] = -5;
      expect(() => inspectProjectBackup(jsonEncode(doc)), throwsFormatException);
      models[0]['T'] = 12;
      models[0]['active'] = true;
      models[1]['active'] = true;
      expect(() => inspectProjectBackup(jsonEncode(doc)), throwsFormatException);
    } finally { await db.close(); }
  });

  test('SQLite failure in a replacement transaction rolls back original data', () async {
    final db = await PidDatabase.inMemory();
    final other = await PidDatabase.inMemory();
    try {
      await db.save([loop('original')]);
      await other.save([loop('BLOCK')]);
      final incoming = await other.exportProjectBackup();
      await db.customStatement('''CREATE TRIGGER block_restore BEFORE INSERT ON loops
        WHEN NEW.tag = 'BLOCK' BEGIN SELECT RAISE(ABORT, 'simulated failure'); END''');
      await expectLater(db.restoreProjectBackup(incoming,
        replaceExisting: true), throwsA(isA<Exception>()));
      expect((await db.load()).single.id, 'original');
    } finally {
      await db.close();
      await other.close();
    }
  });
}

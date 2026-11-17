import 'dart:convert';
import 'dart:io';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'project_store.dart';
import 'model_management.dart';

/// Drift-backed repository. Tables are defined with SQL to avoid generated files.
/// All writes occur in a single SQLite transaction.
class PidDatabase extends DatabaseConnectionUser {
  PidDatabase(super.connection);

  static Future<PidDatabase> open(File file) async {
    await file.parent.create(recursive: true);
    final db = PidDatabase(DatabaseConnection(NativeDatabase(file)));
    await db.initialize();
    return db;
  }

  static Future<PidDatabase> inMemory() async {
    final db = PidDatabase(DatabaseConnection(NativeDatabase.memory()));
    await db.initialize();
    return db;
  }

  Future<void> initialize() async {
    await customStatement('PRAGMA foreign_keys = ON');
    await customStatement('''CREATE TABLE IF NOT EXISTS loops (
      id TEXT PRIMARY KEY, tag TEXT NOT NULL, description TEXT NOT NULL,
      vendor TEXT NOT NULL, controller_block TEXT NOT NULL,
      created_at TEXT NOT NULL)''');
    await customStatement('''CREATE TABLE IF NOT EXISTS identifications (
      id INTEGER PRIMARY KEY AUTOINCREMENT, loop_id TEXT NOT NULL,
      k REAL NOT NULL, tau REAL NOT NULL, dead_time REAL NOT NULL,
      source TEXT NOT NULL, r_squared REAL, nrmse REAL, created_at TEXT NOT NULL,
      FOREIGN KEY(loop_id) REFERENCES loops(id) ON DELETE CASCADE,
      CHECK(tau > 0), CHECK(dead_time >= 0), CHECK(k != 0))''');
    await customStatement('''CREATE TABLE IF NOT EXISTS events (
      id INTEGER PRIMARY KEY AUTOINCREMENT, loop_id TEXT NOT NULL,
      event_type TEXT NOT NULL, event_json TEXT NOT NULL,
      created_at TEXT NOT NULL,
      FOREIGN KEY(loop_id) REFERENCES loops(id) ON DELETE CASCADE)''');
    await customStatement('CREATE INDEX IF NOT EXISTS events_loop_idx ON events(loop_id, id)');
    await customStatement('CREATE INDEX IF NOT EXISTS ident_loop_idx ON identifications(loop_id, id)');
    // Non-destructive migration for existing v1.2 databases.
    final cols = await customSelect('PRAGMA table_info(identifications)').get();
    if (!cols.any((r) => r.data['name'] == 'operating_point')) {
      await customStatement('ALTER TABLE identifications ADD COLUMN operating_point TEXT');
    }
    await customStatement('''CREATE TABLE IF NOT EXISTS active_models (
      loop_id TEXT PRIMARY KEY REFERENCES loops(id) ON DELETE CASCADE,
      identification_id INTEGER NOT NULL REFERENCES identifications(id) ON DELETE CASCADE)''');
    await customStatement('''CREATE TABLE IF NOT EXISTS metadata (
      key TEXT PRIMARY KEY, value TEXT NOT NULL)''');
  }

  Future<List<LoopProject>> load() async {
    final loops = await customSelect('SELECT * FROM loops ORDER BY created_at, id').get();
    final output = <LoopProject>[];
    for (final loop in loops) {
      final row = loop.data;
      final id = row['id'] as String;
      final models = await customSelect(
        '''SELECT i.k, i.tau, i.dead_time FROM identifications i
          LEFT JOIN active_models a ON a.loop_id = i.loop_id
          WHERE i.loop_id = ? ORDER BY (i.id = a.identification_id) DESC, i.id DESC LIMIT 1''',
        variables: [Variable.withString(id)],
      ).get();
      final events = await customSelect(
        'SELECT event_json FROM events WHERE loop_id = ? ORDER BY id',
        variables: [Variable.withString(id)],
      ).get();
      final m = models.isEmpty ? null : models.first.data;
      output.add(LoopProject(
        id: id, tag: row['tag'] as String,
        description: row['description'] as String,
        vendor: row['vendor'] as String,
        controllerBlock: row['controller_block'] as String,
        createdAt: DateTime.parse(row['created_at'] as String),
        identifiedModel: m == null ? null : {
          'K': (m['k'] as num).toDouble(),
          'T': (m['tau'] as num).toDouble(),
          'L': (m['dead_time'] as num).toDouble(),
        },
        history: events.map((e) => Map<String, Object?>.from(
          jsonDecode(e.data['event_json'] as String) as Map)).toList(),
      ));
    }
    return output;
  }

  /// Snapshot save for compatibility with existing UI. Existing events are
  /// append-only: rewriting an earlier event is rejected.
  Future<void> save(List<LoopProject> projects) async {
    if (projects.map((e) => e.id).toSet().length != projects.length) {
      throw ArgumentError('Duplicate loop IDs');
    }
    await transaction(() async {
      final old = {for (final x in await load()) x.id: x};
      final ids = projects.map((e) => e.id).toSet();
      for (final id in old.keys.where((id) => !ids.contains(id))) {
        await customStatement('DELETE FROM loops WHERE id = ?', [id]);
      }
      for (final project in projects) {
        final previous = old[project.id];
        final before = previous?.history ?? <Map<String, Object?>>[];
        if (project.history.length < before.length ||
            List.generate(before.length, (i) => jsonEncode(before[i]) == jsonEncode(project.history[i]))
                .contains(false)) {
          throw StateError('History must be append-only');
        }
        await customStatement('''INSERT INTO loops
          (id,tag,description,vendor,controller_block,created_at)
          VALUES (?,?,?,?,?,?) ON CONFLICT(id) DO UPDATE SET
          tag=excluded.tag, description=excluded.description,
          vendor=excluded.vendor, controller_block=excluded.controller_block''',
          [project.id, project.tag, project.description, project.vendor,
            project.controllerBlock, project.createdAt.toUtc().toIso8601String()]);
        for (final event in project.history.skip(before.length)) {
          final type = event['type']?.toString() ?? 'unknown';
          final at = event['at']?.toString() ?? DateTime.now().toUtc().toIso8601String();
          await customStatement('INSERT INTO events (loop_id,event_type,event_json,created_at) VALUES (?,?,?,?)',
            [project.id, type, jsonEncode(event), at]);
          if (type == 'identification') {
            final model = Map<String, dynamic>.from(event['model'] as Map);
            final k = (model['K'] as num).toDouble();
            final tau = (model['T'] as num).toDouble();
            final delay = (model['L'] as num).toDouble();
            if (![k, tau, delay].every((x) => x.isFinite) || k == 0 || tau <= 0 || delay < 0) {
              throw ArgumentError('Invalid identification');
            }
            await customStatement('''INSERT INTO identifications
              (loop_id,k,tau,dead_time,source,r_squared,nrmse,created_at)
              VALUES (?,?,?,?,?,?,?,?)''', [project.id,k,tau,delay,
                event['source']?.toString() ?? 'unknown',
                event['rSquared'],event['normalizedRmse'],at]);
          }
        }
        // Allow legacy projects with a model but no history.
        if (previous == null && project.identifiedModel != null &&
            !project.history.any((e) => e['type'] == 'identification')) {
          final m = project.identifiedModel!;
          await customStatement('''INSERT INTO identifications
            (loop_id,k,tau,dead_time,source,created_at) VALUES (?,?,?,?,?,?)''',
            [project.id,m['K'],m['T'],m['L'],'legacy import',project.createdAt.toUtc().toIso8601String()]);
        }
      }
    });
  }

  /// One-time import. The old JSON is retained as a rollback backup.
  Future<bool> importLegacyIfEmpty(File jsonFile) async {
    final flag = await customSelect("SELECT value FROM metadata WHERE key = 'legacy_imported'").get();
    if (flag.isNotEmpty) return false;
    if ((await customSelect('SELECT id FROM loops LIMIT 1').get()).isNotEmpty) return false;
    if (!await jsonFile.exists()) return false;
    final legacy = await ProjectStore(jsonFile).load();
    await transaction(() async {
      await save(legacy);
      await customStatement("INSERT INTO metadata(key,value) VALUES ('legacy_imported','1')");
    });
    return true;
  }

  Future<void> close() async => await connection.executor.close();
}

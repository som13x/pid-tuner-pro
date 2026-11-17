import 'dart:convert';

import 'package:drift/drift.dart';

import 'sqlite_project_store.dart';

/// Portable snapshot of the local engineering database.
///
/// Export includes *all* identifications, their quality/provenance, active
/// selections, operating points, and append-only event history. This is not a
/// backup of any external DCS configuration or the original imported CSV files.
class BackupOverview {
  final int loops;
  final int identifications;
  final int events;

  const BackupOverview({required this.loops, required this.identifications,
    required this.events});
}

const _backupFormat = 'pid-tuner-pro-project-backup';
const _backupVersion = 1;
const _maxBackupChars = 25 * 1024 * 1024;

Map<String, dynamic> _object(Object? raw, String path) {
  if (raw is! Map) throw FormatException('$path must be an object');
  try {
    return Map<String, dynamic>.from(raw);
  } on TypeError {
    throw FormatException('$path has non-string keys');
  }
}

List<dynamic> _array(Object? raw, String path) {
  if (raw is! List) throw FormatException('$path must be an array');
  return raw;
}

String _string(Map<String, dynamic> m, String key, String path) {
  final value = m[key];
  if (value is! String || value.trim().isEmpty) {
    throw FormatException('$path.$key must be a non-empty string');
  }
  return value;
}

String _timestamp(Map<String, dynamic> m, String key, String path) {
  final value = _string(m, key, path);
  if (DateTime.tryParse(value) == null) {
    throw FormatException('$path.$key must be an ISO-8601 timestamp');
  }
  return value;
}

double _number(Map<String, dynamic> m, String key, String path) {
  final value = m[key];
  if (value is! num || !value.toDouble().isFinite) {
    throw FormatException('$path.$key must be a finite number');
  }
  return value.toDouble();
}

double? _optionalNumber(Map<String, dynamic> m, String key, String path) =>
  m[key] == null ? null : _number(m, key, path);

class _CheckedBackup {
  final List<Map<String, dynamic>> loops;
  final BackupOverview overview;
  const _CheckedBackup(this.loops, this.overview);
}

_CheckedBackup _parseBackup(String text) {
  if (text.length > _maxBackupChars) {
    throw const FormatException('Backup exceeds 25 MB');
  }
  late final Map<String, dynamic> backup;
  try {
    backup = _object(jsonDecode(text), 'backup');
  } on FormatException {
    rethrow;
  } catch (_) {
    throw const FormatException('Invalid backup JSON');
  }
  if (backup['format'] != _backupFormat || backup['schemaVersion'] != _backupVersion) {
    throw const FormatException('Unsupported backup format or version');
  }
  final rawLoops = _array(backup['loops'], 'backup.loops');
  if (rawLoops.length > 1000) throw const FormatException('Too many loops');
  final ids = <String>{};
  final loops = <Map<String, dynamic>>[];
  var modelCount = 0;
  var eventCount = 0;

  for (var i = 0; i < rawLoops.length; i++) {
    final path = 'loops[$i]';
    final loop = _object(rawLoops[i], path);
    final id = _string(loop, 'id', path);
    if (!ids.add(id)) throw FormatException('Duplicate loop ID: $id');
    for (final key in ['tag', 'description', 'vendor', 'controllerBlock']) {
      // Description may legitimately be blank.
      if (key == 'description') {
        if (loop[key] is! String) throw FormatException('$path.description must be a string');
      } else {
        _string(loop, key, path);
      }
    }
    _timestamp(loop, 'createdAt', path);

    final rawModels = _array(loop['identifications'], '$path.identifications');
    final rawEvents = _array(loop['events'], '$path.events');
    modelCount += rawModels.length;
    eventCount += rawEvents.length;
    if (modelCount > 20000 || eventCount > 50000) {
      throw const FormatException('Backup contains too many records');
    }
    var activeCount = 0;
    for (var j = 0; j < rawModels.length; j++) {
      final mp = '$path.identifications[$j]';
      final model = _object(rawModels[j], mp);
      final k = _number(model, 'K', mp);
      final tau = _number(model, 'T', mp);
      final delay = _number(model, 'L', mp);
      if (k == 0 || tau <= 0 || delay < 0) {
        throw FormatException('$mp has invalid FOPDT parameters');
      }
      _string(model, 'source', mp);
      _timestamp(model, 'createdAt', mp);
      _optionalNumber(model, 'rSquared', mp);
      final nrmse = _optionalNumber(model, 'nrmse', mp);
      if (nrmse != null && nrmse < 0) throw FormatException('$mp has negative NRMSE');
      if (model['operatingPoint'] != null && model['operatingPoint'] is! String) {
        throw FormatException('$mp.operatingPoint must be a string or null');
      }
      if (model['active'] is! bool) throw FormatException('$mp.active must be a boolean');
      if (model['active'] == true) activeCount++;
    }
    if (activeCount > 1) throw FormatException('$path has multiple active models');
    for (var j = 0; j < rawEvents.length; j++) {
      final ep = '$path.events[$j]';
      final event = _object(rawEvents[j], ep);
      _string(event, 'type', ep);
      _timestamp(event, 'createdAt', ep);
      _object(event['payload'], '$ep.payload');
    }
    loops.add(loop);
  }
  return _CheckedBackup(loops, BackupOverview(
    loops: loops.length, identifications: modelCount, events: eventCount));
}

/// Parse and validate without touching the on-device database.
BackupOverview inspectProjectBackup(String text) => _parseBackup(text).overview;

extension ProjectBackup on PidDatabase {
  /// Consistent, human-readable, versioned JSON. No cloud upload.
  Future<String> exportProjectBackup() async {
    return transaction(() async {
      final rows = await customSelect('SELECT * FROM loops ORDER BY created_at, id').get();
      final projects = <Map<String, Object?>>[];
      for (final loop in rows) {
        final row = loop.data;
        final id = row['id'] as String;
        final variables = [Variable.withString(id)];
        final activeRows = await customSelect(
          'SELECT identification_id FROM active_models WHERE loop_id = ?',
          variables: variables).get();
        final activeId = activeRows.isEmpty ? null : activeRows.first.data['identification_id'];
        final models = await customSelect(
          'SELECT * FROM identifications WHERE loop_id = ? ORDER BY id',
          variables: variables).get();
        final events = await customSelect(
          'SELECT * FROM events WHERE loop_id = ? ORDER BY id',
          variables: variables).get();
        projects.add({
          'id': id,
          'tag': row['tag'],
          'description': row['description'],
          'vendor': row['vendor'],
          'controllerBlock': row['controller_block'],
          'createdAt': row['created_at'],
          'identifications': models.map((m) {
            final x = m.data;
            return <String, Object?>{
              'K': x['k'], 'T': x['tau'], 'L': x['dead_time'],
              'source': x['source'], 'rSquared': x['r_squared'],
              'nrmse': x['nrmse'], 'createdAt': x['created_at'],
              'operatingPoint': x['operating_point'],
              'active': x['id'] == activeId,
            };
          }).toList(),
          'events': events.map((e) {
            final x = e.data;
            return <String, Object?>{
              'type': x['event_type'], 'createdAt': x['created_at'],
              'payload': jsonDecode(x['event_json'] as String),
            };
          }).toList(),
        });
      }
      return const JsonEncoder.withIndent('  ').convert({
        'format': _backupFormat,
        'schemaVersion': _backupVersion,
        'exportedAt': DateTime.now().toUtc().toIso8601String(),
        'loops': projects,
      });
    });
  }

  /// By default, refuses to overwrite an existing database. With replacement
  /// explicitly enabled, the entire restore is one transaction (all or none).
  /// Existing CSV files are not part of this backup format.
  Future<BackupOverview> restoreProjectBackup(String text, {
    bool replaceExisting = false,
  }) async {
    final parsed = _parseBackup(text); // Validate everything before first write.
    await transaction(() async {
      final existing = await customSelect('SELECT id FROM loops LIMIT 1').get();
      if (existing.isNotEmpty && !replaceExisting) {
        throw StateError('Database is not empty; explicit replacement is required');
      }
      if (replaceExisting) await customStatement('DELETE FROM loops');
      for (final project in parsed.loops) {
        final id = project['id'] as String;
        await customStatement('''INSERT INTO loops
          (id, tag, description, vendor, controller_block, created_at)
          VALUES (?, ?, ?, ?, ?, ?)''', [
          id, project['tag'], project['description'], project['vendor'],
          project['controllerBlock'], project['createdAt'],
        ]);
        for (final rawModel in project['identifications'] as List) {
          final m = rawModel as Map<String, dynamic>;
          await customStatement('''INSERT INTO identifications
            (loop_id, k, tau, dead_time, source, r_squared, nrmse,
              created_at, operating_point) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)''', [
            id, m['K'], m['T'], m['L'], m['source'], m['rSquared'],
            m['nrmse'], m['createdAt'], m['operatingPoint'],
          ]);
          if (m['active'] == true) {
            final lastId = await customSelect('SELECT last_insert_rowid() AS id').get();
            await customStatement('''INSERT INTO active_models
              (loop_id, identification_id) VALUES (?, ?)''',
              [id, lastId.single.data['id']]);
          }
        }
        for (final rawEvent in project['events'] as List) {
          final e = rawEvent as Map<String, dynamic>;
          await customStatement('''INSERT INTO events
            (loop_id, event_type, event_json, created_at) VALUES (?, ?, ?, ?)''',
            [id, e['type'], jsonEncode(e['payload']), e['createdAt']]);
        }
      }
    });
    return parsed.overview;
  }
}

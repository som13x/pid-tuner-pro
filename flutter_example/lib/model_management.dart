import 'package:drift/drift.dart';
import 'sqlite_project_store.dart';

class StoredIdentification {
  final int id;
  final String loopId, source, createdAt;
  final double k, tau, delay;
  final double? rSquared, nrmse;
  final String? operatingPoint;
  final bool active;
  const StoredIdentification({required this.id, required this.loopId,
    required this.source, required this.createdAt, required this.k,
    required this.tau, required this.delay, this.rSquared, this.nrmse,
    this.operatingPoint, required this.active});
  Map<String, double> get model => {'K': k, 'T': tau, 'L': delay};
}

/// Database extension: model selection is independent of the latest test.
extension ModelManagement on PidDatabase {
  Future<List<StoredIdentification>> modelsFor(String loopId) async {
    final rows = await customSelect('''SELECT i.*, a.identification_id AS active_id
      FROM identifications i LEFT JOIN active_models a ON a.loop_id = i.loop_id
      WHERE i.loop_id = ? ORDER BY i.id DESC''',
      variables: [Variable.withString(loopId)]).get();
    return rows.map((r) {
      final d = r.data;
      return StoredIdentification(
        id: d['id'] as int, loopId: d['loop_id'] as String,
        source: d['source'] as String, createdAt: d['created_at'] as String,
        k: (d['k'] as num).toDouble(), tau: (d['tau'] as num).toDouble(),
        delay: (d['dead_time'] as num).toDouble(),
        rSquared: (d['r_squared'] as num?)?.toDouble(),
        nrmse: (d['nrmse'] as num?)?.toDouble(),
        operatingPoint: d['operating_point'] as String?,
        active: d['active_id'] == d['id'],
      );
    }).toList();
  }

  Future<void> selectActiveModel(String loopId, int modelId) async {
    await transaction(() async {
      final found = await customSelect('''SELECT id FROM identifications
        WHERE id = ? AND loop_id = ?''', variables: [
          Variable.withInt(modelId), Variable.withString(loopId)]).get();
      if (found.isEmpty) throw StateError('Model does not belong to this loop');
      await customStatement('''INSERT INTO active_models(loop_id, identification_id)
        VALUES (?, ?) ON CONFLICT(loop_id) DO UPDATE SET
        identification_id = excluded.identification_id''', [loopId, modelId]);
    });
  }

  Future<void> updateOperatingPoint(String loopId, int modelId, String value) async {
    final changed = await customUpdate('''UPDATE identifications
      SET operating_point = ? WHERE id = ? AND loop_id = ?''',
      variables: [Variable.withString(value.trim()), Variable.withInt(modelId),
        Variable.withString(loopId)]);
    if (changed != 1) throw StateError('Identification not found');
  }
}

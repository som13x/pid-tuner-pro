import 'dart:convert';
import 'dart:io';
import 'package:pid_tuner_pro_core/cascade_circuit.dart';

/// Local project metadata. Models are deliberately not shared between loops.
class LoopProject {
  final String id;
  final String tag;
  final String description;
  final String vendor;
  final String controllerBlock;
  final DateTime createdAt;
  final Map<String, double>? identifiedModel;
  final List<Map<String, Object?>> history;

  const LoopProject({required this.id, required this.tag,
    required this.description, required this.vendor,
    required this.controllerBlock, required this.createdAt,
    this.identifiedModel, this.history = const []});

  /// Change DCS profile without reassigning any model or rewriting past
  /// reports. Existing history remains append-only and retains its original
  /// profile context. Changing vendor requires reviewing controller settings.
  LoopProject withControllerProfile({
    required String vendorName,
    required String blockName,
  }) {
    if (vendorName.trim().isEmpty || blockName.trim().isEmpty) {
      throw ArgumentError('Profile vendor and block are required');
    }
    if (vendor == vendorName && controllerBlock == blockName) return this;
    final event = <String, Object?>{
      'type': 'profileChanged',
      'at': DateTime.now().toUtc().toIso8601String(),
      'previousVendor': vendor,
      'previousBlock': controllerBlock,
      'vendor': vendorName,
      'block': blockName,
      'requiresEngineeringReview': true,
    };
    return LoopProject(
      id: id, tag: tag, description: description,
      vendor: vendorName, controllerBlock: blockName,
      createdAt: createdAt, identifiedModel: identifiedModel,
      history: [...history, event],
    );
  }

  /// Stored as an append-only event, so earlier schematics remain auditable
  /// and the existing SQLite/backup schemas do not require a migration.
  Map<String, dynamic>? get latestCircuitWiring {
    for (final event in history.reversed) {
      if (event['type'] == 'circuitWiring' && event['wiring'] is Map) {
        return Map<String, dynamic>.from(event['wiring'] as Map);
      }
    }
    return null;
  }

  LoopProject withCircuitWiring(Map<String, dynamic> wiring) {
    final validated = CircuitWiring.fromJson(wiring);
    final event = <String, Object?>{
      'type': 'circuitWiring',
      'at': DateTime.now().toUtc().toIso8601String(),
      'wiring': validated.toJson(),
      'wiringOnly': true,
      'verifiedForDcsDeployment': false,
    };
    return LoopProject(
      id: id, tag: tag, description: description, vendor: vendor,
      controllerBlock: controllerBlock, createdAt: createdAt,
      identifiedModel: identifiedModel,
      history: [...history, event],
    );
  }

  LoopProject withIdentification({required Map<String, double> model,
    required String source, required double rSquared, required double nrmse}) {
    if (!model.values.every((v) => v.isFinite) || model['T'] == null ||
        model['K'] == null || model['L'] == null || model['T']! <= 0 ||
        model['L']! < 0 || model['K'] == 0) {
      throw ArgumentError('Invalid FOPDT model');
    }
    final event = <String, Object?>{'type': 'identification',
      'at': DateTime.now().toUtc().toIso8601String(), 'source': source,
      'model': Map<String, double>.from(model), 'rSquared': rSquared,
      'normalizedRmse': nrmse};
    return LoopProject(id: id, tag: tag, description: description,
      vendor: vendor, controllerBlock: controllerBlock, createdAt: createdAt,
      identifiedModel: Map<String, double>.from(model),
      history: [...history, event]);
  }

  LoopProject withTuneReport(Map<String, dynamic> report) {
    if (identifiedModel == null) throw StateError('No identified model');
    final event = <String, Object?>{'type': 'autoTune',
      'at': DateTime.now().toUtc().toIso8601String(),
      'model': Map<String, double>.from(identifiedModel!),
      'report': report};
    return LoopProject(id: id, tag: tag, description: description,
      vendor: vendor, controllerBlock: controllerBlock, createdAt: createdAt,
      identifiedModel: identifiedModel, history: [...history, event]);
  }

  Map<String, Object?> toJson() => {
    'id': id, 'tag': tag, 'description': description, 'vendor': vendor,
    'controllerBlock': controllerBlock,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'identifiedModel': identifiedModel,
    'history': history,
  };

  factory LoopProject.fromJson(Map<String, dynamic> data) {
    final model = data['identifiedModel'];
    return LoopProject(
      id: data['id'] as String, tag: data['tag'] as String,
      description: data['description'] as String,
      vendor: data['vendor'] as String,
      controllerBlock: data['controllerBlock'] as String,
      createdAt: DateTime.parse(data['createdAt'] as String),
      history: ((data['history'] as List?) ?? const []).map((e) => Map<String, Object?>.from(e as Map)).toList(),
      identifiedModel: model == null ? null : (model as Map).map(
        (key, value) => MapEntry(key.toString(), (value as num).toDouble())),
    );
  }
}

/// Atomic file replacement to avoid half-written JSON after an app interruption.
/// Does not claim to be a transactional multi-user database.
class ProjectStore {
  final File file;
  const ProjectStore(this.file);

  Future<List<LoopProject>> load() async {
    if (!await file.exists()) return [];
    final data = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
    if (data['schemaVersion'] != 1) {
      throw const FormatException('Unsupported project schema version');
    }
    return (data['projects'] as List)
        .map((item) => LoopProject.fromJson(Map<String, dynamic>.from(item as Map)))
        .toList(growable: false);
  }

  Future<void> save(List<LoopProject> projects) async {
    if (projects.map((p) => p.id).toSet().length != projects.length) {
      throw ArgumentError('Duplicate project IDs');
    }
    await file.parent.create(recursive: true);
    final temp = File('${file.path}.tmp');
    await temp.writeAsString(jsonEncode({
      'schemaVersion': 1,
      'projects': projects.map((p) => p.toJson()).toList(),
    }), flush: true);
    if (await file.exists()) await file.delete();
    await temp.rename(file.path);
  }
}

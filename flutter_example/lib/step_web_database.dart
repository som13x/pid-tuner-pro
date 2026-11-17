import 'package:idb_shim/idb_shim.dart';
import 'package:pid_tuner_pro_core/auto_tune.dart';
import 'package:pid_tuner_pro_core/integrating_step_identification.dart';
import 'package:pid_tuner_pro_core/step_test_settings.dart';

import 'step_web_factory.dart';

/// IndexedDB (Safari) store for the current Step Test configuration and
/// append-only identification runs. No remote server or user account.
class StepWebDatabase {
  static const databaseName = 'pid-tuner-pro-step-test';
  static const _settingsStore = 'settings';
  static const _resultsStore = 'identifications';
  static const _tuningStore = 'tuning_calculations';

  final IdbFactory factory;
  Database? _database;

  StepWebDatabase({IdbFactory? factory})
      : factory = factory ?? makeStepDatabaseFactory();

  Future<void> open() async {
    if (_database != null) return;
    _database = await factory.open(
      databaseName,
      version: 2,
      onUpgradeNeeded: (event) {
        final db = event.database;
        if (!db.objectStoreNames.contains(_settingsStore)) {
          db.createObjectStore(_settingsStore);
        }
        if (!db.objectStoreNames.contains(_resultsStore)) {
          db.createObjectStore(_resultsStore, autoIncrement: true);
        }
        if (!db.objectStoreNames.contains(_tuningStore)) {
          db.createObjectStore(_tuningStore, autoIncrement: true);
        }
      },
    );
  }

  Database get _db {
    final db = _database;
    if (db == null) throw StateError('Database is not open');
    return db;
  }

  Future<StepTestSettings?> loadSettings() async {
    await open();
    final tx = _db.transaction(_settingsStore, idbModeReadOnly);
    final raw = await tx.objectStore(_settingsStore).getObject('active');
    await tx.completed;
    if (raw == null) return null;
    if (raw is! Map) {
      throw const FormatException('Stored Step Test settings are corrupted');
    }
    return StepTestSettings.fromJson(
      Map<String, dynamic>.from(raw),
    );
  }

  Future<void> saveSettings(StepTestSettings settings) async {
    settings.validate();
    await open();
    final tx = _db.transaction(_settingsStore, idbModeReadWrite);
    await tx.objectStore(_settingsStore).put(settings.toJson(), 'active');
    await tx.completed;
  }

  /// Every identified model stores a snapshot of Settings and the evidence.
  /// On error callers MUST keep the result marked unsaved.
  Future<void> addResult({
    required StepTestSettings settings,
    required Plant plant,
    required String source,
    required Map<String, Object?> evidence,
    StepPiEstimate? piEstimate,
    String? originalCsv,
  }) async {
    settings.validate();
    if (settings.isIntegratingAcquisition) {
      throw ArgumentError('FOPDT result cannot be stored as an IPDT test');
    }
    plant.validate();
    if (source.trim().isEmpty) throw ArgumentError('Missing source');
    if (originalCsv != null && originalCsv.length > 10 * 1024 * 1024) {
      throw ArgumentError('CSV exceeds 10 MB');
    }
    await open();
    final record = <String, Object?>{
      'schemaVersion': 1,
      'savedAt': DateTime.now().toUtc().toIso8601String(),
      'settings': settings.toJson(),
      'source': source,
      'model': {
        'K': plant.gain, 'T': plant.tau, 'L': plant.delay,
      },
      'evidence': evidence,
      if (piEstimate != null) 'piEstimate': piEstimate.toJson(),
      if (originalCsv != null) 'csvText': originalCsv,
      'requiresEngineeringReview': true,
      'verifiedForDcsDeployment': false,
    };
    final tx = _db.transaction(_resultsStore, idbModeReadWrite);
    await tx.objectStore(_resultsStore).add(record);
    await tx.completed;
  }

  /// Separate IPDT result schema. Never serialize Ki as FOPDT steady-state K.
  /// Existing records and object stores remain unchanged.
  Future<void> addIntegratingResult({
    required StepTestSettings settings,
    required IntegratingPlant plant,
    required String source,
    required Map<String, Object?> evidence,
    StepPiEstimate? piEstimate,
    String? originalCsv,
  }) async {
    settings.validate();
    plant.validate();
    if (!settings.isIntegratingAcquisition) {
      throw ArgumentError('IPDT results require integrating Step Test');
    }
    if (source.trim().isEmpty) throw ArgumentError('Missing source');
    if (originalCsv != null && originalCsv.length > 10 * 1024 * 1024) {
      throw ArgumentError('CSV exceeds 10 MB');
    }
    await open();
    final record = <String, Object?>{
      'schemaVersion': 1,
      'savedAt': DateTime.now().toUtc().toIso8601String(),
      'settings': settings.toJson(),
      'source': source,
      'model': {
        'type': 'IPDT',
        'KiPerSecond': plant.gainPerSecond,
        'L': plant.delaySeconds,
      },
      'evidence': evidence,
      if (piEstimate != null) 'piEstimate': piEstimate.toJson(),
      if (originalCsv != null) 'csvText': originalCsv,
      'requiresEngineeringReview': true,
      'verifiedForDcsDeployment': false,
    };
    final tx = _db.transaction(_resultsStore, idbModeReadWrite);
    await tx.objectStore(_resultsStore).add(record);
    await tx.completed;
  }

  /// Newest first, with all per-result settings snapshots intact.
  Future<List<Map<String, dynamic>>> getResults() async {
    await open();
    final tx = _db.transaction(_resultsStore, idbModeReadOnly);
    final rows = await tx.objectStore(_resultsStore).getAll();
    await tx.completed;
    return rows.reversed.map((raw) =>
      Map<String, dynamic>.from(raw as Map)).toList(growable: false);
  }

  /// Append-only tuning history, preserving the exact Settings and model.
  Future<void> saveTuningCalculation({
    required StepTestSettings settings,
    required Map<String, dynamic> sourceResult,
    required StepPiEstimate estimate,
  }) async {
    await open();
    final tx = _db.transaction(_tuningStore, idbModeReadWrite);
    await tx.objectStore(_tuningStore).add(<String, Object?>{
      'savedAt': DateTime.now().toUtc().toIso8601String(),
      'settings': settings.toJson(),
      'sourceSavedAt': sourceResult['savedAt'],
      'source': sourceResult['source'],
      'model': sourceResult['model'],
      'piEstimate': estimate.toJson(),
      'verifiedForDcsDeployment': false,
    });
    await tx.completed;
  }

  Future<List<Map<String, dynamic>>> getTuningCalculations() async {
    await open();
    final tx = _db.transaction(_tuningStore, idbModeReadOnly);
    final rows = await tx.objectStore(_tuningStore).getAll();
    await tx.completed;
    return rows.reversed.map((raw) =>
      Map<String, dynamic>.from(raw as Map)).toList(growable: false);
  }

  void close() {
    _database?.close();
    _database = null;
  }
}

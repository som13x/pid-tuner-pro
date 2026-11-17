import 'package:pid_tuner_pro_core/auto_tune.dart';
import 'package:pid_tuner_pro_core/step_test_settings.dart';
import 'package:pid_tuner_pro_demo/step_web_database.dart';

/// Synchronous-completion test double avoids tying Flutter widget pump's
/// fake clock to IndexedDB memory backend scheduling. Storage round-trips
/// are tested separately against real idb_shim in-memory DB transactions.
class FakeStepWebDatabase extends StepWebDatabase {
  StepTestSettings? configuration;
  final List<Map<String, dynamic>> rows = [];
  FakeStepWebDatabase({this.configuration});

  @override
  Future<void> open() async {}

  @override
  Future<StepTestSettings?> loadSettings() async => configuration;

  @override
  Future<void> saveSettings(StepTestSettings settings) async {
    settings.validate();
    configuration = settings;
  }

  @override
  Future<List<Map<String, dynamic>>> getResults() async => rows;

  @override
  Future<void> addResult({
    required StepTestSettings settings,
    required Plant plant,
    required String source,
    required Map<String, Object?> evidence,
    StepPiEstimate? piEstimate,
    String? originalCsv,
  }) async {
    rows.insert(0, {
      'settings': settings.toJson(),
      'source': source,
      'savedAt': DateTime.utc(2026, 11, 17).toIso8601String(),
      'model': {'K': plant.gain, 'T': plant.tau, 'L': plant.delay},
      'evidence': evidence,
      if (piEstimate != null) 'piEstimate': piEstimate.toJson(),
      if (originalCsv != null) 'csvText': originalCsv,
    });
  }

  @override
  void close() {}
}

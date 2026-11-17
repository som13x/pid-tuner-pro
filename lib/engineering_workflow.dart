import 'auto_tune.dart';
import 'step_identification.dart';
import 'robust_tune.dart';
import 'stability_studio.dart';
import 'stability_analysis.dart';

/// A step test with provenance and an explicit operating-point label.
class StepTestRecord {
  final String id, operatingPoint, source;
  final IdentificationResult identification;
  final DateTime recordedAt;
  const StepTestRecord({required this.id, required this.operatingPoint,
    required this.source, required this.identification,
    required this.recordedAt});

  PlantObservation toObservation() => PlantObservation.fromIdentification(
    identification, '$operatingPoint [$id]');
}

class WorkflowReport {
  final List<StepTestRecord> included;
  final List<StepTestRecord> excluded;
  final ModelEnsemble ensemble;
  final StabilityStudioReport analysis;
  const WorkflowReport(this.included, this.excluded, this.ensemble, this.analysis);

  Map<String, Object?> toJson() => {
    'schemaVersion': 1,
    'status': 'simulation_only_not_approved_for_plant',
    'includedTests': included.map((r) => _recordJson(r)).toList(),
    'excludedTests': excluded.map((r) => _recordJson(r)).toList(),
    'scenarioCount': ensemble.scenarios.length,
    'evaluatedCandidates': analysis.evaluated,
    'baseline': _candidateJson(analysis.baseline),
    'candidates': analysis.candidates.map(_candidateJson).toList(),
  };

  static Map<String, Object?> _recordJson(StepTestRecord r) => {
    'id': r.id, 'operatingPoint': r.operatingPoint,
    'source': r.source, 'recordedAt': r.recordedAt.toIso8601String(),
    'K': r.identification.plant.gain,
    'T_seconds': r.identification.plant.tau,
    'L_seconds': r.identification.plant.delay,
    'rSquared': r.identification.rSquared,
    'nrmse': r.identification.normalizedRmse,
  };

  static Map<String, Object?> _candidateJson(StabilityCandidateReport c) => {
    'pbPercent': c.pb, 'tiSeconds': c.ti,
    'timeFeasible': c.timeDomainFeasible,
    'frequencyFeasible': c.frequencyDomainFeasible,
    'feasible': c.feasible,
    'worstIae': c.worstIae, 'worstTravel': c.worstTravel,
    'worstError': c.worstError, 'violations': c.violations,
  };
}

/// Explicitly rejects mixing different operating points without engineer approval.
/// An approved mixed-point analysis is still only an envelope stress test.
class EngineeringWorkflow {
  final StepIdentifier identifier;
  const EngineeringWorkflow({this.identifier = const StepIdentifier()});

  StepTestRecord identify({required String id, required String operatingPoint,
    required String source, required DateTime recordedAt,
    required List<TrendPoint> trend, double? manualStepAt}) {
    if (id.trim().isEmpty || operatingPoint.trim().isEmpty || source.trim().isEmpty) {
      throw ArgumentError('ID, operating point and source are required');
    }
    return StepTestRecord(id: id, operatingPoint: operatingPoint,
      source: source, recordedAt: recordedAt,
      identification: identifier.identify(trend, manualStepAt: manualStepAt));
  }

  WorkflowReport analyse(List<StepTestRecord> records, {
    bool allowMixedOperatingPoints = false,
    TuneConfig config = const TuneConfig(),
    StabilityLimits limits = const StabilityLimits(),
    int shortlist = 20,
  }) {
    if (records.map((r) => r.id).toSet().length != records.length) {
      throw ArgumentError('Duplicate step test IDs');
    }
    final accepted = records.where((r) => r.identification.suitableForAutoTune).toList();
    final rejected = records.where((r) => !r.identification.suitableForAutoTune).toList();
    if (accepted.length < 2) {
      throw StateError('At least two quality-approved step tests required');
    }
    if (!allowMixedOperatingPoints &&
        accepted.map((r) => r.operatingPoint.trim()).toSet().length != 1) {
      throw StateError('Mixed operating points require explicit approval');
    }
    final ensemble = ModelEnsemble.build(
      accepted.map((r) => r.toObservation()).toList());
    final analysis = StabilityStudio(ensemble, config: config, limits: limits)
      .run(shortlist: shortlist);
    return WorkflowReport(List.unmodifiable(accepted),
      List.unmodifiable(rejected), ensemble, analysis);
  }
}

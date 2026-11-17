import 'package:pid_tuner_pro_core/auto_tune.dart';
import 'package:pid_tuner_pro_core/manual_step_identification.dart';
import 'package:pid_tuner_pro_core/step_identification.dart';

/// The route result carries true source provenance. Manual estimates must
/// never impersonate statistically validated CSV fits.
class StepTestSelection {
  final IdentificationResult? csvFit;
  final ManualStepEstimate? manualEstimate;

  const StepTestSelection.fromCsv(IdentificationResult fit)
      : csvFit = fit, manualEstimate = null;
  const StepTestSelection.fromManual(ManualStepEstimate estimate)
      : manualEstimate = estimate, csvFit = null;

  bool get isManual => manualEstimate != null;
  Plant get plant => csvFit?.plant ?? manualEstimate!.plant;
  String get source => isManual
      ? (manualEstimate!.input.method == ManualStepMethod.knownDelayAndT63
          ? 'Manual Step 63.2%'
          : 'Manual Step 28.3/63.2%')
      : 'Step Test CSV';
  double? get rSquared => csvFit?.rSquared;
  double? get nrmse => csvFit?.normalizedRmse;

  Map<String, Object?>? get manualEvidence => manualEstimate?.evidence;
}

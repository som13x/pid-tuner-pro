import 'auto_tune.dart';
import 'robust_tune.dart';
import 'stability_analysis.dart';

/// A frequency-domain assessment of an existing time-domain candidate.
/// No optimization or plant data is fabricated here.
class StabilityCandidateReport {
  final double pb, ti;
  final bool timeDomainFeasible, frequencyDomainFeasible;
  final double worstIae, worstTravel, worstError;
  final RobustStabilityResult margins;
  final List<String> violations;
  const StabilityCandidateReport({required this.pb, required this.ti,
    required this.timeDomainFeasible, required this.frequencyDomainFeasible,
    required this.worstIae, required this.worstTravel, required this.worstError,
    required this.margins, required this.violations});
  bool get feasible => timeDomainFeasible && frequencyDomainFeasible;
}

class StabilityStudioReport {
  final StabilityCandidateReport baseline;
  final List<StabilityCandidateReport> candidates;
  final int scenarioCount, evaluated;
  const StabilityStudioReport(this.baseline, this.candidates,
      this.scenarioCount, this.evaluated);
  List<StabilityCandidateReport> get accepted =>
      List.unmodifiable(candidates.where((c) => c.feasible));
}

/// Performs time-domain search then checks *all* enumerated plant scenarios
/// in frequency domain. The search is intentionally not a formal robust proof.
/// The time-domain shortlist may miss candidates that would pass frequency
/// limits; no claim of global optimality is made.
class StabilityStudio {
  final ModelEnsemble ensemble;
  final TuneConfig config;
  final StabilityLimits limits;
  StabilityStudio(this.ensemble, {this.config = const TuneConfig(),
      this.limits = const StabilityLimits()}) {
    config.validate();
    limits.validate();
  }

  StabilityCandidateReport assess(RobustCandidate c) {
    final margins = checkRobustStability(ensemble, c.pb, c.ti, limits: limits);
    return StabilityCandidateReport(pb:c.pb, ti:c.ti,
      timeDomainFeasible:c.feasible, frequencyDomainFeasible:margins.passes,
      worstIae:c.worstIae, worstTravel:c.worstTravel,
      worstError:c.worstError, margins:margins,
      violations:List.unmodifiable([...c.violations,...margins.violations]));
  }

  StabilityStudioReport run({int shortlist = 20}) {
    if (shortlist < 1) throw ArgumentError('shortlist must be positive');
    final result = RobustAutoTune(ensemble, config).search(top: shortlist);
    final candidates = result.best.map(assess).toList();
    // The original valve-priority ordering is preserved.
    return StabilityStudioReport(assess(result.baseline),
      List.unmodifiable(candidates), result.scenarioCount, result.evaluated);
  }

  List<FrequencyPoint> bode(Plant plant, double pb, double ti,
      {int count = 160}) =>
      PiFopdtStability(plant, pb:pb, ti:ti).bode(count:count);
}

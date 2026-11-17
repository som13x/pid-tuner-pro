import 'dart:math' as math;
import 'auto_tune.dart';
import 'robust_tune.dart';

/// Continuous-time, ideal PI and FOPDT open-loop frequency analysis.
/// PB is percent proportional band; Kp=100/PB assumes matching normalized
/// PV/MV spans. The controller action is selected to make loop gain positive.
/// Not a CENTUM VP algorithm emulation, nor a formal stability certificate.
class FrequencyPoint {
  final double omega, magnitude, phaseRadians;
  const FrequencyPoint(this.omega, this.magnitude, this.phaseRadians);
  double get magnitudeDb => 20 * math.log(magnitude) / math.ln10;
  double get phaseDegrees => phaseRadians * 180 / math.pi;
}

class StabilityMargins {
  final double gainCrossoverRadSec;
  final double? phaseCrossoverRadSec;
  final double phaseMarginDegrees;
  /// null when no finite phase crossover exists (e.g. zero dead time).
  final double? gainMarginDb;
  final bool passes;
  final List<String> violations;
  const StabilityMargins({required this.gainCrossoverRadSec,
    required this.phaseCrossoverRadSec,required this.phaseMarginDegrees,
    required this.gainMarginDb,required this.passes,
    required this.violations});
}

class StabilityLimits {
  final double minimumPhaseMarginDegrees;
  final double minimumGainMarginDb;
  const StabilityLimits({this.minimumPhaseMarginDegrees=45,
    this.minimumGainMarginDb=6});
  void validate() {
    if (!minimumPhaseMarginDegrees.isFinite ||
        minimumPhaseMarginDegrees < 0 || minimumPhaseMarginDegrees >= 180 ||
        !minimumGainMarginDb.isFinite || minimumGainMarginDb < 0) {
      throw ArgumentError('Invalid stability margin limits');
    }
  }
}

class PiFopdtStability {
  final Plant plant;
  final double pb, ti;
  PiFopdtStability(this.plant,{required this.pb,required this.ti}) {
    plant.validate();
    if (!pb.isFinite || pb<=0 || !ti.isFinite || ti<=0) {
      throw ArgumentError('Invalid PI tuning');
    }
  }
  double get _loopGain => (100/pb)*plant.gain.abs();

  FrequencyPoint at(double omega) {
    if (!omega.isFinite || omega<=0) throw ArgumentError('omega > 0 required');
    final integral=1/(omega*ti);
    final magnitude=_loopGain*math.sqrt(1+integral*integral)/
        math.sqrt(1+math.pow(omega*plant.tau,2));
    final phase=-math.atan(integral)-math.atan(omega*plant.tau)-
        omega*plant.delay;
    return FrequencyPoint(omega,magnitude,phase);
  }

  /// Bisection in log-frequency for monotonic |L(jw)| of PI/FOPDT.
  double _gainCrossover() {
    var lo=1e-12, hi=1.0;
    while(at(hi).magnitude>1 && hi<1e12) { hi*=2; }
    if (at(hi).magnitude>1) throw StateError('Gain crossover not bracketed');
    for(var i=0;i<110;i++) {
      final mid=math.sqrt(lo*hi);
      if(at(mid).magnitude>1) lo=mid; else hi=mid;
    }
    return math.sqrt(lo*hi);
  }

  double? _phaseCrossover() {
    if(plant.delay==0) return null; // PI+first order approaches -180° only.
    var lo=1e-12,hi=1.0;
    while(at(hi).phaseRadians > -math.pi && hi<1e12) { hi*=2; }
    if(at(hi).phaseRadians > -math.pi) return null;
    for(var i=0;i<110;i++) {
      final mid=(lo+hi)/2;
      if(at(mid).phaseRadians > -math.pi) lo=mid; else hi=mid;
    }
    return (lo+hi)/2;
  }

  StabilityMargins analyze([StabilityLimits limits=const StabilityLimits()]) {
    limits.validate();
    final wg=_gainCrossover();
    final pm=180+at(wg).phaseDegrees;
    final wp=_phaseCrossover();
    final gm=wp==null?null:-at(wp).magnitudeDb;
    final violations=<String>[];
    if(pm<limits.minimumPhaseMarginDegrees) {
      violations.add('Phase margin below ${limits.minimumPhaseMarginDegrees} deg');
    }
    if(gm!=null && gm<limits.minimumGainMarginDb) {
      violations.add('Gain margin below ${limits.minimumGainMarginDb} dB');
    }
    return StabilityMargins(gainCrossoverRadSec:wg,
      phaseCrossoverRadSec:wp,phaseMarginDegrees:pm,gainMarginDb:gm,
      passes:violations.isEmpty,violations:List.unmodifiable(violations));
  }

  List<FrequencyPoint> bode({double minOmega=0.001,
      double maxOmega=100, int count=180}) {
    if(minOmega<=0 || maxOmega<=minOmega || count<2 ||
        !minOmega.isFinite || !maxOmega.isFinite) {
      throw ArgumentError('Invalid frequency grid');
    }
    return List.unmodifiable(List.generate(count,(i)=>at(
      minOmega*math.pow(maxOmega/minOmega,i/(count-1)).toDouble())));
  }
}

class RobustStabilityResult {
  final List<StabilityMargins> scenarios;
  final double worstPhaseMarginDegrees;
  final double? worstGainMarginDb;
  final bool passes;
  final List<String> violations;
  const RobustStabilityResult(this.scenarios,this.worstPhaseMarginDegrees,
      this.worstGainMarginDb,this.passes,this.violations);
}

/// Applies frequency-domain margins to all enumerated ensemble scenarios.
/// These margins are necessary engineering screens, not sufficient proof of
/// robustness to arbitrary uncertainty or nonlinear actuator dynamics.
RobustStabilityResult checkRobustStability(ModelEnsemble ensemble,
    double pb,double ti,{StabilityLimits limits=const StabilityLimits()}) {
  final results=ensemble.scenarios.map((p)=>
      PiFopdtStability(p,pb:pb,ti:ti).analyze(limits)).toList();
  final failures=<String>[];
  for(var i=0;i<results.length;i++) {
    if(!results[i].passes) failures.add('Scenario $i: ${results[i].violations.join(', ')}');
  }
  final worstPm=results.map((r)=>r.phaseMarginDegrees).reduce(math.min);
  final finiteGm=results.where((r)=>r.gainMarginDb!=null)
      .map((r)=>r.gainMarginDb!).toList();
  return RobustStabilityResult(List.unmodifiable(results),worstPm,
    finiteGm.isEmpty?null:finiteGm.reduce(math.min),failures.isEmpty,
    List.unmodifiable(failures));
}

/// Filters the existing time-domain shortlist by frequency margins.
/// Rejection is explicit; never silently substitute a failed candidate.
List<RobustCandidate> filterByStability(ModelEnsemble ensemble,
    Iterable<RobustCandidate> candidates,
    {StabilityLimits limits=const StabilityLimits()}) =>
    List.unmodifiable(candidates.where((c)=>c.feasible &&
      checkRobustStability(ensemble,c.pb,c.ti,limits:limits).passes));

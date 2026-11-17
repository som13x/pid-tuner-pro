import 'auto_tune.dart';
import 'robust_tune.dart';
import 'stability_analysis.dart';
import 'stability_studio.dart';

/// Joint constrained PI search. Every visited point is checked against every
/// time-domain scenario AND every frequency-domain scenario. No shortlist gate.
/// Finite grid + local refinement: not a mathematical global optimum/proof.
class CombinedRobustResult {
  final StabilityCandidateReport baseline;
  final List<StabilityCandidateReport> best;
  final int evaluated, feasibleCount, frequencyRejected, timeRejected;
  final int scenarioCount;
  const CombinedRobustResult({required this.baseline, required this.best,
    required this.evaluated, required this.feasibleCount,
    required this.frequencyRejected, required this.timeRejected,
    required this.scenarioCount});
}

class CombinedRobustOptimizer {
  final ModelEnsemble ensemble;
  final TuneConfig config;
  final StabilityLimits limits;
  late final RobustAutoTune _time;
  CombinedRobustOptimizer(this.ensemble,
      {this.config=const TuneConfig(),this.limits=const StabilityLimits()}) {
    config.validate();
    limits.validate();
    _time=RobustAutoTune(ensemble,config);
  }

  /// Frequency checks first: inexpensive filter before numerical simulation.
  StabilityCandidateReport assess(double pb,double ti) {
    if (!pb.isFinite || !ti.isFinite || pb<=0 || ti<=0) {
      throw ArgumentError('Invalid PB/Ti');
    }
    final margins=checkRobustStability(ensemble,pb,ti,limits:limits);
    // Still evaluate time domain even if PM/GM fails, for transparent metrics.
    final run=_time.evaluate(pb,ti);
    return StabilityCandidateReport(pb:pb,ti:ti,
      timeDomainFeasible:run.feasible,
      frequencyDomainFeasible:margins.passes,
      worstIae:run.worstIae,worstTravel:run.worstTravel,
      worstError:run.worstError,margins:margins,
      violations:List.unmodifiable([...run.violations,...margins.violations]));
  }

  CombinedRobustResult search({int top=5}) {
    if(top<1) throw ArgumentError('top must be positive');
    final seen=<String,StabilityCandidateReport>{};
    void visit(double pb,double ti) {
      pb=pb.clamp(config.pbMin,config.pbMax).toDouble();
      ti=ti.clamp(config.tiMin,config.tiMax).toDouble();
      final key='${pb.toStringAsFixed(8)}:${ti.toStringAsFixed(8)}';
      seen.putIfAbsent(key,()=>assess(pb,ti));
    }
    for(var i=0;i<config.coarseSteps;i++) {
      for(var j=0;j<config.coarseSteps;j++) {
        visit(config.pbMin+(config.pbMax-config.pbMin)*i/(config.coarseSteps-1),
          config.tiMin+(config.tiMax-config.tiMin)*j/(config.coarseSteps-1));
      }
    }
    int compare(StabilityCandidateReport a,StabilityCandidateReport b) {
      var c=a.worstTravel.compareTo(b.worstTravel);
      if(c!=0)return c;
      c=a.worstIae.compareTo(b.worstIae);
      if(c!=0)return c;
      c=a.pb.compareTo(b.pb);
      return c!=0?c:a.ti.compareTo(b.ti);
    }
    List<StabilityCandidateReport> accepted()=>
      seen.values.where((c)=>c.feasible).toList()..sort(compare);
    var dp=(config.pbMax-config.pbMin)/(config.coarseSteps-1);
    var di=(config.tiMax-config.tiMin)/(config.coarseSteps-1);
    for(var round=0;round<2;round++) {
      final seeds=accepted().take(5).toList();
      if(seeds.isEmpty)break;
      for(final seed in seeds) {
        for(var i=0;i<config.refinementSteps;i++) {
          for(var j=0;j<config.refinementSteps;j++) {
            visit(seed.pb+dp*(2*i/(config.refinementSteps-1)-1),
              seed.ti+di*(2*j/(config.refinementSteps-1)-1));
          }
        }
      }
      dp/=3;di/=3;
    }
    final feasible=accepted();
    return CombinedRobustResult(baseline:assess(config.baselinePb,config.baselineTi),
      best:List.unmodifiable(feasible.take(top)),evaluated:seen.length,
      feasibleCount:feasible.length,
      frequencyRejected:seen.values.where((c)=>!c.frequencyDomainFeasible).length,
      timeRejected:seen.values.where((c)=>!c.timeDomainFeasible).length,
      scenarioCount:ensemble.scenarios.length);
  }
}

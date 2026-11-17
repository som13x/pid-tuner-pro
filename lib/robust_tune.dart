import 'dart:math' as math;
import 'auto_tune.dart';
import 'step_identification.dart';

/// An operating-point model from a distinct, validated step test.
class PlantObservation {
  final Plant plant;
  final double rSquared, normalizedRmse;
  final String label;
  const PlantObservation(this.plant, {required this.label,
    required this.rSquared, required this.normalizedRmse});

  factory PlantObservation.fromIdentification(IdentificationResult result,
      String label) => PlantObservation(result.plant, label: label,
      rSquared: result.rSquared, normalizedRmse: result.normalizedRmse);

  bool get accepted => rSquared.isFinite && normalizedRmse.isFinite &&
      rSquared >= .90 && normalizedRmse <= .10;
}

class ModelEnsemble {
  final List<PlantObservation> observations;
  final Plant nominal;
  final List<Plant> scenarios;
  final double minGain, maxGain, minTau, maxTau, minDelay, maxDelay;
  const ModelEnsemble._(this.observations, this.nominal, this.scenarios,
    this.minGain, this.maxGain, this.minTau, this.maxTau,
    this.minDelay, this.maxDelay);

  /// Includes every measured model and every K/T/L bounding-box corner.
  /// Corners are conservative synthetic combinations, not confidence bounds.
  factory ModelEnsemble.build(List<PlantObservation> input,
      {int minimumAccepted = 2}) {
    if (minimumAccepted < 1) throw ArgumentError('Invalid minimumAccepted');
    final accepted = input.where((o) => o.accepted).toList();
    if (accepted.length < minimumAccepted) {
      throw StateError('Not enough quality-approved step tests');
    }
    for (final o in accepted) { o.plant.validate(); }
    final signs = accepted.map((o) => o.plant.gain > 0).toSet();
    if (signs.length != 1) {
      throw StateError('Process gain changes sign across tests');
    }
    double minOf(double Function(Plant) f) =>
        accepted.map((o) => f(o.plant)).reduce(math.min);
    double maxOf(double Function(Plant) f) =>
        accepted.map((o) => f(o.plant)).reduce(math.max);
    final k0=minOf((p)=>p.gain),k1=maxOf((p)=>p.gain);
    final t0=minOf((p)=>p.tau),t1=maxOf((p)=>p.tau);
    final l0=minOf((p)=>p.delay),l1=maxOf((p)=>p.delay);
    final nominal=Plant(gain:(k0+k1)/2,tau:(t0+t1)/2,delay:(l0+l1)/2);
    final scenarios=<Plant>[];
    final keys=<String>{};
    void add(Plant p) {
      final key='${p.gain.toStringAsPrecision(14)}:'
          '${p.tau.toStringAsPrecision(14)}:${p.delay.toStringAsPrecision(14)}';
      if(keys.add(key)) scenarios.add(p);
    }
    add(nominal);
    for (final o in accepted) { add(o.plant); }
    for (final k in [k0,k1]) {
      for (final t in [t0,t1]) {
        for (final l in [l0,l1]) { add(Plant(gain:k,tau:t,delay:l)); }
      }
    }
    return ModelEnsemble._(List.unmodifiable(accepted),nominal,
      List.unmodifiable(scenarios),k0,k1,t0,t1,l0,l1);
  }
}

class RobustCandidate {
  final double pb, ti;
  final bool feasible;
  final double worstIae, worstError, worstTravel, worstRate;
  final List<String> violations;
  final List<Candidate> evaluations;
  const RobustCandidate({required this.pb,required this.ti,
    required this.feasible,required this.worstIae,required this.worstError,
    required this.worstTravel,required this.worstRate,
    required this.violations,required this.evaluations});
}

class RobustTuneResult {
  final RobustCandidate baseline;
  final List<RobustCandidate> best;
  final int evaluated, feasibleCount, scenarioCount;
  const RobustTuneResult(this.baseline,this.best,this.evaluated,
    this.feasibleCount,this.scenarioCount);
}

/// Worst-case constrained search. No claim of formal robust stability proof.
class RobustAutoTune {
  final ModelEnsemble ensemble;
  final TuneConfig config;
  late final List<AutoTune> _engines;
  RobustAutoTune(this.ensemble, [this.config=const TuneConfig()]) {
    config.validate();
    _engines=ensemble.scenarios.map((p)=>AutoTune(p,config)).toList();
  }

  RobustCandidate evaluate(double pb,double ti,{bool keepSamples=false}) {
    final runs=_engines.map((e)=>e.evaluate(pb,ti,
      keepSamples:keepSamples)).toList();
    final violations=<String>[];
    for (var i=0;i<runs.length;i++) {
      for (final v in runs[i].violations) {
        final label='Scenario $i: $v';
        if (!violations.contains(label)) violations.add(label);
      }
    }
    double worst(double Function(Candidate) f) => runs.map(f).reduce(math.max);
    return RobustCandidate(pb:pb,ti:ti,feasible:violations.isEmpty,
      worstIae:worst((r)=>r.metrics.iae),
      worstError:worst((r)=>r.metrics.maxError),
      worstTravel:worst((r)=>r.metrics.totalVariation),
      worstRate:worst((r)=>r.metrics.maxMvRate),
      violations:List.unmodifiable(violations),
      evaluations:List.unmodifiable(runs));
  }

  RobustTuneResult search({int top=5}) {
    if(top<1) throw ArgumentError('top must be positive');
    final seen=<String,RobustCandidate>{};
    void visit(double pb,double ti) {
      pb=pb.clamp(config.pbMin,config.pbMax).toDouble();
      ti=ti.clamp(config.tiMin,config.tiMax).toDouble();
      final key='${pb.toStringAsFixed(8)}:${ti.toStringAsFixed(8)}';
      seen.putIfAbsent(key,()=>evaluate(pb,ti));
    }
    for(var i=0;i<config.coarseSteps;i++) {
      for(var j=0;j<config.coarseSteps;j++) {
        visit(config.pbMin+(config.pbMax-config.pbMin)*i/(config.coarseSteps-1),
          config.tiMin+(config.tiMax-config.tiMin)*j/(config.coarseSteps-1));
      }
    }
    int compare(RobustCandidate a,RobustCandidate b) {
      final travel=a.worstTravel.compareTo(b.worstTravel);
      if(travel!=0) return travel;
      final iae=a.worstIae.compareTo(b.worstIae);
      if(iae!=0) return iae;
      final p=a.pb.compareTo(b.pb);
      return p!=0?p:a.ti.compareTo(b.ti);
    }
    List<RobustCandidate> feasible()=>seen.values.where((c)=>c.feasible)
        .toList()..sort(compare);
    var dp=(config.pbMax-config.pbMin)/(config.coarseSteps-1);
    var di=(config.tiMax-config.tiMin)/(config.coarseSteps-1);
    for(var round=0;round<2;round++) {
      final seeds=feasible().take(5).toList();
      if(seeds.isEmpty) break;
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
    final sorted=feasible();
    return RobustTuneResult(
      evaluate(config.baselinePb,config.baselineTi,keepSamples:true),
      List.unmodifiable(sorted.take(top).map((r)=>evaluate(r.pb,r.ti,
        keepSamples:true))),seen.length,sorted.length,ensemble.scenarios.length);
  }
}

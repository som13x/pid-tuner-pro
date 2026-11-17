import 'package:pid_tuner_pro_core/auto_tune.dart';
import 'package:pid_tuner_pro_core/robust_tune.dart';
import 'package:pid_tuner_pro_core/stability_studio.dart';
import 'package:pid_tuner_pro_core/combined_robust_optimization.dart';
import 'model_management.dart';

/// Never substitute assumed fit scores for missing measured data.
class MultiModelSelection {
  final List<StoredIdentification> models;
  final String operatingPoint;
  MultiModelSelection._(this.models, this.operatingPoint);

  factory MultiModelSelection.validate(List<StoredIdentification> input,
      {required String loopId}) {
    if (input.length < 2) throw StateError('Выберите минимум два Step Test');
    if (input.map((m) => m.id).toSet().length != input.length) {
      throw StateError('Повторяющиеся идентификаторы испытаний');
    }
    if (input.any((m) => m.loopId != loopId)) {
      throw StateError('Нельзя смешивать модели разных контуров');
    }
    if (input.any((m) => m.source.trim().isEmpty ||
        m.rSquared == null || m.nrmse == null ||
        !m.rSquared!.isFinite || !m.nrmse!.isFinite ||
        m.rSquared! < .90 || m.nrmse! > .10)) {
      throw StateError('Нужны реальные результаты идентификации: R² ≥ 0.90, NRMSE ≤ 0.10');
    }
    if (input.any((m) => !m.k.isFinite || m.k == 0 ||
        !m.tau.isFinite || m.tau <= 0 ||
        !m.delay.isFinite || m.delay < 0)) {
      throw StateError('Некорректные параметры K/T/L');
    }
    if (input.map((m) => m.k > 0).toSet().length != 1) {
      throw StateError('Знак усиления объекта отличается');
    }
    final points = input.map((m) => (m.operatingPoint ?? '').trim()).toSet();
    if (points.length != 1 || points.single.isEmpty) {
      throw StateError('Укажите одинаковую рабочую точку для каждого Step Test');
    }
    return MultiModelSelection._(List.unmodifiable(input), points.single);
  }

  ModelEnsemble ensemble() => ModelEnsemble.build(models.map((m) =>
    PlantObservation(Plant(gain:m.k,tau:m.tau,delay:m.delay),
      label:'Step Test #${m.id}',rSquared:m.rSquared!,
      normalizedRmse:m.nrmse!)).toList());
}

/// Pure isolate entry point; returns only serializable values.
Map<String, Object?> calculateMultiModel(Map<String, Object?> args) {
  final raw = (args['models'] as List).cast<Map<String, Object?>>();
  final observations = raw.map((m) => PlantObservation(
    Plant(gain:(m['k'] as num).toDouble(),
      tau:(m['tau'] as num).toDouble(),delay:(m['delay'] as num).toDouble()),
    label:m['label'] as String,rSquared:(m['r2'] as num).toDouble(),
    normalizedRmse:(m['nrmse'] as num).toDouble())).toList();
  final ensemble = ModelEnsemble.build(observations);
  final result = CombinedRobustOptimizer(ensemble).search(top:20);
  Map<String, Object?> item(StabilityCandidateReport c) => {
    'pb':c.pb,'ti':c.ti,'feasible':c.feasible,
    'timeDomainFeasible':c.timeDomainFeasible,
    'frequencyDomainFeasible':c.frequencyDomainFeasible,
    'worstIae':c.worstIae,'worstTravel':c.worstTravel,
    'violations':c.violations,
  };
  return {
    'modelIds':raw.map((m)=>m['id']).toList(),
    'operatingPoint':args['operatingPoint'],
    'scenarioCount':result.scenarioCount,'evaluated':result.evaluated,
    'feasibleCount':result.feasibleCount,
    'frequencyRejected':result.frequencyRejected,
    'timeRejected':result.timeRejected,
    'baseline':item(result.baseline),
    'candidates':result.best.map(item).toList(),
    'accepted':result.feasibleCount,
    'warning':'Сценарная проверка не доказывает робастную устойчивость; '
      'все рассмотренные кандидаты проверены по временным и частотным ограничениям; ' 'поиск сеточный и не гарантирует глобальный оптимум.',
  };
}

Map<String, Object?> buildMultiModelArguments(MultiModelSelection selection) => {
  'operatingPoint':selection.operatingPoint,
  'models':selection.models.map((m)=><String, Object?>{
    'id':m.id,'label':'Step Test #${m.id}', 'k':m.k,
    'tau':m.tau,'delay':m.delay,'r2':m.rSquared!,
    'nrmse':m.nrmse!,
  }).toList(),
};

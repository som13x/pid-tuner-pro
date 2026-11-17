import 'package:flutter/material.dart';
import 'package:pid_tuner_pro_core/integrating_step_identification.dart';

/// Original OptiControls four-point measurement: two pre-step points
/// (PV1/t1, PV2/t2) and two post-delay points (PV3/t3, PV4/t4).
class IntegratingManualForm extends StatefulWidget {
  final ValueChanged<IntegratingManualEstimate> onAccept;
  const IntegratingManualForm({super.key, required this.onAccept});

  @override
  State<IntegratingManualForm> createState() => _IntegratingManualFormState();
}

class _IntegratingManualFormState extends State<IntegratingManualForm> {
  late final Map<String, TextEditingController> inputs;
  IntegratingManualEstimate? estimate;
  String? error;

  @override
  void initState() {
    super.initState();
    // Never pre-fill measured data with invented plant observations.
    const defaults = <String, String>{
      'mvBefore': '', 'mvAfter': '',
      'pv1': '', 'pv2': '', 'pv3': '', 'pv4': '',
      't1': '', 't2': '', 't3': '', 't4': '',
      'delay': '',
      'mvLow': '0', 'mvHigh': '100',
      'pvLow': '0', 'pvHigh': '100',
    };
    inputs = defaults.map((k, v) => MapEntry(
      k, TextEditingController(text: v)));
  }

  @override
  void dispose() {
    for (final controller in inputs.values) {
      controller.dispose();
    }
    super.dispose();
  }

  double getNumber(String key) {
    final text = inputs[key]!.text.trim().replaceAll(',', '.');
    if (text.isEmpty) {
      throw FormatException('Заполните поле $key');
    }
    return double.parse(text);
  }

  void calculate() {
    try {
      final input = IntegratingManualInput(
        mvBefore: getNumber('mvBefore'),
        mvAfter: getNumber('mvAfter'),
        pv1: getNumber('pv1'),
        pv2: getNumber('pv2'),
        pv3: getNumber('pv3'),
        pv4: getNumber('pv4'),
        t1Seconds: getNumber('t1'),
        t2Seconds: getNumber('t2'),
        t3Seconds: getNumber('t3'),
        t4Seconds: getNumber('t4'),
        delaySeconds: getNumber('delay'),
        mvSpanLow: getNumber('mvLow'),
        mvSpanHigh: getNumber('mvHigh'),
        pvSpanLow: getNumber('pvLow'),
        pvSpanHigh: getNumber('pvHigh'),
      );
      final next = const IntegratingManualEstimator().estimate(input);
      setState(() { estimate = next; error = null; });
    } catch (e) {
      setState(() {
        estimate = null;
        error = 'Не удалось определить интегрирующее усиление: $e';
      });
    }
  }

  Widget input(String key, String label) => SizedBox(
    width: 165,
    child: TextField(
      key: Key('integrating-$key'),
      controller: inputs[key],
      keyboardType: const TextInputType.numberWithOptions(
        signed: true, decimal: true),
      onChanged: (_) {
        if (estimate != null || error != null) {
          setState(() { estimate = null; error = null; });
        }
      },
      decoration: InputDecoration(
        isDense: true,
        labelText: label,
        border: const OutlineInputBorder()),
    ),
  );

  Widget section(String title, String description) => Padding(
    padding: const EdgeInsets.fromLTRB(0, 14, 0, 10),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        Text(description, style: const TextStyle(fontSize: 12)),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text('OptiControls · ручной Step Test (4 точки)',
        style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 8),
      const Text('Момент ступени MV принимается за t = 0 с. '
        'Для точек ДО ступени укажите отрицательные t1 и t2; '
        'для точек ПОСЛЕ запаздывания положительные t3 и t4. '
        'Все значения времени вводятся в секундах.'),
      section('Ступень выхода регулятора · MV',
        'Зафиксируйте MV0 и MV1 после согласованной ступени.'),
      Wrap(spacing: 10, runSpacing: 14, children: [
        input('mvBefore', 'MV0 до ступени'),
        input('mvAfter', 'MV1 после ступени'),
      ]),
      section('Slope 1 · до ступени MV',
        'Выберите две достаточно разнесённые точки на исходном '
        'линейном участке: t1 < t2 ≤ 0.'),
      Wrap(spacing: 10, runSpacing: 14, children: [
        input('pv1', 'PV1 при t1'),
        input('t1', 't1, с'),
        input('pv2', 'PV2 при t2'),
        input('t2', 't2, с'),
      ]),
      section('Slope 2 · после запаздывания',
        'Две точки на новом установившемся НАКЛОНЕ, '
        'не на установившемся значении PV: L < t3 < t4.'),
      Wrap(spacing: 10, runSpacing: 14, children: [
        input('pv3', 'PV3 при t3'),
        input('t3', 't3, с'),
        input('pv4', 'PV4 при t4'),
        input('t4', 't4, с'),
      ]),
      section('Запаздывание и шкалы', 'Запаздывание L отсчитывается '
        'от ступени MV до пересечения продолжений двух прямых. '
        'Шкалы необходимы для нормирования ri.'),
      Wrap(spacing: 10, runSpacing: 14, children: [
        input('delay', 'Запаздывание L, с'),
        input('mvLow', 'MV шкала, мин.'),
        input('mvHigh', 'MV шкала, макс.'),
        input('pvLow', 'PV шкала, мин.'),
        input('pvHigh', 'PV шкала, макс.'),
      ]),
      const SizedBox(height: 14),
      FilledButton.icon(
        key: const Key('integrating-calculate'),
        onPressed: calculate,
        icon: const Icon(Icons.calculate_outlined),
        label: const Text('Рассчитать наклоны, DS и ri'),
      ),
      if (error != null) Padding(
        padding: const EdgeInsets.only(top: 10),
        child: Text(error!,
          style: TextStyle(color: Theme.of(context).colorScheme.error))),
      if (estimate != null) ...[
        const SizedBox(height: 12),
        Text('ri = ' +
          estimate!.plant.gainPerSecond.toStringAsFixed(6) +
          ' 1/с, L = ' +
          estimate!.plant.delaySeconds.toStringAsFixed(2) + ' с',
          style: Theme.of(context).textTheme.titleMedium),
        Text('T1 = ' + estimate!.t1Interval.toStringAsFixed(2) +
          ' с; T2 = ' + estimate!.t2Interval.toStringAsFixed(2) + ' с'),
        Text('Slope 1 = ' +
          estimate!.beforeSlopeNormalized.toStringAsFixed(5) +
          ' %/с; Slope 2 = ' +
          estimate!.afterSlopeNormalized.toStringAsFixed(5) + ' %/с'),
        Text('DS = ' +
          estimate!.deltaSlopeNormalized.toStringAsFixed(5) +
          ' %/с; ΔMV = ' +
          estimate!.deltaMvNormalized.toStringAsFixed(3) + ' % шкалы'),
        const Text('Ручные четыре точки не подтверждают линейность '
          'участков статистически. Проверьте тренды и ограничения.'),
        FilledButton.icon(
          key: const Key('integrating-save'),
          onPressed: () => widget.onAccept(estimate!),
          icon: const Icon(Icons.save_outlined),
          label: const Text('Сохранить OptiControls Step Test'),
        ),
      ],
    ],
  );
}

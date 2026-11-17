import 'package:flutter/material.dart';
import 'package:pid_tuner_pro_core/integrating_step_identification.dart';

/// OptiControls: PV1 and PV2 separated by T1 minutes;
/// PV3 and PV4 separated by T2 minutes. No absolute timestamps.
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
      'T1': '', 'T2': '', 'delay': '',
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
        t1Minutes: getNumber('T1'),
        t2Minutes: getNumber('T2'),
        delayMinutes: getNumber('delay'),
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
      Text('OptiControls · Step Test (T1/T2 в минутах)',
        style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 8),
      const Text('Вводите именно продолжительность двух интервалов '
        'в минутах, не абсолютное время точек: '
        'T1 между PV1 и PV2 на первом наклоне, '
        'T2 между PV3 и PV4 на втором наклоне. '
        'Запаздывание td также в минутах.'),
      section('Ступень выхода регулятора · MV',
        'Зафиксируйте MV0 и MV1 после согласованной ступени.'),
      Wrap(spacing: 10, runSpacing: 14, children: [
        input('mvBefore', 'MV0 до ступени'),
        input('mvAfter', 'MV1 после ступени'),
      ]),
      section('Slope 1 · до ступени MV',
        'Измерьте PV1 и PV2 на исходном наклоне. '
        'T1 — прошедшее между ними время в минутах.'),
      Wrap(spacing: 10, runSpacing: 14, children: [
        input('pv1', 'PV1'),
        input('pv2', 'PV2'),
        input('T1', 'T1, мин'),
      ]),
      section('Slope 2 · после запаздывания',
        'Измерьте PV3 и PV4 на новом наклоне после запаздывания. '
        'T2 — прошедшее между ними время в минутах.'),
      Wrap(spacing: 10, runSpacing: 14, children: [
        input('pv3', 'PV3'),
        input('pv4', 'PV4'),
        input('T2', 'T2, мин'),
      ]),
      section('Запаздывание и шкалы', 'Запаздывание td '
        '(L) измерьте от ступени MV до пересечения '
        'продолжений двух прямых. Вводите td в минутах. '
        'Шкалы необходимы для нормирования ri.'),
      Wrap(spacing: 10, runSpacing: 14, children: [
        input('delay', 'Запаздывание td, мин'),
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
          estimate!.integrationRatePerMinute.toStringAsFixed(6) +
          ' 1/мин, td = ' +
          estimate!.deadTimeMinutes.toStringAsFixed(3) + ' мин',
          style: Theme.of(context).textTheme.titleMedium),
        Text('T1 = ' + estimate!.t1IntervalMinutes.toStringAsFixed(3) +
          ' мин; T2 = ' + estimate!.t2IntervalMinutes.toStringAsFixed(3) +
          ' мин'),
        Text('Slope 1 = ' +
          estimate!.beforeSlopePercentPerMinute.toStringAsFixed(5) +
          ' %/мин; Slope 2 = ' +
          estimate!.afterSlopePercentPerMinute.toStringAsFixed(5) +
          ' %/мин'),
        Text('DS = ' +
          estimate!.deltaSlopePercentPerMinute.toStringAsFixed(5) +
          ' %/мин; ΔMV = ' +
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

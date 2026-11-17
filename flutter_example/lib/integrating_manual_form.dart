import 'package:flutter/material.dart';
import 'package:pid_tuner_pro_core/integrating_step_identification.dart';

/// IPDT Step Test. No FOPDT settling/t63 fields are used here.
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
    const defaults = <String, String>{
      'mvBefore': '40', 'mvAfter': '50',
      'pvAtT1': '45', 'pvAtT2': '55',
      't1': '20', 't2': '40',
      'delay': '5', 'baselineSlope': '0',
      'mvLow': '0', 'mvHigh': '100',
      'pvLow': '0', 'pvHigh': '100',
    };
    inputs = defaults.map((k,v) => MapEntry(
      k, TextEditingController(text: v)));
  }

  @override
  void dispose() {
    for (final input in inputs.values) { input.dispose(); }
    super.dispose();
  }

  double getNumber(String key) => double.parse(
    inputs[key]!.text.trim().replaceAll(',', '.'));

  void calculate() {
    try {
      final input = IntegratingManualInput(
        mvBefore: getNumber('mvBefore'),
        mvAfter: getNumber('mvAfter'),
        pvAtT1: getNumber('pvAtT1'),
        pvAtT2: getNumber('pvAtT2'),
        t1Seconds: getNumber('t1'), t2Seconds: getNumber('t2'),
        delaySeconds: getNumber('delay'),
        baselineSlopePerSecond: getNumber('baselineSlope'),
        mvSpanLow: getNumber('mvLow'), mvSpanHigh: getNumber('mvHigh'),
        pvSpanLow: getNumber('pvLow'), pvSpanHigh: getNumber('pvHigh'),
      );
      final next = const IntegratingManualEstimator().estimate(input);
      setState(() { estimate = next; error = null; });
    } catch (e) {
      setState(() {
        estimate = null;
        error = 'Невозможно определить интегрирующий объект: ' +
          e.toString();
      });
    }
  }

  Widget input(String key, String label) => SizedBox(
    width: 160,
    child: TextField(
      key: Key('integrating-' + key),
      controller: inputs[key],
      keyboardType: const TextInputType.numberWithOptions(
        signed: true, decimal: true),
      onChanged: (_) {
        if (estimate != null || error != null) {
          setState(() { estimate = null; error = null; });
        }
      },
      decoration: InputDecoration(
        isDense: true, labelText: label, border: const OutlineInputBorder()),
    ),
  );

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text('Интегрирующий процесс · IPDT',
        style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 8),
      const Text('На интегрирующем объекте PV изменяется по наклонной '
        'прямой, а не выходит на установившееся PV1. '
        'Введите два измерения PV на линейном участке ПОСЛЕ '
        'запаздывания, времена от ступени MV и исходный наклон PV.'),
      const SizedBox(height: 12),
      Wrap(spacing: 10, runSpacing: 14, children: [
        input('mvBefore','MV до ступени'),
        input('mvAfter','MV после ступени'),
        input('pvAtT1','PV при t1'),
        input('pvAtT2','PV при t2'),
        input('t1','t1 от ступени, с'),
        input('t2','t2 от ступени, с'),
        input('delay','Запаздывание L, с'),
        input('baselineSlope','Наклон PV ДО, ед./с'),
        input('mvLow','MV шкала, мин.'),
        input('mvHigh','MV шкала, макс.'),
        input('pvLow','PV шкала, мин.'),
        input('pvHigh','PV шкала, макс.'),
      ]),
      const SizedBox(height: 14),
      FilledButton.icon(
        key: const Key('integrating-calculate'),
        onPressed: calculate,
        icon: const Icon(Icons.calculate_outlined),
        label: const Text('Рассчитать Ki и L'),
      ),
      if (error != null) Padding(
        padding: const EdgeInsets.only(top: 10),
        child: Text(error!,
          style: TextStyle(color: Theme.of(context).colorScheme.error))),
      if (estimate != null) ...[
        const SizedBox(height: 12),
        Text('Ki = ' +
          estimate!.plant.gainPerSecond.toStringAsFixed(6) +
          ' 1/с, L = ' +
          estimate!.plant.delaySeconds.toStringAsFixed(2) + ' с',
          style: Theme.of(context).textTheme.titleMedium),
        Text('Исходный наклон PV = ' +
          estimate!.beforeSlopeNormalized.toStringAsFixed(5) +
          ' %/с; после ступени = ' +
          estimate!.afterSlopeNormalized.toStringAsFixed(5) +
          ' %/с'),
        const Text('Ручной ввод не подтверждает линейность рампы '
          'и не даёт статистической оценки качества модели.'),
        FilledButton.icon(
          key: const Key('integrating-save'),
          onPressed: () => widget.onAccept(estimate!),
          icon: const Icon(Icons.save_outlined),
          label: const Text('Сохранить IPDT Step Test'),
        ),
      ],
    ],
  );
}

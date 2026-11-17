import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:pid_tuner_pro_core/manual_step_identification.dart';

/// Standalone form: accepts only manually observed engineering quantities.
/// It does not claim CSV fit quality or automatic measurement verification.
class ManualStepForm extends StatefulWidget {
  final ValueChanged<ManualStepEstimate> onAccept;
  const ManualStepForm({super.key, required this.onAccept});

  @override
  State<ManualStepForm> createState() => _ManualStepFormState();
}

class _ManualStepFormState extends State<ManualStepForm> {
  late final Map<String, TextEditingController> fields;
  ManualStepMethod method = ManualStepMethod.knownDelayAndT63;
  ManualStepEstimate? estimate;
  String? error;
  bool confirmed = false;

  @override
  void initState() {
    super.initState();
    final defaults = <String, String>{
      'mvBefore': '40', 'mvAfter': '50',
      'pvBefore': '800', 'pvAfter': '950',
      'mvLow': '0', 'mvHigh': '100',
      'pvLow': '0', 'pvHigh': '1000',
      'delay': '3', 't28': '8', 't63': '18',
    };
    fields = defaults.map((key, value) =>
      MapEntry(key, TextEditingController(text: value)));
  }

  @override
  void dispose() {
    for (final c in fields.values) { c.dispose(); }
    super.dispose();
  }

  double parse(String name) {
    final raw = fields[name]!.text.trim().replaceAll(',', '.');
    final value = double.tryParse(raw);
    if (value == null || !value.isFinite) {
      throw FormatException('Некорректное число: ' + name);
    }
    return value;
  }

  void invalidate() {
    if (estimate != null || confirmed || error != null) {
      setState(() { estimate = null; confirmed = false; error = null; });
    }
  }

  void calculate() {
    try {
      final input = ManualStepInput(
        mvBefore: parse('mvBefore'), mvAfter: parse('mvAfter'),
        pvBefore: parse('pvBefore'), pvAfter: parse('pvAfter'),
        mvSpanLow: parse('mvLow'), mvSpanHigh: parse('mvHigh'),
        pvSpanLow: parse('pvLow'), pvSpanHigh: parse('pvHigh'),
        t63Seconds: parse('t63'),
        method: method,
        delaySeconds: method == ManualStepMethod.knownDelayAndT63
          ? parse('delay') : null,
        t28Seconds: method == ManualStepMethod.twoResponseTimes
          ? parse('t28') : null,
      );
      final next = const ManualStepEstimator().estimate(input);
      setState(() { estimate = next; error = null; confirmed = false; });
    } catch (e) {
      setState(() {
        error = 'Невозможно оценить модель: ' + e.toString();
        estimate = null;
        confirmed = false;
      });
    }
  }

  Widget field(String id, String label) => SizedBox(
    width: 155,
    child: TextField(
      key: Key('manual-step-' + id),
      controller: fields[id],
      onChanged: (_) => invalidate(),
      keyboardType: const TextInputType.numberWithOptions(
        signed: true, decimal: true),
      decoration: InputDecoration(
        labelText: label, isDense: true,
        border: const OutlineInputBorder()),
    ),
  );

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Text('Ручная оценка FOPDT по ступени MV',
        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
      const SizedBox(height: 8),
      const Text('Вводите реальные измеренные значения до и после '
        'одной устойчивой ступени MV. PV должна успеть установиться. '
        'Время отсчитывайте от момента подачи ступени.'),
      const SizedBox(height: 14),
      const Text('Значения до и после ступени',
        style: TextStyle(fontWeight: FontWeight.bold)),
      const SizedBox(height: 8),
      Wrap(spacing: 10, runSpacing: 12, children: [
        field('mvBefore', 'MV до'),
        field('mvAfter', 'MV после'),
        field('pvBefore', 'PV до'),
        field('pvAfter', 'PV после'),
      ]),
      const SizedBox(height: 16),
      const Text('Шкалы сигналов, в тех же единицах',
        style: TextStyle(fontWeight: FontWeight.bold)),
      const SizedBox(height: 8),
      Wrap(spacing: 10, runSpacing: 12, children: [
        field('mvLow', 'MV: нижняя граница'),
        field('mvHigh', 'MV: верхняя граница'),
        field('pvLow', 'PV: нижняя граница'),
        field('pvHigh', 'PV: верхняя граница'),
      ]),
      const SizedBox(height: 16),
      const Text('Способ оценки времени',
        style: TextStyle(fontWeight: FontWeight.bold)),
      const SizedBox(height: 8),
      RadioGroup<ManualStepMethod>(
        groupValue: method,
        onChanged: (value) {
          if (value != null) setState(() {
            method = value;
            estimate = null; error = null; confirmed = false;
          });
        },
        child: Column(children: const [
          RadioListTile<ManualStepMethod>(
            title: Text('Известны L и время 63,21%'),
            value: ManualStepMethod.knownDelayAndT63),
          RadioListTile<ManualStepMethod>(
            title: Text('Время 28,35% и 63,21%'),
            value: ManualStepMethod.twoResponseTimes),
        ]),
      ),
      const SizedBox(height: 8),
      Wrap(spacing: 10, runSpacing: 12, children: [
        if (method == ManualStepMethod.knownDelayAndT63)
          field('delay', 'Запаздывание L, с'),
        if (method == ManualStepMethod.twoResponseTimes)
          field('t28', 't28,35%, с'),
        field('t63', 't63,21%, с'),
      ]),
      const SizedBox(height: 8),
      Text(method == ManualStepMethod.knownDelayAndT63
        ? 'T = t63 − L. Введите t63 от подачи ступени, включая задержку L.'
        : 'По двум точкам: T = 1,5 × (t63 − t28), '
          'L = t63 − T. Оба времени отсчитываются от ступени MV.'),
      const SizedBox(height: 14),
      FilledButton.icon(
        onPressed: calculate,
        icon: const Icon(Icons.calculate_outlined),
        label: const Text('Рассчитать K / T / L')),
      if (error != null) Padding(
        padding: const EdgeInsets.only(top: 10),
        child: Text(error!, style: TextStyle(
          color: Theme.of(context).colorScheme.error))),
      if (estimate != null) ...[
        const SizedBox(height: 16),
        Text('K = ' + estimate!.plant.gain.toStringAsFixed(4) +
          ' (нормированный), T = ' +
          estimate!.plant.tau.toStringAsFixed(2) + ' с, L = ' +
          estimate!.plant.delay.toStringAsFixed(2) + ' с',
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        Text('K в инженерных единицах: ' +
          estimate!.gainEngineering.toStringAsFixed(4) +
          ' [PV ед. / MV ед.]. ΔMV = ' +
          estimate!.normalizedMvChange.toStringAsFixed(2) +
          '% шкалы; ΔPV = ' +
          estimate!.normalizedPvChange.toStringAsFixed(2) + '% шкалы.'),
        const SizedBox(height: 10),
        const Text('Расчётная переходная характеристика (не тренд с объекта)'),
        SizedBox(height: 210, child: CustomPaint(
          painter: _SyntheticStepPainter(estimate!.syntheticCurve()),
          child: const SizedBox.expand())),
        const SizedBox(height: 10),
        const Text('R² и NRMSE не вычисляются: фактического тренда нет. '
          'Модель предварительная; по одному ручному замеру нельзя '
          'подтвердить качество, линейность и устойчивость процесса.',
          style: TextStyle(color: Colors.deepOrange)),
        CheckboxListTile(
          key: const Key('manual-step-confirm'),
          value: confirmed,
          onChanged: (value) {
            setState(() => confirmed = value ?? false);
          },
          title: const Text('Подтверждаю: данные измерены на объекте, '
            'ступень была одиночной, PV достигла установившегося значения. '
            'Модель требует инженерной проверки перед применением.'),
          controlAffinity: ListTileControlAffinity.leading,
        ),
        const SizedBox(height: 8),
        FilledButton.icon(
          key: const Key('manual-step-accept'),
          onPressed: confirmed
            ? () => widget.onAccept(estimate!) : null,
          icon: const Icon(Icons.save_outlined),
          label: const Text('Передать оценочную модель в проект'),
        ),
      ],
    ],
  );
}

class _SyntheticStepPainter extends CustomPainter {
  final List<ManualStepPoint> points;
  _SyntheticStepPainter(this.points);

  @override
  void paint(Canvas canvas, Size size) {
    if (points.length < 2) return;
    const left = 48.0, top = 12.0, bottom = 32.0, right = 12.0;
    final w = math.max(1.0, size.width - left - right);
    final h = math.max(1.0, size.height - top - bottom);
    final start = points.first.pv;
    final finish = points.last.pv;
    var low = math.min(start, finish);
    var high = math.max(start, finish);
    if ((high - low).abs() < 1e-9) { low -= 1; high += 1; }
    final endT = points.last.seconds;
    Offset pos(ManualStepPoint p) => Offset(
      left + w * p.seconds / endT,
      top + h * (1 - (p.pv - low) / (high - low)));
    final axis = Paint()..color = Colors.grey..strokeWidth = 1;
    canvas.drawLine(const Offset(left, top),
      Offset(left, top + h), axis);
    canvas.drawLine(Offset(left, top + h),
      Offset(left + w, top + h), axis);
    final path = Path();
    for (var i = 0; i < points.length; i++) {
      final xy = pos(points[i]);
      if (i == 0) { path.moveTo(xy.dx, xy.dy); }
      else { path.lineTo(xy.dx, xy.dy); }
    }
    canvas.drawPath(path, Paint()
      ..color = Colors.teal
      ..strokeWidth = 2.2
      ..style = PaintingStyle.stroke);
    void label(String s, Offset at) {
      final tp = TextPainter(
        text: TextSpan(text: s,
          style: const TextStyle(color: Colors.grey, fontSize: 10)),
        textDirection: TextDirection.ltr)..layout();
      tp.paint(canvas, at);
    }
    label(high.toStringAsFixed(1), const Offset(0, top));
    label(low.toStringAsFixed(1), Offset(0, top + h - 10));
    label(endT.toStringAsFixed(0) + ' с',
      Offset(left + w - 30, top + h + 8));
  }

  @override
  bool shouldRepaint(covariant _SyntheticStepPainter old) =>
    old.points != points;
}

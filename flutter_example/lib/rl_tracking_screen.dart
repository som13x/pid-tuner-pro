import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:pid_tuner_pro_core/auto_tune.dart';
import 'package:pid_tuner_pro_core/external_tracking_lab.dart';

/// A fully offline experiment. RL-like input and actuator tracking are separate.
List<Map<String, dynamic>> rlTrackingWorker(Map<String, double> x) {
  final scenario = ExternalTrackingScenario(
    plant: Plant(gain: x['k']!, tau: x['tau']!, delay: x['delay']!),
    pb: x['pb']!, ti: x['ti']!, duration: x['duration']!,
    spStepAt: x['spAt']!, spStep: x['spStep']!,
    rlStepAt: x['rlAt']!, rlStep: x['rlStep']!,
    rlNoiseAmplitude: x['rlNoise']!, rlLagSeconds: x['rlLag']!,
    actuatorTauSeconds: x['actuatorLag']!,
    trackingTimeSeconds: x['trackingTime']!, mvRateLimit: x['mvRate']!,
  );
  return ExternalTrackingLab.compare(scenario).map((r) => <String, dynamic>{
    'externalTracking': r.externalTracking,
    'iae': r.metrics.iae, 'maxError': r.metrics.maxAbsError,
    'travel': r.metrics.mvTravel,
    'points': r.points.map((p) => <double>[
      p.seconds, p.sp, p.measuredPv, p.requestedMv, p.actualMv,
      p.rawRlLike, p.filteredRlLike,
    ]).toList(),
  }).toList();
}

class RlTrackingScreen extends StatefulWidget {
  final Map<String, double>? initialModel;
  final String? loopTag;
  const RlTrackingScreen({super.key, this.initialModel, this.loopTag});
  @override
  State<RlTrackingScreen> createState() => _RlTrackingScreenState();
}

class _RlTrackingScreenState extends State<RlTrackingScreen> {
  late final Map<String, TextEditingController> fields;
  List<Map<String, dynamic>>? runs;
  String? error;
  bool busy = false;
  int chart = 0;
  static const chartLabels = [
    'PV / SP: сравнение режимов',
    'MV: команда и привод',
    'RL-like: вход и фильтр',
  ];

  @override
  void initState() {
    super.initState();
    final m = widget.initialModel;
    final defaults = <String, double>{
      'k': m?['K'] ?? 0.8, 'tau': m?['T'] ?? 12, 'delay': m?['L'] ?? 2,
      'pb': 120, 'ti': 20, 'mvRate': 5, 'duration': 160,
      'spAt': 30, 'spStep': 5, 'rlAt': 45, 'rlStep': 10,
      'rlNoise': 2, 'rlLag': 2, 'actuatorLag': 4, 'trackingTime': 4,
    };
    fields = defaults.map((k, v) =>
      MapEntry(k, TextEditingController(text: v.toString())));
  }

  @override
  void dispose() {
    for (final c in fields.values) { c.dispose(); }
    super.dispose();
  }

  Widget number(String key, String label) => SizedBox(width: 150,
    child: TextField(
      controller: fields[key],
      keyboardType: const TextInputType.numberWithOptions(
        decimal: true, signed: true),
      decoration: InputDecoration(labelText: label, isDense: true,
        border: const OutlineInputBorder())));

  Future<void> calculate() async {
    final x = <String, double>{};
    for (final entry in fields.entries) {
      final value = double.tryParse(entry.value.text.trim().replaceAll(',', '.'));
      if (value == null || !value.isFinite) {
        setState(() => error = 'Некорректное число: ' + entry.key);
        return;
      }
      x[entry.key] = value;
    }
    if (x['k'] == 0 || x['tau']! < 0.4 || x['delay']! < 0 ||
        x['pb']! <= 0 || x['ti']! <= 0 ||
        x['duration']! <= 0 || x['duration']! > 600 ||
        x['spAt']! < 0 || x['spAt']! > x['duration']! ||
        x['rlAt']! < 0 || x['rlAt']! > x['duration']! ||
        x['rlNoise']! < 0 || x['rlLag']! < 0 ||
        x['actuatorLag']! < 0 || x['trackingTime']! < 0.2 ||
        x['mvRate']! <= 0) {
      setState(() => error = 'Проверьте: K≠0, T≥0.4 c, L≥0, '
          'время≤600 с, RL-фильтр≥0, tracking≥0.2 c, MV rate>0.');
      return;
    }
    setState(() { busy = true; error = null; runs = null; });
    try {
      final result = await compute(rlTrackingWorker, x);
      if (mounted) setState(() => runs = result);
    } catch (e) {
      if (mounted) setState(() => error = 'Ошибка моделирования: ' + e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.loopTag == null
        ? 'RL / Tracking Lab' : 'RL / Tracking · ' + widget.loopTag!)),
    body: ListView(padding: const EdgeInsets.all(16), children: [
      const Text('RL / External Tracking Lab',
          style: TextStyle(fontSize: 21, fontWeight: FontWeight.bold)),
      const SizedBox(height: 8),
      const Text('Два независимых эксперимента: фильтр внешнего сигнала '
        '(условно RL-like) и коррекция интегратора по фактическому MV привода. '
        'Реальное назначение RL1/RL2 зависит от блока CENTUM VP.'),
      if (widget.initialModel == null) const Text(
        'Демонстрационная FOPDT-модель: не подтверждена Step Test.',
        style: TextStyle(color: Colors.deepOrange)),
      const SizedBox(height: 16),
      const Text('Процесс и PI', style: TextStyle(fontWeight: FontWeight.bold)),
      const SizedBox(height: 8),
      Wrap(spacing: 8, runSpacing: 12, children: [
        number('k', 'K (%/%)'), number('tau', 'T, c'),
        number('delay', 'L, c'), number('pb', 'PB, %'),
        number('ti', 'Ti, c'), number('mvRate', 'Лимит MV, %/с'),
        number('duration', 'Время, c'), number('spAt', 'SP ступень, c'),
        number('spStep', 'ΔSP, %'),
      ]),
      const SizedBox(height: 16),
      const Text('Условный RL-like сигнал',
        style: TextStyle(fontWeight: FontWeight.bold)),
      const SizedBox(height: 8),
      Wrap(spacing: 8, runSpacing: 12, children: [
        number('rlAt', 'RL ступень, c'), number('rlStep', 'ΔRL'),
        number('rlNoise', 'Шум RL, ампл.'), number('rlLag', 'Фильтр RL, c'),
      ]),
      const SizedBox(height: 6),
      const Text('RL-фильтр в этой модели не подключён к PV или reset '
        'регулятора. Это отдельная демонстрация задержки и подавления шума.'),
      const SizedBox(height: 16),
      const Text('Внешнее отслеживание фактического MV',
        style: TextStyle(fontWeight: FontWeight.bold)),
      const SizedBox(height: 8),
      Wrap(spacing: 8, runSpacing: 12, children: [
        number('actuatorLag', 'Инерция привода, c'),
        number('trackingTime', 'Tracking time, c'),
      ]),
      const SizedBox(height: 6),
      const Text('Сравнение Tracking OFF/ON. Сигнал внешней обратной связи '
        'берётся от модели привода с предыдущего такта; '
        'back-calculation является упрощением, не алгоритмом Yokogawa.'),
      const SizedBox(height: 16),
      FilledButton.icon(onPressed: busy ? null : calculate,
        icon: const Icon(Icons.play_arrow),
        label: const Text('Сравнить OFF / ON')),
      if (busy) const LinearProgressIndicator(),
      if (error != null) Text(error!, style: TextStyle(
        color: Theme.of(context).colorScheme.error)),
      if (runs != null) ...[
        const SizedBox(height: 18),
        const Text('Метрики по измеренной PV',
          style: TextStyle(fontWeight: FontWeight.bold)),
        SingleChildScrollView(scrollDirection: Axis.horizontal,
          child: DataTable(columns: const [
            DataColumn(label: Text('Режим')),
            DataColumn(label: Text('IAE')),
            DataColumn(label: Text('Макс. |e|')),
            DataColumn(label: Text('Ход MV')),
          ], rows: runs!.map((r) => DataRow(cells: [
            DataCell(Text(r['externalTracking'] == true
              ? 'Tracking ON' : 'Tracking OFF')),
            DataCell(Text((r['iae'] as num).toStringAsFixed(1))),
            DataCell(Text((r['maxError'] as num).toStringAsFixed(2))),
            DataCell(Text((r['travel'] as num).toStringAsFixed(1))),
          ])).toList())),
        const SizedBox(height: 12),
        DropdownButtonFormField<int>(
          value: chart,
          decoration: const InputDecoration(
            labelText: 'График', border: OutlineInputBorder()),
          items: [
            for (var i = 0; i < chartLabels.length; i++)
              DropdownMenuItem(value: i, child: Text(chartLabels[i])),
          ],
          onChanged: (v) { if (v != null) setState(() => chart = v); }),
        const SizedBox(height: 12),
        SizedBox(height: 315, child: Card(
          child: Padding(padding: const EdgeInsets.all(12),
            child: CustomPaint(painter: _LabPlot(runs!, chart),
              child: const SizedBox.expand())))),
        const SizedBox(height: 8),
        const Text('Исследовательская модель. Фильтрация и tracking могут '
          'ухудшать устойчивость. Ни расчёты, ни обозначения RL-like '
          'не соответствуют подтверждённой реализации RL1/RL2 в DCS. '
          'Изменения не отправляются в контроллер.'),
      ],
    ]),
  );
}

class _LabPlot extends CustomPainter {
  final List<Map<String, dynamic>> runs;
  final int kind;
  _LabPlot(this.runs, this.kind);

  List<List<double>> data(Map<String, dynamic> run) =>
    (run['points'] as List).map((row) =>
      (row as List).map((v) => (v as num).toDouble()).toList()).toList();

  @override
  void paint(Canvas canvas, Size size) {
    final off = data(runs.first);
    final on = data(runs.last);
    if (off.length < 2 || on.length < 2) return;
    final series = <(String, List<List<double>>, int, Color)>[];
    if (kind == 0) {
      series.add(('PV tracking OFF', off, 2, Colors.deepOrange));
      series.add(('PV tracking ON', on, 2, Colors.teal));
      series.add(('SP', on, 1, Colors.blueGrey));
    } else if (kind == 1) {
      series.add(('MV команда OFF', off, 3, Colors.deepOrange));
      series.add(('MV привод OFF', off, 4, Colors.orange));
      series.add(('MV команда ON', on, 3, Colors.teal));
      series.add(('MV привод ON', on, 4, Colors.indigo));
    } else {
      series.add(('RL-like raw', on, 5, Colors.deepOrange));
      series.add(('RL-like filtered', on, 6, Colors.teal));
    }
    const left = 44.0, top = 10.0;
    final width = math.max(1.0, size.width - left - 12);
    final height = math.max(1.0, size.height - top - 70);
    final all = series.expand((s) => s.$2.map((p) => p[s.$3])).toList();
    var lo = all.reduce(math.min), hi = all.reduce(math.max);
    if ((hi - lo).abs() < 1e-8) { lo -= 1; hi += 1; }
    final totalTime = math.max(1.0, on.last[0]);
    Offset xy(List<double> p, int index) => Offset(
      left + width * p[0] / totalTime,
      top + height * (1 - (p[index] - lo) / (hi - lo)));
    final axis = Paint()..color = Colors.grey..strokeWidth = 1;
    canvas.drawLine(const Offset(left, top), Offset(left, top + height), axis);
    canvas.drawLine(Offset(left, top + height),
      Offset(left + width, top + height), axis);
    void label(String value, Offset point, Color color) {
      final painter = TextPainter(
        text: TextSpan(text: value,
          style: TextStyle(fontSize: 10, color: color)),
        textDirection: TextDirection.ltr)..layout();
      painter.paint(canvas, point);
    }
    label(hi.toStringAsFixed(1), const Offset(0, top), Colors.grey);
    label(lo.toStringAsFixed(1), Offset(0, top + height - 10), Colors.grey);
    label(totalTime.toStringAsFixed(0) + ' c',
      Offset(left + width - 35, top + height + 5), Colors.grey);
    for (var i = 0; i < series.length; i++) {
      final s = series[i];
      final path = Path();
      for (var j = 0; j < s.$2.length; j++) {
        final p = xy(s.$2[j], s.$3);
        if (j == 0) { path.moveTo(p.dx, p.dy); }
        else { path.lineTo(p.dx, p.dy); }
      }
      canvas.drawPath(path, Paint()
        ..color = s.$4..strokeWidth = 1.8
        ..style = PaintingStyle.stroke);
      label(s.$1, Offset(left + (i % 2) * 144,
        top + height + 22 + (i ~/ 2) * 16), s.$4);
    }
  }

  @override
  bool shouldRepaint(covariant _LabPlot old) =>
    old.runs != runs || old.kind != kind;
}

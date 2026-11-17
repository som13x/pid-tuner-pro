import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:pid_tuner_pro_core/auto_tune.dart';
import 'package:pid_tuner_pro_core/centum_pid_simulator.dart';
import 'package:pid_tuner_pro_core/dual_valve_lng.dart';

/// Isolate entry point. All values and results are transferable primitives.
List<Map<String, dynamic>> dualValveWorker(Map<String, double> x) {
  final a = Plant(gain: x['ka']!, tau: x['ta']!, delay: x['la']!);
  final b = Plant(gain: x['kb']!, tau: x['tb']!, delay: x['lb']!);
  final pid = CentumPidConfig(pb: x['pb']!, ti: x['ti']!, dt: 0.2,
      maxMvRate: x['rate']!);
  return CompensationStrategy.values.map((strategy) {
    final r = DualValveLngSimulator.simulate(DualValveScenario(
      branchA: a, branchB: b, controllerB: pid, strategy: strategy,
      dt: 0.2, duration: x['duration']!, faultAt: x['faultAt']!,
      faultAmplitude: x['amplitude']!, faultPeriod: x['period']!,
      pvFilterSeconds: x['filter']!, feedforwardFraction: x['ff']!,
    ));
    return <String, dynamic>{
      'strategy': strategy.name,
      'iae': r.metrics.iae,
      'maxError': r.metrics.maxAbsError,
      'travel': r.metrics.totalMvBTravel,
      'rate': r.metrics.maxMvBRate,
      'points': r.points.map((p) => <double>[
        p.t, p.sp, p.totalFlow, p.flowA, p.flowB, p.mvA, p.mvB, p.ffMv,
      ]).toList(),
    };
  }).toList();
}

class DualValveScreen extends StatefulWidget {
  /// An identified total-flow model is NOT automatically a branch model.
  /// Deliberately do not inject a loop's total-flow K/T/L into either branch.
  final String? loopTag;
  const DualValveScreen({super.key, this.loopTag});
  @override
  State<DualValveScreen> createState() => _DualValveScreenState();
}

class _DualValveScreenState extends State<DualValveScreen> {
  late final Map<String, TextEditingController> fields;
  List<Map<String, dynamic>>? runs;
  String? error;
  bool busy = false;
  int signal = 0;
  int selected = 0;
  static const signals = <String>['Суммарный расход / SP', 'Расходы A и B', 'MV клапанов A и B', 'FF-коррекция'];
  static const names = <String, String>{
    'pi': 'PI', 'filteredPv': 'PI + PV filter',
    'measuredFeedforward': 'PI + measured FF',
  };
  @override
  void initState() {
    super.initState();
    final defaults = <String, double>{
      'ka': 1, 'ta': 7, 'la': 2, 'kb': 1, 'tb': 10, 'lb': 2,
      'pb': 120, 'ti': 20, 'rate': 5, 'duration': 240,
      'faultAt': 40, 'amplitude': 5, 'period': 60, 'filter': 2, 'ff': 1,
    };
    fields = defaults.map((k, v) => MapEntry(k, TextEditingController(text: '$v')));
  }
  @override
  void dispose() {
    for (final c in fields.values) { c.dispose(); }
    super.dispose();
  }
  Widget field(String key, String label) => SizedBox(width: 148,
    child: TextField(controller: fields[key],
      keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
      decoration: InputDecoration(labelText: label, isDense: true,
        border: const OutlineInputBorder())));
  Future<void> calculate() async {
    final x = <String, double>{};
    for (final e in fields.entries) {
      final v = double.tryParse(e.value.text.trim().replaceAll(',', '.'));
      if (v == null || !v.isFinite) {
        setState(() => error = 'Некорректное значение ${e.key}'); return;
      }
      x[e.key] = v;
    }
    if (x['ka']! <= 0 || x['kb']! <= 0 || x['ta']! < 0.4 || x['tb']! < 0.4 ||
        x['la']! < 0 || x['lb']! < 0 || x['pb']! <= 0 || x['ti']! <= 0 ||
        x['rate']! <= 0 || x['duration']! <= 0 || x['duration']! > 1800 ||
        x['faultAt']! < 0 || x['amplitude']! < 0 || x['amplitude']! > 50 ||
        x['period']! <= 0 || x['filter']! <= 0 || x['ff']! < 0 || x['ff']! > 1) {
      setState(() => error = 'Проверьте диапазоны: K>0, T≥0.4 с, L≥0, амплитуда 0–50%, FF 0–1');
      return;
    }
    setState(() { busy = true; error = null; runs = null; });
    try {
      final result = await compute(dualValveWorker, x);
      if (mounted) setState(() => runs = result);
    } catch (e) {
      if (mounted) setState(() => error = 'Ошибка моделирования: $e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text('Dual-Valve LNG${widget.loopTag == null ? '' : ' · ${widget.loopTag}'}')),
    body: ListView(padding: const EdgeInsets.all(16), children: [
      const Text('Две параллельные линии LNG', style: TextStyle(fontSize: 21, fontWeight: FontWeight.bold)),
      const SizedBox(height: 8),
      const Text('A: ручное управление с механическим возмущением. B: PI-регулятор суммарного расхода. '
        'Сигналы нормированы; это исследовательская модель, не цифровой двойник установки.'),
      const SizedBox(height: 12),
      const Text('Ветвь A: FOPDT', style: TextStyle(fontWeight: FontWeight.bold)),
      const SizedBox(height: 8),
      Wrap(spacing: 8, runSpacing: 12, children: [field('ka', 'K A'), field('ta', 'T A, с'), field('la', 'L A, с')]),
      const SizedBox(height: 16),
      const Text('Ветвь B: FOPDT', style: TextStyle(fontWeight: FontWeight.bold)),
      const SizedBox(height: 8),
      Wrap(spacing: 8, runSpacing: 12, children: [field('kb', 'K B'), field('tb', 'T B, с'), field('lb', 'L B, с')]),
      const SizedBox(height: 16),
      const Text('Регулятор B и возмущение A', style: TextStyle(fontWeight: FontWeight.bold)),
      const SizedBox(height: 8),
      Wrap(spacing: 8, runSpacing: 12, children: [
        field('pb', 'PB, %'), field('ti', 'Ti, с'), field('rate', 'MV B, %/с'),
        field('duration', 'Время, с'), field('faultAt', 'Начало, с'),
        field('amplitude', 'Амплитуда MV A, %'), field('period', 'Период, с'),
        field('filter', 'Фильтр PV, с'), field('ff', 'FF, 0–1'),
      ]),
      const SizedBox(height: 16),
      FilledButton.icon(onPressed: busy ? null : calculate,
        icon: const Icon(Icons.play_arrow), label: const Text('Сравнить 3 стратегии')),
      if (busy) const LinearProgressIndicator(),
      if (error != null) Padding(padding: const EdgeInsets.all(8),
        child: Text(error!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
      if (runs != null) ...[
        const SizedBox(height: 20),
        const Text('Результаты по стратегиям', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        SingleChildScrollView(scrollDirection: Axis.horizontal, child: DataTable(columns: const [
          DataColumn(label: Text('Стратегия')), DataColumn(label: Text('IAE')),
          DataColumn(label: Text('Макс. |e|')), DataColumn(label: Text('Ход MV B')),
          DataColumn(label: Text('Макс. скорость B')),
        ], rows: runs!.map((r) => DataRow(cells: [
          DataCell(Text(names[r['strategy']] ?? '${r['strategy']}')),
          DataCell(Text((r['iae'] as num).toStringAsFixed(2))),
          DataCell(Text((r['maxError'] as num).toStringAsFixed(2))),
          DataCell(Text((r['travel'] as num).toStringAsFixed(2))),
          DataCell(Text((r['rate'] as num).toStringAsFixed(2))),
        ])).toList())),
        const SizedBox(height: 12),
        DropdownButtonFormField<int>(value: signal,
          decoration: const InputDecoration(labelText: 'График', border: OutlineInputBorder()),
          items: [for (var i = 0; i < signals.length; i++)
            DropdownMenuItem(value: i, child: Text(signals[i]))],
          onChanged: (v) { if (v != null) setState(() => signal = v); }),
        const SizedBox(height: 12),
        DropdownButtonFormField<int>(value: selected,
          decoration: const InputDecoration(labelText: 'Стратегия для ветвей/MV/FF', border: OutlineInputBorder()),
          items: [for (var i = 0; i < runs!.length; i++)
            DropdownMenuItem(value: i, child: Text(names[runs![i]['strategy']] ?? 'Стратегия $i'))],
          onChanged: (v) { if (v != null) setState(() => selected = v); }),
        const SizedBox(height: 12),
        SizedBox(height: 320, child: Card(child: Padding(padding: const EdgeInsets.all(12),
          child: CustomPaint(painter: _DualValvePainter(runs!, signal, selected))))),
        const SizedBox(height: 12),
        const Text('На графике суммарного расхода три стратегии показаны вместе. '
          'На остальных графиках показана выбранная стратегия.'),
        const SizedBox(height: 8),
        const Text('Внимание: FF воздействует после PI. Внутренний anti-windup не отслеживает '
          'полный MV после FF. Не переносить настройки в действующую DCS без проверки.'),
      ],
    ]),
  );
}

class _DualValvePainter extends CustomPainter {
  final List<Map<String, dynamic>> runs;
  final int signal, selected;
  _DualValvePainter(this.runs, this.signal, this.selected);
  @override
  void paint(Canvas canvas, Size size) {
    final series = <(String, List<List<double>>, int, Color)>[];
    List<List<double>> points(Map<String, dynamic> r) =>
      (r['points'] as List).map((e) => (e as List).map((n) => (n as num).toDouble()).toList()).toList();
    final colors = [Colors.teal, Colors.deepOrange, Colors.indigo];
    if (signal == 0) {
      for (var i = 0; i < runs.length; i++) {
        series.add((names[runs[i]['strategy']] ?? '$i', points(runs[i]), 2, colors[i % colors.length]));
      }
      series.add(('SP', points(runs.first), 1, Colors.grey));
    } else {
      final p = points(runs[selected]);
      if (signal == 1) {
        series.add(('Flow A', p, 3, Colors.teal));
        series.add(('Flow B', p, 4, Colors.deepOrange));
      } else if (signal == 2) {
        series.add(('MV A', p, 5, Colors.teal));
        series.add(('MV B', p, 6, Colors.deepOrange));
      } else {
        series.add(('FF MV', p, 7, Colors.indigo));
      }
    }
    if (series.isEmpty || series.first.$2.length < 2) return;
    final area = Rect.fromLTWH(48, 12, math.max(1, size.width - 62), math.max(1, size.height - 70));
    final values = series.expand((s) => s.$2.map((p) => p[s.$3])).toList();
    var lo = values.reduce(math.min), hi = values.reduce(math.max);
    if ((hi - lo).abs() < 1e-8) { lo -= 1; hi += 1; }
    final maxT = series.first.$2.last[0];
    final axis = Paint()..color = Colors.grey..strokeWidth = 1;
    canvas.drawLine(area.topLeft, area.bottomLeft, axis);
    canvas.drawLine(area.bottomLeft, area.bottomRight, axis);
    final tp = TextPainter(textDirection: TextDirection.ltr);
    for (var i = 0; i <= 4; i++) {
      final y = area.bottom - i * area.height / 4;
      canvas.drawLine(Offset(area.left, y), Offset(area.right, y),
        Paint()..color = Colors.grey.withOpacity(0.2));
      tp.text = TextSpan(text: (lo + i * (hi - lo) / 4).toStringAsFixed(1),
        style: const TextStyle(color: Colors.grey, fontSize: 10));
      tp.layout(); tp.paint(canvas, Offset(0, y - 6));
    }
    for (var i = 0; i < series.length; i++) {
      final s = series[i];
      final path = Path();
      for (var j = 0; j < s.$2.length; j++) {
        final p = s.$2[j];
        final xy = Offset(area.left + area.width * p[0] / maxT,
          area.bottom - area.height * (p[s.$3] - lo) / (hi - lo));
        if (j == 0) { path.moveTo(xy.dx, xy.dy); } else { path.lineTo(xy.dx, xy.dy); }
      }
      canvas.drawPath(path, Paint()..color = s.$4..strokeWidth = 1.8..style = PaintingStyle.stroke);
      tp.text = TextSpan(text: s.$1, style: TextStyle(fontSize: 11, color: s.$4));
      tp.layout(); tp.paint(canvas, Offset(area.left + (i % 2) * 155, area.bottom + 10 + (i ~/ 2) * 16));
    }
  }
  @override
  bool shouldRepaint(covariant _DualValvePainter old) =>
      old.runs != runs || old.signal != signal || old.selected != selected;
}

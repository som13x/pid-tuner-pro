import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:pid_tuner_pro_core/auto_tune.dart';
import 'package:pid_tuner_pro_core/dcs_controller_profiles.dart';
import 'package:pid_tuner_pro_core/centum_pid_simulator.dart';
import 'package:pid_tuner_pro_core/closed_loop_studio.dart';

// Runs entirely offline in a worker isolate; results are plain JSON-compatible maps.
List<Map<String, dynamic>> _simulateWorker(Map<String, double> p) {
  final plant = Plant(gain: p['k']!, tau: p['tau']!, delay: p['delay']!);
  final config = CentumPidConfig(pb: p['pb']!, ti: p['ti']!, td: p['td']!,
    dt: 0.2, maxMvRate: p['rate']!,
    pvFilterSeconds: p['pvFilter']!,
    derivativeFilterSeconds: p['dFilter']!);
  final scenario = LoopScenario(duration: p['duration']!, dt: 0.2,
    disturbanceAt: p['disturbanceAt']!, disturbanceMagnitude: p['disturbance']!,
    manualUntil: p['manualUntil']!, manualMv: 50);
  return ClosedLoopStudio.compareStructures(plant, config, scenario).map((run) => {
    'structure': run.controller.structure.name,
    'iae': run.metrics.iae, 'maxError': run.metrics.maxAbsError,
    'travel': run.metrics.totalMvTravel, 'rate': run.metrics.maxObservedMvRate,
    'finalError': run.metrics.finalError,
    'points': run.points.map((pt) => [pt.t, pt.sp, pt.pv, pt.mv, pt.filteredPv]).toList(),
  }).toList();
}

class SimulationScreen extends StatefulWidget {
  final Map<String, double>? initialModel;
  final DcsControllerProfile? profile;
  const SimulationScreen({super.key, this.initialModel, this.profile});
  @override
  State<SimulationScreen> createState() => _SimulationScreenState();
}

class _SimulationScreenState extends State<SimulationScreen> {
  late final Map<String, TextEditingController> fields;
  List<Map<String, dynamic>>? results;
  String? error;
  bool busy = false;
  bool showMv = false;
  bool showFilteredPv = false;
  String algorithm = 'compare';
  @override
  void initState() {
    super.initState();
    final m = widget.initialModel;
    final values = <String, double>{
      'k': m?['K'] ?? 1, 'tau': m?['T'] ?? 15, 'delay': m?['L'] ?? 3,
      'pb': 120, 'ti': 20, 'td': 0, 'rate': 5,
      'pvFilter': 0, 'dFilter': 1,
      'duration': 240, 'disturbanceAt': 40, 'disturbance': 6,
      'manualUntil': 0,
    };
    fields = values.map((k, v) => MapEntry(k, TextEditingController(text: '$v')));
  }
  @override
  void dispose() { for (final f in fields.values) { f.dispose(); } super.dispose(); }
  Future<void> run() async {
    final inputs = <String, double>{};
    for (final entry in fields.entries) {
      final value = double.tryParse(entry.value.text.trim().replaceAll(',', '.'));
      if (value == null || !value.isFinite) {
        setState(() => error = 'Некорректное число: ${entry.key}'); return;
      }
      inputs[entry.key] = value;
    }
    if (inputs['duration']! > 1800 || inputs['duration']! < 1 ||
        inputs['tau']! <= 0 || inputs['pb']! <= 0 || inputs['ti']! <= 0 ||
        inputs['delay']! < 0 || inputs['td']! < 0 || inputs['rate']! <= 0 ||
        inputs['pvFilter']! < 0 || inputs['dFilter']! <= 0 ||
        inputs['manualUntil']! < 0 || inputs['manualUntil']! > inputs['duration']! ||
        inputs['disturbanceAt']! < 0 || inputs['tau']! < 0.4) {
      setState(() => error = 'Проверьте диапазоны: T ≥ 0.4 с, время 1–1800 с, PB/Ti > 0; PV фильтр ≥ 0, D фильтр > 0'); return;
    }
    setState(() { busy = true; error = null; results = null; });
    try {
      final r = await compute(_simulateWorker, inputs);
      if (mounted) setState(() => results = r);
    } catch (e) {
      if (mounted) setState(() => error = 'Ошибка расчёта: $e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }
  Widget field(String key, String label) => SizedBox(width: 145,
    child: TextField(controller: fields[key], keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
      decoration: InputDecoration(labelText: label, border: const OutlineInputBorder(), isDense: true)));
  @override
  Widget build(BuildContext context) {
    final visibleResults = results == null ? null : algorithm == 'compare'
      ? results! : results!.where((r) => r['structure'] == algorithm).toList();
    return Scaffold(
    appBar: AppBar(title: const Text('Closed-Loop Simulation')),
    body: ListView(padding: const EdgeInsets.all(16), children: [
      const Text('Модель FOPDT и параметры PID', style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold)),
      if (widget.profile != null) Text('Профиль проекта: ' + widget.profile!.title +
        '. Симуляция остаётся универсальной, а не моделью фирменного блока.',
        style: const TextStyle(color: Colors.deepOrange)),
      const SizedBox(height: 12),
      Wrap(spacing: 10, runSpacing: 12, children: [
        field('k', 'K (%/% )'), field('tau', 'T, с'), field('delay', 'L, с'),
        field('pb', 'PB, %'), field('ti', 'Ti, с'), field('td', 'Td, с'),
        field('pvFilter', 'PV-фильтр, с (0=выкл)'),
        field('dFilter', 'D-фильтр, с'),
        field('rate', 'Макс. MV, %/с'), field('duration', 'Длительность, с'),
        field('disturbanceAt', 'Возмущение с, с'), field('disturbance', 'Возмущение, %'),
        field('manualUntil', 'MAN до, с'),
      ]),
      const SizedBox(height: 8),
      const Text('PV-фильтр: инерционное звено 1-го порядка перед расчётом P/I/D. '
          'Уменьшает шум, но добавляет запаздывание и может ухудшить регулирование. '
          'Нулевое значение отключает фильтрацию.'),
      const SizedBox(height: 14),
      DropdownButtonFormField<String>(
        value: algorithm,
        decoration: const InputDecoration(labelText: 'Структура алгоритма'),
        items: const [
          DropdownMenuItem(value: 'compare', child: Text('Сравнить PID / PI-D / I-PD')),
          DropdownMenuItem(value: 'pid', child: Text('PID: P, I, D по ошибке')),
          DropdownMenuItem(value: 'piD', child: Text('PI-D: D по PV')),
          DropdownMenuItem(value: 'iPd', child: Text('I-PD: P и D по PV')),
        ],
        onChanged: busy ? null : (value) {
          if (value != null) setState(() => algorithm = value);
        },
      ),
      const SizedBox(height: 6),
      const Text('AUTO/MAN здесь означает режим регулятора, '
          'а не автоматический выбор алгоритма CENTUM VP. '
          'Структуры являются приближёнными математическими моделями.'),
      const SizedBox(height: 14),
      FilledButton.icon(onPressed: busy ? null : run,
        icon: const Icon(Icons.play_arrow), label: const Text('Рассчитать выбранную структуру')),
      if (busy) const LinearProgressIndicator(),
      if (error != null) Padding(padding: const EdgeInsets.all(8),
        child: Text(error!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
      if (visibleResults != null) ...[
        const SizedBox(height: 20),
        const Text('Сравнение структур', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        SingleChildScrollView(scrollDirection: Axis.horizontal, child: DataTable(columns: const [
          DataColumn(label: Text('Структура')), DataColumn(label: Text('IAE')),
          DataColumn(label: Text('Макс. |e|')), DataColumn(label: Text('Ход MV')),
          DataColumn(label: Text('Ошибка в конце')),
        ], rows: visibleResults.map((r) => DataRow(cells: [
          DataCell(Text('${r['structure']}')), DataCell(Text((r['iae'] as double).toStringAsFixed(1))),
          DataCell(Text((r['maxError'] as double).toStringAsFixed(2))),
          DataCell(Text((r['travel'] as double).toStringAsFixed(1))),
          DataCell(Text((r['finalError'] as double).toStringAsFixed(2))),
        ])).toList())),
        SwitchListTile(title: Text(showMv ? 'График MV' : 'График PV / SP'),
          value: showMv, onChanged: (v) => setState(() => showMv = v)),
        if (!showMv) SwitchListTile(
          title: const Text('Показывать PV после фильтра вместо измеренной PV'),
          subtitle: const Text('Показатели IAE и ошибка рассчитываются по измеренной PV'),
          value: showFilteredPv,
          onChanged: (v) => setState(() => showFilteredPv = v)),
        SizedBox(height: 320, child: Card(child: Padding(padding: const EdgeInsets.all(12),
          child: CustomPaint(painter: _SimulationPainter(visibleResults, showMv,
            showFilteredPv))))),
        const SizedBox(height: 10),
        const Text('Сигналы нормированы в % шкалы. Возмущение добавляется к PV. '
          'Расчёт является приближённой моделью, не эмулятором PID-блоков Yokogawa, Siemens или ABB.'),
      ],
    ]),
  );
  }
}

class _SimulationPainter extends CustomPainter {
  final List<Map<String, dynamic>> runs;
  final bool mv;
  final bool filteredPv;
  _SimulationPainter(this.runs, this.mv, this.filteredPv);
  @override
  void paint(Canvas canvas, Size size) {
    final area = Rect.fromLTWH(44, 16, math.max(1, size.width - 60), math.max(1, size.height - 50));
    final sets = runs.map((r) => (r['points'] as List).cast<List>()).toList();
    final all = sets.expand((e) => e).toList();
    if (all.length < 2) return;
    final index = mv ? 3 : (filteredPv ? 4 : 2);
    final values = all.map((e) => (e[index] as num).toDouble()).toList();
    if (!mv) values.addAll(all.map((e) => (e[1] as num).toDouble()));
    var lo = values.reduce(math.min), hi = values.reduce(math.max);
    if ((hi - lo).abs() < 1e-8) { lo -= 1; hi += 1; }
    final tMax = (all.last[0] as num).toDouble();
    final axis = Paint()..color = Colors.grey..strokeWidth = 1;
    canvas.drawLine(area.bottomLeft, area.topLeft, axis);
    canvas.drawLine(area.bottomLeft, area.bottomRight, axis);
    final tp = TextPainter(textDirection: TextDirection.ltr);
    for (var i = 0; i <= 4; i++) {
      final y = area.bottom - area.height * i / 4;
      canvas.drawLine(Offset(area.left, y), Offset(area.right, y), Paint()..color = Colors.grey.withOpacity(0.2));
      tp.text = TextSpan(text: (lo + (hi - lo) * i / 4).toStringAsFixed(1),
        style: const TextStyle(fontSize: 10, color: Colors.grey));
      tp.layout(); tp.paint(canvas, Offset(0, y - 6));
    }
    Offset point(List<dynamic> p, int idx) => Offset(
      area.left + area.width * (p[0] as num).toDouble() / tMax,
      area.bottom - area.height * ((p[idx] as num).toDouble() - lo) / (hi - lo));
    final colors = [Colors.teal, Colors.deepOrange, Colors.indigo];
    for (var j = 0; j < sets.length; j++) {
      final path = Path()..moveTo(point(sets[j].first, index).dx, point(sets[j].first, index).dy);
      for (final p in sets[j].skip(1)) { final xy = point(p, index); path.lineTo(xy.dx, xy.dy); }
      canvas.drawPath(path, Paint()..color = colors[j % colors.length]
        ..strokeWidth = 1.8..style = PaintingStyle.stroke);
      tp.text = TextSpan(text: '${runs[j]['structure']}', style: TextStyle(fontSize: 11, color: colors[j % colors.length]));
      tp.layout(); tp.paint(canvas, Offset(area.left + j * 72, area.bottom + 12));
    }
    if (!mv) {
      final path = Path()..moveTo(point(sets.first.first, 1).dx, point(sets.first.first, 1).dy);
      for (final p in sets.first.skip(1)) { final xy = point(p, 1); path.lineTo(xy.dx, xy.dy); }
      canvas.drawPath(path, Paint()..color = Colors.black54..strokeWidth = 1
        ..style = PaintingStyle.stroke);
    }
  }
  @override
  bool shouldRepaint(covariant _SimulationPainter old) => old.mv != mv ||
    old.filteredPv != filteredPv || old.runs != runs;
}

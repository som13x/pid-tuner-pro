import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:pid_tuner_pro_core/auto_tune.dart';
import 'package:pid_tuner_pro_core/cascade_circuit.dart';

/// Offline two-loop simulation; only primitive values cross the isolate.
Map<String, dynamic> circuitWorker(Map<String, dynamic> message) {
  final x = Map<String, double>.from(message['parameters'] as Map);
  final wiring = CircuitWiring.fromJson(
    Map<String, dynamic>.from(message['wiring'] as Map));
  final run = CascadeCircuitSimulator.simulate(
    CascadeCircuitConfig(
      flow: Plant(gain: x['flowK']!, tau: x['flowT']!, delay: x['flowL']!),
      temperature: Plant(
        gain: x['tempK']!, tau: x['tempT']!, delay: x['tempL']!),
      ticPb: x['ticPb']!, ticTi: x['ticTi']!,
      ficPb: x['ficPb']!, ficTi: x['ficTi']!,
      duration: x['duration']!, stepAt: x['stepAt']!,
      stepAmplitude: x['step']!, lagSeconds: x['lag']!,
      actuatorSeconds: x['actuator']!,
      flowDisturbanceAt: x['disturbanceAt']!,
      flowDisturbance: x['disturbance']!,
    ), wiring);
  return <String, dynamic>{
    'temperatureIae': run.metrics.temperatureIae,
    'flowIae': run.metrics.flowIae,
    'mvTravel': run.metrics.totalMvTravel,
    'rows': run.points.map((p) => <double?>[
      p.t, p.ticSp, p.ticPv, p.ticMv, p.ficSv, p.ficPv,
      p.ficMv, p.actualMv, p.ticRl1, p.ficRl1,
    ]).toList(),
  };
}

class CircuitStudioScreen extends StatefulWidget {
  final String? loopTag;
  final Map<String, dynamic>? initialWiring;
  final Future<void> Function(Map<String, dynamic> wiring)? onSave;

  const CircuitStudioScreen({
    super.key, this.loopTag, this.initialWiring, this.onSave,
  });

  @override
  State<CircuitStudioScreen> createState() => _CircuitStudioScreenState();
}

class _CircuitStudioScreenState extends State<CircuitStudioScreen> {
  late CircuitWiring wiring;
  late final Map<String, TextEditingController> fields;
  Map<String, dynamic>? result;
  String? error;
  bool running = false;
  bool saving = false;
  int selectedTab = 0;
  int selectedChart = 0;

  @override
  void initState() {
    super.initState();
    wiring = CircuitWiring(CircuitWiring.initial);
    if (widget.initialWiring != null) {
      try {
        wiring = CircuitWiring.fromJson(widget.initialWiring!);
      } catch (e) {
        error = 'Сохранённая схема повреждена: ' + e.toString();
      }
    }
    final defaults = <String, double>{
      'tempK': 0.8, 'tempT': 17, 'tempL': 3,
      'flowK': 0.8, 'flowT': 5, 'flowL': 1,
      'ticPb': 180, 'ticTi': 45, 'ficPb': 110, 'ficTi': 12,
      'duration': 180, 'stepAt': 30, 'step': 5,
      'lag': 2, 'actuator': 1,
      'disturbanceAt': 90, 'disturbance': 2,
    };
    fields = defaults.map((k, v) =>
      MapEntry(k, TextEditingController(text: v.toString())));
  }

  @override
  void dispose() {
    for (final controller in fields.values) { controller.dispose(); }
    super.dispose();
  }

  void toggle(CircuitLink link, bool enabled) {
    try {
      final next = wiring.toggle(link, enabled);
      next.validate();
      setState(() { wiring = next; result = null; error = null; });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Несовместимая связь: ' + e.toString())));
    }
  }

  Future<void> save() async {
    final callback = widget.onSave;
    if (callback == null || saving) return;
    setState(() => saving = true);
    try {
      wiring.validate();
      await callback(wiring.toJson());
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Схема сохранена в истории контура')));
    } catch (e) {
      if (mounted) setState(() => error = 'Ошибка сохранения: ' + e.toString());
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  Future<void> simulate() async {
    if (running) return;
    final x = <String, double>{};
    for (final item in fields.entries) {
      final value = double.tryParse(item.value.text.trim().replaceAll(',', '.'));
      if (value == null || !value.isFinite) {
        setState(() => error = 'Неверное число: ' + item.key);
        return;
      }
      x[item.key] = value;
    }
    setState(() { running = true; result = null; error = null; });
    try {
      final data = await compute(circuitWorker, <String, dynamic>{
        'parameters': x, 'wiring': wiring.toJson(),
      });
      if (mounted) setState(() { result = data; selectedTab = 2; });
    } catch (e) {
      if (mounted) setState(() => error = 'Не удалось рассчитать: ' + e.toString());
    } finally {
      if (mounted) setState(() => running = false);
    }
  }

  Widget number(String id, String label) => SizedBox(
    width: 142,
    child: TextField(
      controller: fields[id],
      keyboardType: const TextInputType.numberWithOptions(
        decimal: true, signed: true),
      decoration: InputDecoration(labelText: label, isDense: true,
        border: const OutlineInputBorder()),
    ),
  );

  Widget diagram() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Text('Каскад TIC1 → FIC1',
        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
      const SizedBox(height: 8),
      const Text('Масштабируйте и перемещайте схему двумя пальцами. '
        'Синие линии участвуют в расчёте каскада, '
        'оранжевые и фиолетовые показывают мониторинг сигналов.'),
      const SizedBox(height: 8),
      Container(
        height: 295,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(12)),
        child: InteractiveViewer(
          constrained: false,
          boundaryMargin: const EdgeInsets.all(65),
          minScale: 0.55, maxScale: 3,
          child: CustomPaint(
            size: const Size(555, 270),
            painter: _CircuitPainter(wiring),
          ),
        ),
      ),
      const SizedBox(height: 12),
      Text('Активных связей: ' + wiring.links.length.toString()),
      for (final link in wiring.links)
        Padding(padding: const EdgeInsets.only(top: 5),
          child: Row(children: [
            const Icon(Icons.arrow_forward, size: 15),
            const SizedBox(width: 8),
            Expanded(child: Text(link.label)),
          ])),
      const SizedBox(height: 10),
      const Text('RL1 показан как контрольная точка. Его влияние на PID '
        'не включено без подтверждения назначения терминала '
        'конкретного блока CENTUM VP.',
        style: TextStyle(color: Colors.deepOrange)),
    ],
  );

  Widget connections() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Text('Редактор соединений',
        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
      const SizedBox(height: 8),
      const Text('Включайте или отключайте допустимые связи. '
        'Два источника на один вход и LAG.OUT без LAG.IN запрещены.'),
      const SizedBox(height: 12),
      for (final link in CircuitWiring.catalogue)
        Card(child: SwitchListTile(
          title: Text(link.label),
          subtitle: Text(link == CircuitWiring.cascade
            ? 'Рабочая каскадная связь MV → SV'
            : link == CircuitWiring.pvToLag
              ? 'Источник сигнала для блока LAG'
              : link == CircuitWiring.lagToTicRl
                ? 'Контрольная точка RL1 после фильтра'
                : link == CircuitWiring.directPvRl
                  ? 'Альтернатива без LAG, только наблюдение'
                  : 'Контрольная точка RL1 по фактическому MV AS-M'),
          value: wiring.contains(link),
          onChanged: (value) => toggle(link, value),
        )),
      const SizedBox(height: 8),
      const Text('Подключения RL1 в этом редакторе НЕ трактуются '
        'как external reset, PID tracking или алгоритмическая обратная связь.'),
    ],
  );

  Widget trends() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Text('Настройки расчётной модели',
        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
      const SizedBox(height: 8),
      const Text('Два отдельных демонстрационных процесса FOPDT. '
        'Сохранённая модель одиночного контура автоматически не назначается '
        'температурной или расходной ветви каскада.'),
      const SizedBox(height: 12),
      const Text('FIC: MV → расход', style: TextStyle(fontWeight: FontWeight.bold)),
      const SizedBox(height: 8),
      Wrap(spacing: 8, runSpacing: 12, children: [
        number('flowK', 'K расхода'),
        number('flowT', 'T расхода, с'),
        number('flowL', 'L расхода, с'),
        number('ficPb', 'FIC PB, %'),
        number('ficTi', 'FIC Ti, с'),
      ]),
      const SizedBox(height: 16),
      const Text('TIC: расход → температура',
        style: TextStyle(fontWeight: FontWeight.bold)),
      const SizedBox(height: 8),
      Wrap(spacing: 8, runSpacing: 12, children: [
        number('tempK', 'K температуры'),
        number('tempT', 'T температуры, с'),
        number('tempL', 'L температуры, с'),
        number('ticPb', 'TIC PB, %'),
        number('ticTi', 'TIC Ti, с'),
      ]),
      const SizedBox(height: 16),
      const Text('Возмущения, фильтрация и привод',
        style: TextStyle(fontWeight: FontWeight.bold)),
      const SizedBox(height: 8),
      Wrap(spacing: 8, runSpacing: 12, children: [
        number('duration', 'Время, с'),
        number('stepAt', 'Ступень SP, с'),
        number('step', 'ΔSP TIC, %'),
        number('lag', 'LAG, с'),
        number('actuator', 'Привод AS-M, с'),
        number('disturbanceAt', 'Возмущение, с'),
        number('disturbance', 'Δ расхода, %'),
      ]),
      const SizedBox(height: 14),
      if (result != null) ...[
        const Divider(),
        Text('TIC IAE: ' +
          (result!['temperatureIae'] as num).toStringAsFixed(1) +
          '   FIC IAE: ' +
          (result!['flowIae'] as num).toStringAsFixed(1)),
        Text('Суммарный ход MV FIC: ' +
          (result!['mvTravel'] as num).toStringAsFixed(1) + ' %'),
        const SizedBox(height: 10),
        DropdownButtonFormField<int>(
          value: selectedChart,
          decoration: const InputDecoration(labelText: 'График'),
          items: const [
            DropdownMenuItem(value: 0, child: Text('TIC1: SP / PV')),
            DropdownMenuItem(value: 1, child: Text('FIC1: SV / PV')),
            DropdownMenuItem(value: 2, child: Text('MV TIC/FIC/AS-M')),
            DropdownMenuItem(value: 3, child: Text('Мониторинг RL1')),
          ],
          onChanged: (v) {
            if (v != null) setState(() => selectedChart = v);
          },
        ),
        const SizedBox(height: 10),
        SizedBox(height: 320, child: Card(
          child: Padding(padding: const EdgeInsets.all(12),
            child: CustomPaint(painter: _CircuitTrendPainter(
              result!['rows'] as List, selectedChart),
              child: const SizedBox.expand()),
          ),
        )),
        const SizedBox(height: 8),
        const Text('Тренды синтетические. Параметры модели и связи '
          'не отправляются в реальную DCS.'),
      ],
    ],
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(widget.loopTag == null
        ? 'Circuit Studio' : 'Circuit · ' + widget.loopTag!),
      actions: [
        if (widget.onSave != null) IconButton(
          tooltip: 'Сохранить схему',
          onPressed: saving ? null : save,
          icon: const Icon(Icons.save_outlined)),
      ],
    ),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text('PID Tuner Pro · Circuit Studio v2.8',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        const SizedBox(height: 6),
        const Text('Упрощённый офлайн-редактор. Реализация фирменных '
          'RL1/RL2, внешнего reset и реального подключения DCS '
          'не подтверждена.'),
        const SizedBox(height: 12),
        Wrap(spacing: 8, runSpacing: 6, children: [
          ChoiceChip(label: const Text('Схема'),
            selected: selectedTab == 0,
            onSelected: (_) => setState(() => selectedTab = 0)),
          ChoiceChip(label: const Text('Связи'),
            selected: selectedTab == 1,
            onSelected: (_) => setState(() => selectedTab = 1)),
          ChoiceChip(label: const Text('Тренды'),
            selected: selectedTab == 2,
            onSelected: (_) => setState(() => selectedTab = 2)),
        ]),
        const SizedBox(height: 14),
        if (selectedTab == 0) diagram(),
        if (selectedTab == 1) connections(),
        if (selectedTab == 2) trends(),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: running ? null : simulate,
          icon: const Icon(Icons.play_arrow),
          label: Text(running ? 'Моделирование…'
            : 'Рассчитать каскад TIC/FIC'),
        ),
        if (running) const LinearProgressIndicator(),
        if (widget.onSave != null) Padding(
          padding: const EdgeInsets.only(top: 8),
          child: OutlinedButton.icon(
            onPressed: saving ? null : save,
            icon: const Icon(Icons.save_outlined),
            label: Text(saving ? 'Сохранение…' : 'Сохранить схему в проект'),
          ),
        ),
        if (widget.onSave == null) const Padding(
          padding: EdgeInsets.only(top: 8),
          child: Text('Демонстрационный запуск: схема хранится '
            'только до закрытия экрана.'),
        ),
        if (error != null) Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Text(error!, style: TextStyle(
            color: Theme.of(context).colorScheme.error)),
        ),
      ],
    ),
  );
}

class _CircuitPainter extends CustomPainter {
  final CircuitWiring wiring;
  _CircuitPainter(this.wiring);

  @override
  void paint(Canvas canvas, Size size) {
    void node(Rect r, String title, String detail, Color fill, Color outline) {
      canvas.drawRRect(RRect.fromRectAndRadius(r, const Radius.circular(12)),
        Paint()..color = fill);
      canvas.drawRRect(RRect.fromRectAndRadius(r, const Radius.circular(12)),
        Paint()..color = outline..style = PaintingStyle.stroke
          ..strokeWidth = 1.8);
      void text(String value, double y, double font, FontWeight weight) {
        final tp = TextPainter(
          text: TextSpan(text: value, style: TextStyle(
            fontSize: font, fontWeight: weight, color: Colors.black87)),
          textDirection: TextDirection.ltr)..layout();
        tp.paint(canvas, Offset(r.center.dx - tp.width / 2, y));
      }
      text(title, r.top + 14, 16, FontWeight.bold);
      text(detail, r.top + 40, 10, FontWeight.normal);
    }

    void wire(CircuitLink link, List<Offset> pathPoints, Color color) {
      if (!wiring.contains(link)) return;
      final path = Path()..moveTo(pathPoints.first.dx, pathPoints.first.dy);
      for (final p in pathPoints.skip(1)) { path.lineTo(p.dx, p.dy); }
      canvas.drawPath(path, Paint()
        ..color = color..strokeWidth = 2.5
        ..style = PaintingStyle.stroke);
      final end = pathPoints.last;
      final previous = pathPoints[pathPoints.length - 2];
      final angle = math.atan2(end.dy - previous.dy, end.dx - previous.dx);
      const arrow = 8.0;
      final left = Offset(end.dx - arrow * math.cos(angle - 0.5),
        end.dy - arrow * math.sin(angle - 0.5));
      final right = Offset(end.dx - arrow * math.cos(angle + 0.5),
        end.dy - arrow * math.sin(angle + 0.5));
      canvas.drawPath(Path()..moveTo(left.dx, left.dy)
        ..lineTo(end.dx, end.dy)..lineTo(right.dx, right.dy),
        Paint()..color = color..style = PaintingStyle.stroke..strokeWidth = 2.5);
    }

    wire(CircuitWiring.cascade,
      const [Offset(170, 60), Offset(318, 60)], Colors.blue);
    wire(CircuitWiring.pvToLag,
      const [Offset(480, 100), Offset(511, 100),
        Offset(511, 184), Offset(460, 184)], Colors.deepOrange);
    wire(CircuitWiring.lagToTicRl,
      const [Offset(322, 184), Offset(252, 184),
        Offset(252, 127), Offset(100, 127),
        Offset(100, 107)], Colors.deepOrange);
    wire(CircuitWiring.directPvRl,
      const [Offset(480, 92), Offset(536, 92),
        Offset(536, 137), Offset(95, 137),
        Offset(95, 107)], Colors.deepOrange);
    wire(CircuitWiring.actualMvRl,
      const [Offset(165, 222), Offset(285, 222),
        Offset(285, 94), Offset(318, 94)], Colors.deepPurple);

    node(const Rect.fromLTWH(30, 20, 140, 87), 'TIC1',
      'Temperature PID · MV', const Color(0xFFE1F0FC), Colors.blue);
    node(const Rect.fromLTWH(318, 20, 162, 87), 'FIC1',
      'Flow PID · SV / PV', const Color(0xFFE1F0FC), Colors.blue);
    node(const Rect.fromLTWH(322, 157, 138, 61), 'LAG',
      'T = configurable', const Color(0xFFFFECD5), Colors.deepOrange);
    node(const Rect.fromLTWH(30, 193, 135, 61), 'AS-M',
      'Actual MV monitor', const Color(0xFFF1E7FA), Colors.deepPurple);
  }

  @override
  bool shouldRepaint(covariant _CircuitPainter old) => old.wiring != wiring;
}

class _CircuitTrendPainter extends CustomPainter {
  final List rows;
  final int chart;
  _CircuitTrendPainter(this.rows, this.chart);

  @override
  void paint(Canvas canvas, Size size) {
    if (rows.length < 2) return;
    final traces = <(int, String, Color)>[];
    if (chart == 0) {
      traces.add((1, 'TIC.SP', Colors.blueGrey));
      traces.add((2, 'TIC.PV', Colors.teal));
    } else if (chart == 1) {
      traces.add((4, 'FIC.SV', Colors.blueGrey));
      traces.add((5, 'FIC.PV', Colors.teal));
    } else if (chart == 2) {
      traces.add((3, 'TIC.MV', Colors.orange));
      traces.add((6, 'FIC.MV', Colors.teal));
      traces.add((7, 'AS-M.MV', Colors.indigo));
    } else {
      traces.add((8, 'TIC.RL1', Colors.deepOrange));
      traces.add((9, 'FIC.RL1', Colors.deepPurple));
    }
    final active = traces.where((trace) =>
      rows.any((r) => (r as List)[trace.$1] != null)).toList();
    if (active.isEmpty) return;
    final values = active.expand((trace) => rows
      .map((r) => (r as List)[trace.$1])
      .whereType<num>().map((v) => v.toDouble())).toList();
    var minValue = values.reduce(math.min);
    var maxValue = values.reduce(math.max);
    if ((maxValue - minValue).abs() < 1e-9) {
      minValue -= 1; maxValue += 1;
    }
    const left = 43.0, top = 12.0;
    final width = math.max(1.0, size.width - left - 12);
    final height = math.max(1.0, size.height - top - 65);
    final lastT = ((rows.last as List)[0] as num).toDouble();
    final timeMax = math.max(1.0, lastT);
    Offset point(List row, int col) => Offset(
      left + width * (row[0] as num).toDouble() / timeMax,
      top + height * (1 - ((row[col] as num).toDouble() -
        minValue) / (maxValue - minValue)));
    final axisPaint = Paint()..color = Colors.grey..strokeWidth = 1;
    canvas.drawLine(const Offset(left, top),
      Offset(left, top + height), axisPaint);
    canvas.drawLine(Offset(left, top + height),
      Offset(left + width, top + height), axisPaint);
    void text(String value, Offset offset, Color color) {
      final painter = TextPainter(
        text: TextSpan(text: value, style: TextStyle(
          color: color, fontSize: 10)),
        textDirection: TextDirection.ltr)..layout();
      painter.paint(canvas, offset);
    }
    text(maxValue.toStringAsFixed(1),
      const Offset(0, top), Colors.grey);
    text(minValue.toStringAsFixed(1),
      Offset(0, top + height - 10), Colors.grey);
    text(timeMax.toStringAsFixed(0) + ' c',
      Offset(left + width - 38, top + height + 5), Colors.grey);
    for (var i = 0; i < active.length; i++) {
      final trace = active[i];
      final path = Path();
      var first = true;
      for (final r in rows) {
        final row = r as List;
        if (row[trace.$1] == null) {
          first = true;
          continue;
        }
        final xy = point(row, trace.$1);
        if (first) { path.moveTo(xy.dx, xy.dy); first = false; }
        else { path.lineTo(xy.dx, xy.dy); }
      }
      canvas.drawPath(path, Paint()
        ..color = trace.$3
        ..strokeWidth = 1.8
        ..style = PaintingStyle.stroke);
      text(trace.$2,
        Offset(left + (i % 2) * 145, top + height + 22 +
          (i ~/ 2) * 16), trace.$3);
    }
  }

  @override
  bool shouldRepaint(covariant _CircuitTrendPainter old) =>
    old.rows != rows || old.chart != chart;
}

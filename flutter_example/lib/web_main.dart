import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:pid_tuner_pro_core/auto_tune.dart';
import 'package:pid_tuner_pro_core/step_identification.dart';
import 'package:pid_tuner_pro_core/trend_csv.dart';

import 'circuit_studio_screen.dart';
import 'dual_valve_screen.dart';
import 'manual_step_form.dart';
import 'rl_tracking_screen.dart';
import 'simulation_screen.dart';
import 'stability_screen.dart';

/// Safari / Flutter Web entry point. Core solvers and existing pure Flutter
/// lab screens are reused. Native SQLite / dart:io screens are deliberately
/// excluded until a real web persistence and backup adapter is implemented.
void main() => runApp(const PidTunerWebPreview());

class PidTunerWebPreview extends StatelessWidget {
  const PidTunerWebPreview({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'PID Tuner Pro · Safari Preview',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      useMaterial3: true,
      colorSchemeSeed: Colors.teal,
      brightness: Brightness.light,
    ),
    home: const WebPreviewHome(),
  );
}

class WebPreviewHome extends StatefulWidget {
  const WebPreviewHome({super.key});

  @override
  State<WebPreviewHome> createState() => _WebPreviewHomeState();
}

class _WebPreviewHomeState extends State<WebPreviewHome> {
  int selected = 0;
  Plant? currentModel;
  String? source;
  Map<String, dynamic>? circuit;
  static const labels = [
    'Step Test', 'Auto Tune', 'Simulation', 'Circuit Studio',
    'Stability', 'RL Tracking', 'Dual Valve LNG',
  ];

  void useModel(Plant plant, String origin) {
    setState(() {
      currentModel = plant;
      source = origin;
    });
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('Модель K/T/L принята для расчётов в этой вкладке: ' +
        origin + '. Для реальной DCS требуется проверка.'),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final model = currentModel;
    final modelMap = model == null ? null : {
      'K': model.gain, 'T': model.tau, 'L': model.delay,
    };
    Widget content;
    switch (selected) {
      case 0:
        content = WebStepTest(onIdentified: useModel);
      case 1:
        content = WebAutoTune(initialPlant: model);
      case 2:
        content = SimulationScreen(initialModel: modelMap);
      case 3:
        content = CircuitStudioScreen(
          initialWiring: circuit,
          onSave: (wiring) async {
            setState(() => circuit = Map<String, dynamic>.from(wiring));
          },
        );
      case 4:
        content = StabilityScreen(initialModel: modelMap);
      case 5:
        content = RlTrackingScreen(initialModel: modelMap);
      default:
        content = const DualValveScreen();
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text('PID Tuner Pro · Web Preview'),
        backgroundColor: Theme.of(context).colorScheme.surfaceContainer,
      ),
      body: SafeArea(child: Column(children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          color: Theme.of(context).colorScheme.surfaceContainerLow,
          child: Text(
            model == null
              ? 'Браузерная версия для Safari. Данные живут только во время '
                'работы этой вкладки. SQLite и резервные копии пока не поддерживаются.'
              : 'Активная модель: K=' + model.gain.toStringAsFixed(3) +
                ', T=' + model.tau.toStringAsFixed(2) + ' с, L=' +
                model.delay.toStringAsFixed(2) + ' с. Источник: ' +
                source! + '. Хранение только в текущей вкладке.',
            style: const TextStyle(fontSize: 12),
          ),
        ),
        SizedBox(
          height: 54,
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            scrollDirection: Axis.horizontal,
            itemCount: labels.length,
            itemBuilder: (_, index) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 6),
              child: ChoiceChip(
                key: Key('web-section-' + index.toString()),
                label: Text(labels[index]),
                selected: selected == index,
                onSelected: (_) => setState(() => selected = index),
              ),
            ),
          ),
        ),
        Expanded(child: content),
      ])),
    );
  }
}

class WebStepTest extends StatefulWidget {
  final void Function(Plant plant, String source) onIdentified;

  const WebStepTest({super.key, required this.onIdentified});

  @override
  State<WebStepTest> createState() => _WebStepTestState();
}

class _WebStepTestState extends State<WebStepTest> {
  bool manualMode = true;
  final csv = TextEditingController();
  final mvHigh = TextEditingController(text: '100');
  final pvHigh = TextEditingController(text: '1000');
  final manualStepAt = TextEditingController();
  IdentificationResult? fit;
  List<TrendPoint>? measured;
  List<TrendPoint>? fitted;
  String? error;
  String? fileName;
  bool loading = false;

  @override
  void dispose() {
    csv.dispose();
    mvHigh.dispose();
    pvHigh.dispose();
    manualStepAt.dispose();
    super.dispose();
  }

  Future<void> loadCsv() async {
    setState(() => loading = true);
    try {
      final files = await FilePicker.pickFiles(
        type: FileType.custom, allowedExtensions: ['csv', 'txt'],
      );
      if (files.isEmpty) return;
      final file = files.single;
      final bytes = await file.readAsBytes();
      if (bytes.length > 10 * 1024 * 1024) {
        throw const FormatException('Файл больше 10 МБ');
      }
      final decoded = utf8.decode(bytes, allowMalformed: false);
      if (!mounted) return;
      setState(() {
        csv.text = decoded;
        fileName = file.name;
        fit = null;
        error = null;
      });
    } catch (e) {
      if (mounted) setState(() => error = 'Импорт не выполнен: ' + e.toString());
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  void identify() {
    try {
      double value(TextEditingController c) =>
        double.parse(c.text.trim().replaceAll(',', '.'));
      final points = const TrendCsv().parse(csv.text,
        mvHigh: value(mvHigh), pvHigh: value(pvHigh));
      final step = manualStepAt.text.trim();
      final result = const StepIdentifier().identify(points,
        manualStepAt: step.isEmpty ? null : value(manualStepAt));
      setState(() {
        fit = result;
        measured = points;
        fitted = fittedResponse(points, result);
        error = null;
      });
    } catch (e) {
      setState(() {
        fit = null;
        measured = null;
        fitted = null;
        error = 'Не удалось идентифицировать: ' + e.toString();
      });
    }
  }

  Widget numeric(String label, TextEditingController controller) =>
    SizedBox(width: 155, child: TextField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(
        labelText: label, border: const OutlineInputBorder(),
        isDense: true),
    ));

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(16),
    children: [
      Text('Step Test', style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 8),
      Wrap(spacing: 8, children: [
        ChoiceChip(
          label: const Text('Ручной ввод'),
          selected: manualMode,
          onSelected: (_) => setState(() => manualMode = true)),
        ChoiceChip(
          label: const Text('CSV / тренд'),
          selected: !manualMode,
          onSelected: (_) => setState(() => manualMode = false)),
      ]),
      const SizedBox(height: 14),
      if (manualMode)
        ManualStepForm(onAccept: (estimate) {
          widget.onIdentified(estimate.plant,
            'Manual Step ' + estimate.input.method.name);
        })
      else ...[
        const Text('Введите CSV time,mv,pv (секунды и инженерные '
          'единицы) либо выберите файл в Safari.'),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          onPressed: loading ? null : loadCsv,
          icon: const Icon(Icons.file_open),
          label: const Text('Выбрать CSV-файл')),
        if (fileName != null) Text('Файл: ' + fileName!),
        const SizedBox(height: 8),
        TextField(
          controller: csv, maxLines: 7,
          decoration: const InputDecoration(
            labelText: 'CSV-тренд', border: OutlineInputBorder(),
            hintText: 'time,mv,pv\n0,40,800\n1,40,800')),
        const SizedBox(height: 10),
        Wrap(spacing: 10, runSpacing: 10, children: [
          numeric('MV span high', mvHigh),
          numeric('PV span high', pvHigh),
          numeric('Время ступени, с', manualStepAt),
        ]),
        const SizedBox(height: 12),
        FilledButton(
          onPressed: identify,
          child: const Text('Идентифицировать по CSV')),
        if (error != null) Text(error!,
          style: TextStyle(color: Theme.of(context).colorScheme.error)),
        if (fit != null) ...[
          const SizedBox(height: 12),
          Text('K = ' + fit!.plant.gain.toStringAsFixed(4) +
            ', T = ' + fit!.plant.tau.toStringAsFixed(2) +
            ' с, L = ' + fit!.plant.delay.toStringAsFixed(2) + ' с',
            style: Theme.of(context).textTheme.titleMedium),
          Text('R² = ' + fit!.rSquared.toStringAsFixed(3) +
            ', NRMSE = ' + fit!.normalizedRmse.toStringAsFixed(3)),
          Text(fit!.suitableForAutoTune
            ? 'Формальные критерии качества выполнены. Нужна проверка инженера.'
            : 'Качество недостаточно для передачи в Auto Tune.'),
          if (fit!.suitableForAutoTune)
            FilledButton.icon(
              icon: const Icon(Icons.check_circle_outline),
              onPressed: () => widget.onIdentified(
                fit!.plant, 'Step Test CSV'),
              label: const Text('Принять модель для Auto Tune')),
          const Text('Измеренный и расчётный отклик PV · % шкалы'),
          SizedBox(height: 220,
            child: CustomPaint(
              painter: _WebCsvPlot(measured!, fitted!),
              child: const SizedBox.expand())),
        ],
      ],
      const SizedBox(height: 14),
      const Text('Все результаты являются оценочными. Из браузера '
        'не выполняются команды в DCS. Не меняйте настройки рабочего '
        'регулятора без инженерной проверки.'),
    ],
  );
}

class _WebCsvPlot extends CustomPainter {
  final List<TrendPoint> measured;
  final List<TrendPoint> predicted;
  _WebCsvPlot(this.measured, this.predicted);

  @override
  void paint(Canvas canvas, Size size) {
    if (measured.isEmpty || predicted.isEmpty) return;
    const x0 = 40.0, y0 = 10.0, right = 10.0, bottom = 23.0;
    final w = (size.width - x0 - right).clamp(1.0, double.infinity);
    final h = (size.height - y0 - bottom).clamp(1.0, double.infinity);
    final values = [...measured.map((p) => p.pv),
      ...predicted.map((p) => p.pv)];
    final minY = values.reduce((a, b) => a < b ? a : b);
    final maxY = values.reduce((a, b) => a > b ? a : b);
    final start = measured.first.seconds;
    final end = measured.last.seconds;
    Offset at(TrendPoint p) => Offset(
      x0 + w * (p.seconds - start) /
        (end - start).clamp(1e-9, double.infinity),
      y0 + h - h * (p.pv - minY) /
        (maxY - minY).clamp(1e-9, double.infinity),
    );
    canvas.drawLine(Offset(x0, y0), Offset(x0, y0 + h),
      Paint()..color = Colors.grey);
    canvas.drawLine(Offset(x0, y0 + h), Offset(x0 + w, y0 + h),
      Paint()..color = Colors.grey);
    void draw(List<TrendPoint> pts, Color color) {
      final path = Path();
      for (var i = 0; i < pts.length; i++) {
        final p = at(pts[i]);
        if (i == 0) { path.moveTo(p.dx, p.dy); }
        else { path.lineTo(p.dx, p.dy); }
      }
      canvas.drawPath(path, Paint()
        ..color = color
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke);
    }
    draw(measured, Colors.teal);
    draw(predicted, Colors.orange);
  }

  @override
  bool shouldRepaint(covariant _WebCsvPlot old) =>
    old.measured != measured || old.predicted != predicted;
}

List<Map<String, Object>> _autoTuneWorker(List<double> raw) {
  final plant = Plant(gain: raw[0], tau: raw[1], delay: raw[2]);
  final run = AutoTune(plant).search();
  return run.best.map((p) => <String, Object>{
    'pb': p.pb,
    'ti': p.ti,
    'iae': p.metrics.iae,
    'mvTravel': p.metrics.totalVariation,
    'maxError': p.metrics.maxError,
    'feasible': p.feasible,
  }).toList();
}

class WebAutoTune extends StatefulWidget {
  final Plant? initialPlant;
  const WebAutoTune({super.key, this.initialPlant});

  @override
  State<WebAutoTune> createState() => _WebAutoTuneState();
}

class _WebAutoTuneState extends State<WebAutoTune> {
  late final TextEditingController gain;
  late final TextEditingController tau;
  late final TextEditingController delay;
  bool busy = false;
  String? error;
  List<Map<String, Object>>? results;

  @override
  void initState() {
    super.initState();
    gain = TextEditingController(
      text: (widget.initialPlant?.gain ?? 0.8).toString());
    tau = TextEditingController(
      text: (widget.initialPlant?.tau ?? 12).toString());
    delay = TextEditingController(
      text: (widget.initialPlant?.delay ?? 3).toString());
  }

  @override
  void dispose() {
    gain.dispose();
    tau.dispose();
    delay.dispose();
    super.dispose();
  }

  Future<void> run() async {
    setState(() { busy = true; results = null; error = null; });
    try {
      double parse(TextEditingController t) =>
        double.parse(t.text.trim().replaceAll(',', '.'));
      final output = await compute(_autoTuneWorker,
        [parse(gain), parse(tau), parse(delay)]);
      if (mounted) setState(() => results = output);
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Widget number(String label, TextEditingController controller) =>
    SizedBox(width: 140, child: TextField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(
        signed: true, decimal: true),
      decoration: InputDecoration(labelText: label,
        border: const OutlineInputBorder()),
    ));

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(16),
    children: [
      Text('Auto Tune · офлайн PI',
        style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 10),
      const Text('Модель FOPDT можно передать из Step Test или '
        'ввести вручную. Это моделирование, а не запись настроек в DCS.'),
      if (widget.initialPlant != null) const Padding(
        padding: EdgeInsets.only(top: 8),
        child: Text('Получена модель из Step Test; '
          'подтвердите допустимость инженерного применения.')),
      const SizedBox(height: 14),
      Wrap(spacing: 10, runSpacing: 10, children: [
        number('K · %/%', gain),
        number('T · с', tau),
        number('L · с', delay),
      ]),
      const SizedBox(height: 14),
      FilledButton.icon(
        onPressed: busy ? null : run,
        icon: const Icon(Icons.calculate_outlined),
        label: Text(busy ? 'Расчёт…' : 'Запустить Auto Tune')),
      if (error != null) Text(error!,
        style: TextStyle(color: Theme.of(context).colorScheme.error)),
      if (results != null) ...[
        const SizedBox(height: 14),
        Text('Лучшие рассчитанные варианты PI',
          style: Theme.of(context).textTheme.titleMedium),
        if (results!.isEmpty)
          const Text('Подходящих вариантов не найдено'),
        for (final c in results!)
          Card(child: ListTile(
            title: Text('PB = ' +
              (c['pb'] as double).toStringAsFixed(2) +
              '%, Ti = ' + (c['ti'] as double).toStringAsFixed(2) + ' с'),
            subtitle: Text('IAE = ' +
              (c['iae'] as double).toStringAsFixed(2) +
              ' · Перемещение MV = ' +
              (c['mvTravel'] as double).toStringAsFixed(2) +
              '% · Max PV deviation = ' +
              (c['maxError'] as double).toStringAsFixed(2) + '%'),
            trailing: Icon(
              (c['feasible'] as bool)
                ? Icons.check_circle_outline : Icons.warning_amber_outlined),
          )),
      ],
      const SizedBox(height: 10),
      const Text('Прежде чем использовать результаты на объекте, '
        'проверьте идентификацию, устойчивость, направление действия '
        'и ограничения клапана.'),
    ],
  );
}

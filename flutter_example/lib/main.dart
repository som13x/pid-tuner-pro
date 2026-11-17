import 'stability_screen.dart';
import 'project_home.dart';
import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:pid_tuner_pro_core/auto_tune.dart';
import 'package:pid_tuner_pro_core/step_identification.dart';
import 'package:pid_tuner_pro_core/trend_csv.dart';

void main() => runApp(const PidTunerDemo());

class PidTunerDemo extends StatelessWidget {
  const PidTunerDemo({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    title: 'PID Tuner Pro',
    theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.teal),
    home: const ProjectHome(),
  );
}

/// Runs on a worker isolate; only serializable inputs/outputs cross isolates.
Map<String, dynamic> _runSearch(Map<String, dynamic> _) {
  final args = _;
  final plant = Plant(gain: (args['gain'] as num).toDouble(), tau: (args['tau'] as num).toDouble(), delay: (args['delay'] as num).toDouble());
  const config = TuneConfig();
  final result = AutoTune(plant, config).search();
  return {
    'model': {'type': 'FOPDT', 'gain': plant.gain, 'tauSeconds': plant.tau,
      'delaySeconds': plant.delay, 'verifiedForPlant': false},
    'configuration': {'priority': 'valve', 'pbRange': [40, 250],
      'tiRangeSeconds': [5, 80], 'maxMvRatePctPerSecond': 5,
      'maxPvDeviationPctSpan': 10, 'scenario': 'step',
      'baselineComparison': true},
    'evaluated': result.evaluated,
    'feasibleCount': result.feasibleCount,
    'baseline': _candidateToJson(result.baseline),
    'best': result.best.map(_candidateToJson).toList(),
  };
}

Map<String, dynamic> _candidateToJson(Candidate c) => {
  'pbPercent': c.pb, 'tiSeconds': c.ti, 'feasible': c.feasible,
  'violations': c.violations,
  'metrics': {
    'iae': c.metrics.iae, 'ise': c.metrics.ise,
    'mvTotalVariationPercent': c.metrics.totalVariation,
    'maxPvDeviationPctSpan': c.metrics.maxError,
    'maxMvRatePctPerSecond': c.metrics.maxMvRate,
    'saturationSeconds': c.metrics.saturationSeconds,
    'recoverySeconds': c.metrics.recoverySeconds,
    'terminalErrorPctSpan': c.metrics.terminalError,
    'recovered': c.metrics.recovered,
    'numericallyStable': c.metrics.numericallyStable,
  },
  'samples': c.samples.map((s) => [s.time, s.pv, s.mv, s.sp]).toList(),
};

class AutoTuneScreen extends StatefulWidget {
  const AutoTuneScreen({super.key, this.initialPlant, this.allowSave = false});
  final bool allowSave;
  final Plant? initialPlant;
  @override
  State<AutoTuneScreen> createState() => _AutoTuneScreenState();
}

class _AutoTuneScreenState extends State<AutoTuneScreen> {
  Map<String, dynamic>? report;
  bool running = false;
  int selection = 0;
  bool compareBaseline = true;
  String? error;
  Plant? identifiedPlant;

  Future<void> run() async {
    setState(() { running = true; error = null; });
    try {
      final plant = identifiedPlant ?? widget.initialPlant ?? const Plant(gain: 0.8, tau: 12, delay: 3);
      final value = await compute(_runSearch, <String, dynamic>{'gain': plant.gain, 'tau': plant.tau, 'delay': plant.delay});
      if (!mounted) return;
      setState(() { report = value; selection = 0; });
    } catch (e) {
      if (!mounted) return;
      setState(() { error = '$e'; });
    } finally {
      if (mounted) setState(() => running = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final best = (report?['best'] as List?) ?? [];
    final chosen = best.isEmpty ? null : best[selection] as Map<String, dynamic>;
    final baseline = report?['baseline'] as Map<String, dynamic>?;
    return Scaffold(
      appBar: AppBar(title: const Text('Auto Tune Studio'), actions: [IconButton(tooltip: 'Stability Analysis', icon: const Icon(Icons.stacked_line_chart), onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const StabilityScreen()))), IconButton(tooltip: 'Step Test', icon: const Icon(Icons.analytics_outlined), onPressed: () async { final fit = await Navigator.of(context).push<IdentificationResult>(MaterialPageRoute(builder: (_) => const StepTestScreen())); if (fit != null && mounted) setState(() { identifiedPlant = fit.plant; report = null; }); })]),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        const Text('FIC-80B · Yokogawa CENTUM VP',
          style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Text(identifiedPlant != null ? 'Модель из Step Test: K=${identifiedPlant!.gain.toStringAsFixed(3)}, T=${identifiedPlant!.tau.toStringAsFixed(2)} с, L=${identifiedPlant!.delay.toStringAsFixed(2)} с. Требуется инженерная проверка.' : widget.initialPlant != null ? 'Модель выбранного контура: K=${widget.initialPlant!.gain.toStringAsFixed(3)}, T=${widget.initialPlant!.tau.toStringAsFixed(2)} с, L=${widget.initialPlant!.delay.toStringAsFixed(2)} с.' : 'Демонстрационная FOPDT-модель, не подтверждённая Step Test.'),
        const SizedBox(height: 12),
        const Wrap(spacing: 10, runSpacing: 8, children: [
          Chip(label: Text('Приоритет: клапан')),
          Chip(label: Text('PB 40–250%')),
          Chip(label: Text('Ti 5–80 с')),
          Chip(label: Text('MV ≤ 5%/с')),
          Chip(label: Text('|PV−SP| ≤ 10%')),
        ]),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: running ? null : run,
          icon: running ? const SizedBox(width: 18, height: 18,
            child: CircularProgressIndicator(strokeWidth: 2))
            : const Icon(Icons.play_arrow),
          label: Text(running ? 'Выполняется поиск…' : 'Запустить Auto Tune'),
        ),
        if (error != null) Text(error!, style: const TextStyle(color: Colors.red)),
        if (report != null && widget.allowSave) Padding(
          padding: const EdgeInsets.only(top: 12),
          child: OutlinedButton.icon(
            onPressed: () => Navigator.of(context).pop(report),
            icon: const Icon(Icons.save_alt),
            label: const Text('Сохранить расчёт в контур')),
        ),
        if (report != null) ...[
          const SizedBox(height: 14),
          Text('Проверено: ${report!['evaluated']} · допустимо: ${report!['feasibleCount']}'),
          if (best.isEmpty) const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Text('Допустимых настроек нет. Измените модель или ограничения.'),
          ),
          if (best.isNotEmpty) ...[
            const SizedBox(height: 12),
            const Text('Найденные настройки', style: TextStyle(fontWeight: FontWeight.bold)),
            ...List.generate(best.length, (i) {
              final c = best[i] as Map<String, dynamic>;
              final m = c['metrics'] as Map<String, dynamic>;
              return RadioListTile<int>(
                value: i, groupValue: selection,
                onChanged: (v) => setState(() => selection = v!),
                title: Text('PB ${(c['pbPercent'] as num).toStringAsFixed(1)}% · '
                  'Ti ${(c['tiSeconds'] as num).toStringAsFixed(1)} с'),
                subtitle: Text('Ход MV ${(m['mvTotalVariationPercent'] as num).toStringAsFixed(2)}% · '
                  'IAE ${(m['iae'] as num).toStringAsFixed(1)}'),
              );
            }),
            SwitchListTile(
              title: const Text('Сравнить с исходной настройкой'),
              value: compareBaseline,
              onChanged: (v) => setState(() => compareBaseline = v),
            ),
            if (chosen != null) ...[
              const SizedBox(height: 8),
              const Text('PV и SP · % шкалы', style: TextStyle(fontWeight: FontWeight.bold)),
              SizedBox(height: 210, child: _Plot(
                current: chosen, baseline: compareBaseline ? baseline : null,
                valueIndex: 1, showSp: true)),
              const SizedBox(height: 12),
              const Text('MV · % открытия', style: TextStyle(fontWeight: FontWeight.bold)),
              SizedBox(height: 210, child: _Plot(
                current: chosen, baseline: compareBaseline ? baseline : null,
                valueIndex: 2)),
            ],
          ],
          const SizedBox(height: 12),
          ExpansionTile(title: const Text('JSON-отчёт'), children: [
            SelectableText(const JsonEncoder.withIndent('  ').convert(report)),
          ]),
        ],
      ]),
    );
  }
}

class _Plot extends StatelessWidget {
  final Map<String, dynamic> current;
  final Map<String, dynamic>? baseline;
  final int valueIndex;
  final bool showSp;
  const _Plot({required this.current, this.baseline,
    required this.valueIndex, this.showSp = false});
  @override
  Widget build(BuildContext context) => CustomPaint(
    painter: _PlotPainter(current, baseline, valueIndex, showSp),
    child: const SizedBox.expand(),
  );
}

class _PlotPainter extends CustomPainter {
  final Map<String, dynamic> current;
  final Map<String, dynamic>? baseline;
  final int index;
  final bool showSp;
  _PlotPainter(this.current, this.baseline, this.index, this.showSp);

  List<List<num>> points(Map<String, dynamic> data) =>
    (data['samples'] as List).map((s) => (s as List).cast<num>()).toList();

  @override
  void paint(Canvas canvas, Size size) {
    final all = points(current);
    if (all.isEmpty) return;
    final other = baseline == null ? <List<num>>[] : points(baseline!);
    final combined = [...all, ...other];
    final minY = combined.map((p) => p[index].toDouble()).reduce(math.min);
    final maxY = combined.map((p) => p[index].toDouble()).reduce(math.max);
    final spanY = math.max(1.0, maxY - minY);
    final minX = all.first[0].toDouble();
    final maxX = all.last[0].toDouble();
    final spanX = math.max(1.0, maxX - minX);
    const left = 42.0, right = 10.0, top = 12.0, bottom = 25.0;
    final w = math.max(1.0, size.width - left - right);
    final h = math.max(1.0, size.height - top - bottom);
    Offset xy(List<num> p, double value) => Offset(
      left + (p[0] - minX) / spanX * w,
      top + h - (value - minY) / spanY * h);
    void line(List<List<num>> series, Color color, int column) {
      if (series.isEmpty) return;
      final path = Path()..moveTo(xy(series.first, series.first[column].toDouble()).dx,
        xy(series.first, series.first[column].toDouble()).dy);
      for (final p in series.skip(1)) {
        final q = xy(p, p[column].toDouble());
        path.lineTo(q.dx, q.dy);
      }
      canvas.drawPath(path, Paint()..color = color..strokeWidth = 2
        ..style = PaintingStyle.stroke);
    }
    final axis = Paint()..color = Colors.grey.shade500..strokeWidth = 1;
    canvas.drawLine(const Offset(left, top), Offset(left, top + h), axis);
    canvas.drawLine(Offset(left, top + h), Offset(left + w, top + h), axis);
    void text(String s, Offset at) {
      final painter = TextPainter(text: TextSpan(text: s,
        style: const TextStyle(color: Colors.black87, fontSize: 10)),
        textDirection: TextDirection.ltr)..layout();
      painter.paint(canvas, at);
    }
    text(maxY.toStringAsFixed(1), const Offset(0, top));
    text(minY.toStringAsFixed(1), Offset(0, top + h - 10));
    text('${maxX.toStringAsFixed(0)} с', Offset(left + w - 35, top + h + 5));
    line(all, Colors.teal, index);
    if (other.isNotEmpty) line(other, Colors.deepOrange, index);
    if (showSp) line(all, Colors.blueGrey, 3);
  }

  @override
  bool shouldRepaint(covariant _PlotPainter old) => true;
}


/// Offline CSV import via paste, preview and manual step-time override.
/// Import from file picker can be connected to the same parser later.
class StepTestScreen extends StatefulWidget {
  const StepTestScreen({super.key});
  @override
  State<StepTestScreen> createState() => _StepTestScreenState();
}

class _StepTestScreenState extends State<StepTestScreen> {
  final csv = TextEditingController();
  final manualStep = TextEditingController();
  String? fileName;
  final mvHigh = TextEditingController(text: '100');
  final pvHigh = TextEditingController(text: '100');
  List<TrendPoint>? measured, fitted;
  IdentificationResult? result;
  String? error;

  @override
  void dispose() {csv.dispose();mvHigh.dispose();pvHigh.dispose();manualStep.dispose();super.dispose();}

  Future<void> importCsv() async {
    try {
      final picked = await FilePicker.platform.pickFiles(
        type: FileType.custom, allowedExtensions: ['csv', 'txt'],
        withData: true,
      );
      if (picked == null || picked.files.isEmpty) return;
      final file = picked.files.single;
      if (file.bytes == null) throw const FormatException('File data unavailable');
      if (file.bytes!.length > 10 * 1024 * 1024) {
        throw const FormatException('CSV file exceeds 10 MB');
      }
      final content = utf8.decode(file.bytes!, allowMalformed: false);
      if (!mounted) return;
      setState(() { csv.text = content; fileName = file.name; error = null; result = null; });
    } catch (e) {
      if (mounted) setState(() => error = 'Import: $e');
    }
  }

  void identify() {
    try {
      final samples=const TrendCsv().parse(csv.text,
        mvHigh: double.parse(mvHigh.text), pvHigh: double.parse(pvHigh.text));
      final manual = manualStep.text.trim();
      final fit=const StepIdentifier().identify(samples, manualStepAt: manual.isEmpty ? null : double.parse(manual.replaceAll(',', '.')));
      setState(() {measured=samples;result=fit;
        fitted=fittedResponse(samples,fit);error=null;});
    } catch (e) {
      setState(() {error='$e';result=null;measured=null;fitted=null;});
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Step Test · FOPDT')),
    body: ListView(padding: const EdgeInsets.all(16),children: [
      const Text('Вставьте CSV с колонками time,mv,pv. Время в секундах; MV и PV в инженерных единицах. Данные не отправляются в сеть.'),
      const SizedBox(height: 12),
      OutlinedButton.icon(onPressed: importCsv, icon: const Icon(Icons.file_open), label: const Text('Выбрать CSV-файл')),
      if (fileName != null) Text('Файл: $fileName'),
      const SizedBox(height: 12),
      TextField(controller: csv, maxLines: 7,
        decoration: const InputDecoration(border: OutlineInputBorder(),
          labelText: 'CSV-тренд',hintText: 'time,mv,pv\n0,50,40\n1,50,40')),
      const SizedBox(height: 10),
      Row(children: [
        Expanded(child: TextField(controller: mvHigh, keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'MV span high'))),
        const SizedBox(width: 12),
        Expanded(child: TextField(controller: pvHigh, keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'PV span high'))),
      ]),
      const SizedBox(height: 12),
      TextField(controller: manualStep, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Момент ступени, с (необязательно)', hintText: 'Автоматически')),
      const SizedBox(height: 12),
      FilledButton(onPressed: identify, child: const Text('Идентифицировать')),
      if (error!=null) Text(error!,style:const TextStyle(color:Colors.red)),
      if (result!=null) ...[
        const SizedBox(height: 16),
        Text('K=${result!.plant.gain.toStringAsFixed(3)} · '
          'T=${result!.plant.tau.toStringAsFixed(2)} с · '
          'L=${result!.plant.delay.toStringAsFixed(2)} с'),
        Text('R²=${result!.rSquared.toStringAsFixed(3)} · '
          'RMSE=${result!.rmse.toStringAsFixed(3)} · '
          'NRMSE=${result!.normalizedRmse.toStringAsFixed(3)}'),
        Text(result!.suitableForAutoTune
          ? 'Формальные критерии качества выполнены. Требуется инженерная проверка.'
          : 'Качество недостаточно для Auto Tune.'),
        if (result!.suitableForAutoTune) FilledButton.icon(
          onPressed: () => Navigator.of(context).pop(result),
          icon: const Icon(Icons.arrow_forward),
          label: const Text('Передать модель в Auto Tune')),
        const SizedBox(height: 12),
        const Text('Измеренная PV и расчётная FOPDT · % шкалы'),
        SizedBox(height: 230,child: CustomPaint(
          painter: _StepPlotPainter(measured!,fitted!),child: const SizedBox.expand())),
      ],
    ]),
  );
}

class _StepPlotPainter extends CustomPainter {
  final List<TrendPoint> actual, fitted;
  _StepPlotPainter(this.actual,this.fitted);
  @override
  void paint(Canvas canvas, Size size) {
    if (actual.isEmpty) return;
    const left=40.0,top=12.0,bottom=24.0,right=12.0;
    final w=math.max(1.0,size.width-left-right);
    final h=math.max(1.0,size.height-top-bottom);
    final minT=actual.first.seconds,maxT=actual.last.seconds;
    final values=[...actual.map((p)=>p.pv),...fitted.map((p)=>p.pv)];
    final minY=values.reduce(math.min),maxY=values.reduce(math.max);
    Offset pos(TrendPoint p)=>Offset(left+(p.seconds-minT)/math.max(1,maxT-minT)*w,
      top+h-(p.pv-minY)/math.max(1,maxY-minY)*h);
    void plot(List<TrendPoint> points,Color color) {
      final path=Path()..moveTo(pos(points.first).dx,pos(points.first).dy);
      for(final p in points.skip(1)) {final v=pos(p);path.lineTo(v.dx,v.dy);}
      canvas.drawPath(path,Paint()..color=color..strokeWidth=2..style=PaintingStyle.stroke);
    }
    canvas.drawLine(const Offset(left,top),Offset(left,top+h),Paint()..color=Colors.grey);
    canvas.drawLine(Offset(left,top+h),Offset(left+w,top+h),Paint()..color=Colors.grey);
    plot(actual,Colors.teal);plot(fitted,Colors.deepOrange);
  }
  @override
  bool shouldRepaint(covariant _StepPlotPainter old)=>true;
}

import 'dart:async';
import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:pid_tuner_pro_core/auto_tune.dart';
import 'package:pid_tuner_pro_core/manual_step_identification.dart';
import 'package:pid_tuner_pro_core/integrating_step_identification.dart';
import 'package:pid_tuner_pro_core/step_identification.dart';
import 'package:pid_tuner_pro_core/step_test_settings.dart';
import 'package:pid_tuner_pro_core/trend_csv.dart';

import 'manual_step_form.dart';
import 'integrating_manual_form.dart';
import 'step_settings_screen.dart';
import 'step_web_database.dart';
import 'tuning_calculation_screen.dart';

/// Safari Step Test. Native DCS control and other lab screens remain excluded.
/// Settings and identification evidence use the browser's own IndexedDB.
void main() => runApp(const PidTunerWebPreview());

class PidTunerWebPreview extends StatelessWidget {
  final StepWebDatabase? database;
  const PidTunerWebPreview({super.key, this.database});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'PID Tuner Pro',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF176C80),
        brightness: Brightness.light,
      ),
      scaffoldBackgroundColor: const Color(0xFFF5F7FA),
      appBarTheme: const AppBarTheme(
        backgroundColor: Color(0xFFF5F7FA),
        centerTitle: false,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: Colors.white,
        margin: const EdgeInsets.symmetric(vertical: 6),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Color(0xFFE1E7ED)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    home: WebPreviewHome(database: database),
  );
}

class WebPreviewHome extends StatefulWidget {
  final StepWebDatabase? database;
  const WebPreviewHome({super.key, this.database});

  @override
  State<WebPreviewHome> createState() => _WebPreviewHomeState();
}

class _WebPreviewHomeState extends State<WebPreviewHome> {
  late final StepWebDatabase db;
  bool ownsDatabase = false;
  bool loading = true;
  int selectedTab = 0; // Settings must precede Step Test.
  int stepDraft = 1;
  String? error;
  StepTestSettings? settings;
  List<Map<String, dynamic>> results = const [];

  @override
  void initState() {
    super.initState();
    ownsDatabase = widget.database == null;
    db = widget.database ?? StepWebDatabase();
    unawaited(restore());
  }

  Future<void> restore() async {
    try {
      await db.open();
      final loadedSettings = await db.loadSettings();
      final previousResults = await db.getResults();
      if (!mounted) return;
      setState(() {
        settings = loadedSettings;
        results = previousResults;
        loading = false;
        error = null;
      });
    } catch (e) {
      if (mounted) setState(() {
        error = 'Не удалось открыть базу IndexedDB: ' + e.toString();
        loading = false;
      });
    }
  }

  @override
  void dispose() {
    if (ownsDatabase) db.close();
    super.dispose();
  }

  Future<void> saveSettings(StepTestSettings value) async {
    await db.saveSettings(value); // Only proceed if transaction committed.
    if (!mounted) return;
    setState(() {
      settings = value;
      selectedTab = 1;
      error = null;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Settings сохранены в IndexedDB')),
    );
  }

  Future<void> refreshResults() async {
    final loaded = await db.getResults();
    if (mounted) setState(() => results = loaded);
  }

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Scaffold(
        body: Center(child: Text('Загрузка настроек из IndexedDB…')),
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text('PID Tuner Pro',
          style: TextStyle(fontWeight: FontWeight.w700)),
        backgroundColor: Theme.of(context).colorScheme.surfaceContainer,
      ),
      body: SafeArea(child: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          child: Row(children: [
            Expanded(child: ChoiceChip(
              key: const Key('top-settings'),
              label: const Center(child: Text('Settings', maxLines: 1)),
              selected: selectedTab == 0,
              onSelected: (_) => setState(() => selectedTab = 0),
            )),
            const SizedBox(width: 12),
            Expanded(child: ChoiceChip(
              key: const Key('top-step-test'),
              label: const Center(child: Text('Step Test', maxLines: 1)),
              selected: selectedTab == 1,
              onSelected: settings == null ? null
                : (_) => setState(() => selectedTab = 1),
            )),
            const SizedBox(width: 6),
            Expanded(child: ChoiceChip(
              key: const Key('top-tuning-calculation'),
              label: const Center(child: Text('Tuning', maxLines: 1)),
              selected: selectedTab == 2,
              onSelected: settings == null ? null
                : (_) => setState(() => selectedTab = 2),
            )),
          ]),
        ),
        if (error != null)
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text(error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ),
        Expanded(
          child: selectedTab == 0
            ? StepSettingsScreen(
                key: ValueKey(settings?.toJson().toString() ?? 'new'),
                initialSettings: settings,
                onSave: saveSettings,
              )
            : settings == null
              ? const Center(child: Text('Сначала заполните Settings'))
              : selectedTab == 2
                ? TuningCalculationScreen(
                    settings: settings!, database: db, results: results)
                : WebStepTest(
                  key: ValueKey('${settings!.toJson()}-$stepDraft'),
                  settings: settings!,
                  database: db,
                  results: results,
                  onResultSaved: refreshResults,
                  onNewStepTest: () => setState(() => stepDraft++),
                ),
        ),
      ])),
    );
  }
}

class WebStepTest extends StatefulWidget {
  final StepTestSettings settings;
  final StepWebDatabase database;
  final List<Map<String, dynamic>> results;
  final Future<void> Function() onResultSaved;
  final VoidCallback? onNewStepTest;

  const WebStepTest({
    super.key,
    required this.settings,
    required this.database,
    required this.results,
    required this.onResultSaved,
    this.onNewStepTest,
  });

  @override
  State<WebStepTest> createState() => _WebStepTestState();
}

class _WebStepTestState extends State<WebStepTest> {
  final csv = TextEditingController();
  final mvHigh = TextEditingController(text: '100');
  final pvHigh = TextEditingController(text: '1000');
  final manualStepAt = TextEditingController();
  IdentificationResult? fit;
  IntegratingIdentificationResult? integratingFit;
  List<TrendPoint>? measured;
  List<TrendPoint>? fitted;
  String? error;
  String? fileName;
  String? savedStatus;
  String? tuningWarning;
  StepPiEstimate? latestPi;
  bool loading = false;
  bool saving = false;

  bool get integratingMode => widget.settings.isIntegratingAcquisition;

  bool get manualMode =>
    widget.settings.acquisition != StepAcquisition.csvTrend &&
    widget.settings.acquisition != StepAcquisition.csvIntegratingTrend;

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
        integratingFit = null;
        error = null;
        savedStatus = null;
        latestPi = null;
      });
    } catch (e) {
      if (mounted) setState(() =>
        error = 'Импорт не выполнен: ' + e.toString());
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
      final stepTime = step.isEmpty ? null : value(manualStepAt);
      if (integratingMode) {
        final result = const IntegratingStepIdentifier().identify(
          points, manualStepAt: stepTime);
        setState(() {
          integratingFit = result;
          fit = null;
          measured = points;
          fitted = result.fittedCurve;
          error = null;
          savedStatus = null;
          latestPi = null;
        });
      } else {
        final result = const StepIdentifier().identify(
          points, manualStepAt: stepTime);
        setState(() {
          fit = result;
          integratingFit = null;
          measured = points;
          fitted = fittedResponse(points, result);
          error = null;
          savedStatus = null;
          latestPi = null;
        });
      }
    } catch (e) {
      setState(() {
        fit = null;
        integratingFit = null;
        measured = null;
        fitted = null;
        error = 'Не удалось идентифицировать: ' + e.toString();
      });
    }
  }

  Future<void> saveResult({
    required Plant plant,
    required String source,
    required Map<String, Object?> evidence,
    String? originalCsv,
  }) async {
    if (saving) return;
    setState(() {
      saving = true;
      error = null;
      savedStatus = null;
      tuningWarning = null;
      latestPi = null;
    });
    try {
      StepPiEstimate? pi;
      String? warning = widget.settings.tuningBlockReason;
      if (widget.settings.canCalculate) {
        try {
          pi = const StepPiCalculator().calculate(plant, widget.settings);
        } catch (e) {
          warning = 'PI не рассчитан: ' + e.toString();
        }
      }
      await widget.database.addResult(
        settings: widget.settings,
        plant: plant,
        source: source,
        evidence: evidence,
        piEstimate: pi,
        originalCsv: originalCsv,
      );
      await widget.onResultSaved();
      if (!mounted) return;
      setState(() {
        latestPi = pi;
        tuningWarning = warning;
        savedStatus = 'Step Test и контекст Settings сохранены в IndexedDB.';
      });
    } catch (e) {
      if (mounted) setState(() =>
        error = 'Результат НЕ сохранён: ' + e.toString());
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  Future<void> saveIntegratingResult({
    required IntegratingPlant plant,
    required String source,
    required Map<String, Object?> evidence,
    String? originalCsv,
    bool fitAcceptable = true,
  }) async {
    if (saving) return;
    setState(() {
      saving = true;
      error = null;
      savedStatus = null;
      tuningWarning = null;
      latestPi = null;
    });
    try {
      StepPiEstimate? pi;
      String? warning = widget.settings.tuningBlockReason;
      if (!fitAcceptable) {
        warning = 'Качество CSV идентификации недостаточно: '
          'PI не рассчитывается. Сохранён только результат анализа.';
      } else if (widget.settings.canCalculate) {
        try {
          pi = const StepPiCalculator().calculateIntegrating(
            plant, widget.settings);
        } catch (e) {
          warning = 'PI не рассчитан: ' + e.toString();
        }
      }
      await widget.database.addIntegratingResult(
        settings: widget.settings, plant: plant,
        source: source, evidence: evidence,
        piEstimate: pi, originalCsv: originalCsv,
      );
      await widget.onResultSaved();
      if (!mounted) return;
      setState(() {
        latestPi = pi;
        tuningWarning = warning;
        savedStatus = 'IPDT Step Test сохранён в IndexedDB с Settings.';
      });
    } catch (e) {
      if (mounted) setState(() =>
        error = 'IPDT результат НЕ сохранён: ' + e.toString());
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  void acceptIntegratingManual(IntegratingManualEstimate estimate) {
    unawaited(saveIntegratingResult(
      plant: estimate.plant,
      source: 'Manual Integrating Step',
      evidence: estimate.evidence,
    ));
  }

  void acceptIntegratingCsv() {
    final r = integratingFit;
    if (r == null) return;
    unawaited(saveIntegratingResult(
      plant: r.plant, source: 'Integrating Step CSV',
      fitAcceptable: r.suitableForTuning,
      evidence: {
        'method': 'csvIpdtRampFit',
        'stepAtSeconds': r.stepAtSeconds,
        'mvBefore': r.mvBefore,
        'mvAfter': r.mvAfter,
        'baselineSlopePctPerSecond': r.baselineSlopePctPerSecond,
        'baselinePvAtStep': r.baselinePvAtStep,
        'rSquared': r.rSquared,
        'nrmse': r.normalizedRmse,
        'fittedPoints': r.fittedPoints,
        'suitableForTuning': r.suitableForTuning,
        'fileName': fileName,
        'mvSpanHigh': double.parse(mvHigh.text.replaceAll(',', '.')),
        'pvSpanHigh': double.parse(pvHigh.text.replaceAll(',', '.')),
      },
      originalCsv: csv.text,
    ));
  }

  void acceptManual(ManualStepEstimate estimate) {
    unawaited(saveResult(
      plant: estimate.plant,
      source: 'Manual Step ' + estimate.input.method.name,
      evidence: Map<String, Object?>.from(estimate.evidence),
    ));
  }

  void acceptCsv() {
    final r = fit;
    if (r == null) return;
    unawaited(saveResult(
      plant: r.plant,
      source: 'Step Test CSV',
      evidence: {
        'method': 'csvFopdtGridFit',
        'stepAtSeconds': r.stepAt,
        'mvBefore': r.mvBefore,
        'mvAfter': r.mvAfter,
        'pvBefore': r.pvBefore,
        'rmse': r.rmse,
        'rSquared': r.rSquared,
        'nrmse': r.normalizedRmse,
        'fittedPoints': r.fittedPoints,
        'suitableForAutoTune': r.suitableForAutoTune,
        'fileName': fileName,
        'mvSpanHigh': double.parse(mvHigh.text.replaceAll(',', '.')),
        'pvSpanHigh': double.parse(pvHigh.text.replaceAll(',', '.')),
      },
      originalCsv: csv.text,
    ));
  }

  Widget numeric(String label, TextEditingController controller) =>
    SizedBox(width: 155, child: TextField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(labelText: label,
        border: const OutlineInputBorder(), isDense: true),
    ));

  @override
  Widget build(BuildContext context) {
    final settings = widget.settings;
    return ListView(
      key: const Key('step-test-form'),
      padding: const EdgeInsets.all(16),
      children: [
        Text('Step Test · ' + settings.tag,
          style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        Text('Сохранено испытаний: ${widget.results.where((r) => (r['settings'] as Map?)?['tag'] == settings.tag).length}',
          style: Theme.of(context).textTheme.bodyMedium),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          key: const Key('add-step-test'),
          onPressed: widget.onNewStepTest,
          icon: const Icon(Icons.add),
          label: const Text('Add Step Test'),
        ),
        const SizedBox(height: 8),
        Text(settings.profile.vendor + ' · ' + settings.profile.system +
          ' · ' + settings.controlledVariable.title),
        const SizedBox(height: 4),
        Text('Метод: ' + settings.acquisition.title),
        Text('Расчёт: ' + settings.tuningMethod.title),
        const SizedBox(height: 8),
        ExpansionTile(
          title: const Text('Как проводить Step Test'),
          children: [Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
            child: Text(settings.acquisition.instructions),
          )],
        ),
        const SizedBox(height: 14),
        if (widget.settings.acquisition == StepAcquisition.manualIntegratingSlope)
          IntegratingManualForm(
            onAccept: acceptIntegratingManual,
          )
        else if (manualMode)
          ManualStepForm(
            key: ValueKey(settings.acquisition.name),
            initialMethod:
              settings.acquisition == StepAcquisition.manualTwoPoints
                ? ManualStepMethod.twoResponseTimes
                : ManualStepMethod.knownDelayAndT63,
            allowMethodSelection: false,
            onAccept: acceptManual,
          )
        else ...[
          const Text('CSV time,mv,pv: время в секундах; MV/PV '
            'в инженерных единицах.'),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: loading ? null : loadCsv,
            icon: const Icon(Icons.file_open),
            label: const Text('Выбрать CSV-файл')),
          if (fileName != null) Text('Файл: ' + fileName!),
          const SizedBox(height: 8),
          TextField(
            key: const Key('step-csv-text'),
            controller: csv, maxLines: 7,
            decoration: const InputDecoration(
              labelText: 'CSV-тренд',
              border: OutlineInputBorder(),
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
          if (integratingFit != null) ...[
            const SizedBox(height: 12),
            Text('Ki = ' +
              integratingFit!.plant.gainPerSecond.toStringAsFixed(6) +
              ' 1/с, L = ' +
              integratingFit!.plant.delaySeconds.toStringAsFixed(2) + ' с',
              style: Theme.of(context).textTheme.titleMedium),
            Text('Начальный наклон PV: ' +
              integratingFit!.baselineSlopePctPerSecond.toStringAsFixed(5) +
              ' %/с. R² = ' +
              integratingFit!.rSquared.toStringAsFixed(3) +
              ', NRMSE = ' +
              integratingFit!.normalizedRmse.toStringAsFixed(3)),
            Text(integratingFit!.suitableForTuning
              ? 'Подходящее качество IPDT-приближения. '
                'Проверьте линейность и безопасные границы процесса.'
              : 'Недостаточное качество; PI будет заблокирован. '
                'Можно сохранить данные для последующей проверки.'),
            FilledButton.icon(
              key: const Key('integrating-csv-save'),
              onPressed: saving ? null : acceptIntegratingCsv,
              icon: const Icon(Icons.save_outlined),
              label: const Text('Сохранить IPDT Step Test')),
            const SizedBox(height: 12),
            const Text('Интегрирующий отклик PV · измерение / модель'),
            SizedBox(height: 220,
              child: CustomPaint(
                painter: _WebCsvPlot(measured!, fitted!),
                child: const SizedBox.expand())),
          ],
          if (fit != null) ...[
            const SizedBox(height: 12),
            Text('K = ' + fit!.plant.gain.toStringAsFixed(4) +
              ', T = ' + fit!.plant.tau.toStringAsFixed(2) +
              ' с, L = ' + fit!.plant.delay.toStringAsFixed(2) + ' с',
              style: Theme.of(context).textTheme.titleMedium),
            Text('R² = ' + fit!.rSquared.toStringAsFixed(3) +
              ', NRMSE = ' + fit!.normalizedRmse.toStringAsFixed(3)),
            Text(fit!.suitableForAutoTune
              ? 'Формальные критерии качества выполнены. '
                'Требуется инженерная проверка.'
              : 'Качество идентификации недостаточно '
                'для автоматического переноса настроек.'),
            FilledButton.icon(
              key: const Key('step-csv-save'),
              onPressed: saving ? null : acceptCsv,
              icon: const Icon(Icons.save_outlined),
              label: const Text('Сохранить Step Test в базе данных')),
            const SizedBox(height: 12),
            const Text('Измеренная и расчётная PV · % шкалы'),
            SizedBox(height: 220,
              child: CustomPaint(
                painter: _WebCsvPlot(measured!, fitted!),
                child: const SizedBox.expand())),
          ],
        ],
        if (error != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error))),
        if (savedStatus != null) ...[
          const SizedBox(height: 14),
          Text(savedStatus!,
            key: const Key('step-saved-status'),
            style: const TextStyle(fontWeight: FontWeight.w600)),
          if (latestPi != null) ...[
            Text('Предварительная настройка ' +
              (latestPi!.levelControlMode == LevelControlMode.pid
                ? 'PID' : 'PI') + ' (' +
              settings.tuningMethod.title + ')',
              style: Theme.of(context).textTheme.titleMedium),
            Text(latestPi!.display.profile.proportionalLabel + ': ' +
              latestPi!.display.proportionalValue.toStringAsFixed(4)),
            Text('PB = ' + latestPi!.pbPercent.toStringAsFixed(3) +
              ' %, Kc = ' + latestPi!.kcNormalized.toStringAsFixed(4) +
              (settings.tuningMethod == TuningMethod.opticontrolsLevel
                ? ', Ti = ' + (latestPi!.tiSeconds / 60).toStringAsFixed(3) +
                    ' мин, Td = ' +
                    (latestPi!.tdSeconds / 60).toStringAsFixed(3) + ' мин'
                : ', Ti = ' + latestPi!.tiSeconds.toStringAsFixed(2) +
                    ' с, Td = ' + latestPi!.tdSeconds.toStringAsFixed(2) + ' с')),
            if (settings.tuningMethod == TuningMethod.opticontrolsLevel)
              const Text('Внутри расчёта и сохранённых DCS-эквивалентах '
                'время переводится в секунды. Перед применением '
                'проверьте единицы конкретного блока DCS.'),
            Text('Направление действия для проверки: ' +
              latestPi!.display.recommendedAction),
            Text(latestPi!.display.profile.warning),
          ],
          if (tuningWarning != null) Text(tuningWarning!),
          const Text('Не переносить параметры в DCS без '
            'проверки PID-формы (interacting/parallel), блока, '
            'единиц, шкал и устойчивости.'),
        ],
        if (widget.results.isNotEmpty) ...[
          const SizedBox(height: 20),
          Text('История Step Test · IndexedDB',
            style: Theme.of(context).textTheme.titleMedium),
          Text('Записей: ' + widget.results.length.toString()),
          for (final row in widget.results.take(10))
            Card(child: ListTile(
              title: Text(((row['settings'] as Map)['tag'] as String) +
                ' · ' + (row['source'] as String)),
              subtitle: Text(
                ((row['model'] as Map)['type'] == 'IPDT'
                  ? 'Ki=' + ((row['model'] as Map)['KiPerSecond'] as num)
                    .toStringAsFixed(6) + ' 1/с'
                  : 'K=' + ((row['model'] as Map)['K'] as num)
                    .toStringAsFixed(3) +
                    ' T=' + ((row['model'] as Map)['T'] as num)
                    .toStringAsFixed(2) + ' с') +
                ' L=' + ((row['model'] as Map)['L'] as num)
                  .toStringAsFixed(2) +
                ' с | ' + (row['savedAt'] as String)),
            )),
        ],
        const SizedBox(height: 12),
        const Text('Step Test не выполняет реальное воздействие на объект. '
          'База хранится локально в Safari; удаление данных сайта '
          'или приватный режим могут уничтожить записи.'),
      ],
    );
  }
}

class _WebCsvPlot extends CustomPainter {
  final List<TrendPoint> measured;
  final List<TrendPoint> predicted;
  _WebCsvPlot(this.measured, this.predicted);

  @override
  void paint(Canvas canvas, Size size) {
    if (measured.isEmpty || predicted.isEmpty) return;
    const x0 = 40.0, y0 = 10.0, right = 10.0, bottom = 23.0;
    final w = (size.width - x0 - right).clamp(1.0, double.infinity).toDouble();
    final h = (size.height - y0 - bottom).clamp(1.0, double.infinity).toDouble();
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


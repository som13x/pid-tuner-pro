import 'package:flutter/material.dart';
import 'package:pid_tuner_pro_core/auto_tune.dart';
import 'package:pid_tuner_pro_core/integrating_step_identification.dart';
import 'package:pid_tuner_pro_core/step_test_settings.dart';
import 'step_web_database.dart';

/// Uses Settings from the first tab exclusively; never selects DCS or method.
class TuningCalculationScreen extends StatefulWidget {
  final StepTestSettings settings;
  final StepWebDatabase database;
  final List<Map<String, dynamic>> results;
  const TuningCalculationScreen({
    super.key, required this.settings, required this.database,
    required this.results,
  });

  @override
  State<TuningCalculationScreen> createState() => _TuningCalculationScreenState();
}

class _TuningCalculationScreenState extends State<TuningCalculationScreen> {
  List<Map<String, dynamic>> history = [];
  String? error;
  bool busy = false;

  @override
  void initState() {
    super.initState();
    loadHistory();
  }

  Future<void> loadHistory() async {
    try {
      final saved = await widget.database.getTuningCalculations();
      if (mounted) setState(() { history = saved; error = null; });
    } catch (e) {
      if (mounted) setState(() => error = 'История: $e');
    }
  }

  StepPiEstimate calculate(Map<String, dynamic> row) {
    final model = Map<String, dynamic>.from(row['model'] as Map);
    const calculator = StepPiCalculator();
    if (model['type'] == 'IPDT') {
      return calculator.calculateIntegrating(
        IntegratingPlant(
          gainPerSecond: (model['KiPerSecond'] as num).toDouble(),
          delaySeconds: (model['L'] as num).toDouble(),
        ), widget.settings,
      );
    }
    return calculator.calculate(
      Plant(
        gain: (model['K'] as num).toDouble(),
        tau: (model['T'] as num).toDouble(),
        delay: (model['L'] as num).toDouble(),
      ), widget.settings,
    );
  }

  Future<void> save(Map<String, dynamic> row) async {
    if (busy) return;
    setState(() { busy = true; error = null; });
    try {
      final estimate = calculate(row);
      await widget.database.saveTuningCalculation(
        settings: widget.settings, sourceResult: row, estimate: estimate);
      await loadHistory();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Расчёт сохранён в IndexedDB')));
    } catch (e) {
      if (mounted) setState(() => error = 'Не удалось сохранить: $e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Widget estimateDetails(StepPiEstimate pi) {
    final minutes = widget.settings.tuningMethod == TuningMethod.opticontrolsLevel;
    final factor = minutes ? 60.0 : 1.0;
    final unit = minutes ? 'мин' : 'с';
    Widget metric(String label, String value) => Container(
      width: 136,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F6F9),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: const TextStyle(fontSize: 12, color: Color(0xFF506476))),
        const SizedBox(height: 5),
        Text(value, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700)),
      ]),
    );
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Wrap(spacing: 8, runSpacing: 8, children: [
        metric('Kc', pi.kcNormalized.toStringAsFixed(4)),
        metric('PB', '${pi.pbPercent.toStringAsFixed(3)} %'),
        metric('Ti', '${(pi.tiSeconds / factor).toStringAsFixed(3)} $unit'),
        metric('Td', '${(pi.tdSeconds / factor).toStringAsFixed(3)} $unit'),
      ]),
      const SizedBox(height: 10),
      Text('${pi.display.profile.proportionalLabel}: '
          '${pi.display.proportionalValue.toStringAsFixed(4)}',
          style: const TextStyle(fontWeight: FontWeight.w600)),
      const SizedBox(height: 6),
      Text(pi.display.profile.warning,
          style: const TextStyle(fontSize: 12, color: Color(0xFF506476))),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final current = widget.results.where((row) {
      final raw = row['settings'];
      return raw is Map && raw['tag'] == widget.settings.tag;
    }).toList();
    return ListView(padding: const EdgeInsets.all(16), children: [
      Text('Tuning Calculation', style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 8),
      Text('Контур: ${widget.settings.tag}',
          style: Theme.of(context).textTheme.titleMedium),
      Text('DCS: ${widget.settings.profile.vendor} · ${widget.settings.profile.system}'),
      Text('Метод: ${widget.settings.tuningMethod.title}'),
      const Padding(
        padding: EdgeInsets.only(top: 8),
        child: Text('Параметры DCS и метод задаются только в Settings.',
          style: TextStyle(color: Color(0xFF506476))),
      ),
      if (error != null) Text(error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
      const SizedBox(height: 16),
      Text('Сохранённые Step Tests (${current.length})',
          style: Theme.of(context).textTheme.titleMedium),
      if (current.isEmpty) const Text('Сначала сохраните Step Test на предыдущей вкладке.'),
      for (var i = 0; i < current.length; i++)
        Card(child: Padding(padding: const EdgeInsets.all(12), child:
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Step Test ${current.length - i} · ${current[i]['source']}',
                style: Theme.of(context).textTheme.titleMedium),
            Text('Дата: ${current[i]['savedAt']}'),
            Text('Модель: ${current[i]['model']}'),
            const SizedBox(height: 8),
            Builder(builder: (context) {
              try {
                final pi = calculate(current[i]);
                return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  estimateDetails(pi),
                  const SizedBox(height: 8),
                  FilledButton.icon(
                    onPressed: busy ? null : () => save(current[i]),
                    icon: const Icon(Icons.save_outlined),
                    label: const Text('Сохранить расчёт')),
                ]);
              } catch (e) {
                return Text('Расчёт заблокирован: $e');
              }
            }),
          ]))),
      const SizedBox(height: 16),
      Text('История сохранённых расчётов (${history.length})',
          style: Theme.of(context).textTheme.titleMedium),
      for (final row in history)
        Card(child: ListTile(
          leading: const Icon(Icons.history),
          title: Text('${row['source']} · ${row['savedAt']}'),
          subtitle: Text('Контур: ${(row['settings'] as Map)['tag']} · '
              'Метод: ${(row['settings'] as Map)['tuningMethod']}\n'
              'Kc: ${(row['piEstimate'] as Map)['kcNormalized']} · '
              'Ti: ${(row['piEstimate'] as Map)['tiSeconds']} с · '
              'Td: ${(row['piEstimate'] as Map)['tdSeconds']} с'),
          isThreeLine: true,
        )),
      const Text('Параметры требуют инженерной проверки перед применением в DCS.'),
    ]);
  }
}

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'multi_model_tune.dart';
import 'model_management.dart';
import 'sqlite_project_store.dart';

class ModelHistoryScreen extends StatefulWidget {
  final PidDatabase db;
  final String loopId, loopTag;
  const ModelHistoryScreen({super.key, required this.db,
    required this.loopId, required this.loopTag});
  @override
  State<ModelHistoryScreen> createState() => _ModelHistoryScreenState();
}

class _ModelHistoryScreenState extends State<ModelHistoryScreen> {
  List<StoredIdentification> models = [];
  final Set<int> selected = {};
  String? error;
  bool loading = true;

  @override
  void initState() { super.initState(); refresh(); }
  Future<void> refresh() async {
    try {
      final rows = await widget.db.modelsFor(widget.loopId);
      if (mounted) setState(() { models = rows; loading = false; error = null; });
    } catch (e) { if (mounted) setState(() { error = '$e'; loading = false; }); }
  }

  Future<void> activate(StoredIdentification m) async {
    try { await widget.db.selectActiveModel(widget.loopId, m.id); await refresh(); }
    catch (e) { if (mounted) setState(() => error = '$e'); }
  }

  Future<void> editPoint(StoredIdentification m) async {
    final ctrl = TextEditingController(text: m.operatingPoint ?? '');
    final save = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('Рабочая точка'),
      content: TextField(controller: ctrl, maxLines: 3, decoration: const InputDecoration(
        labelText: 'Расход, давление, режим и положение клапана',
        hintText: 'Например: LNG 1400 м³/ч; 8 бар; MV 48%')),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Сохранить'))]));
    final value = ctrl.text;
    ctrl.dispose();
    if (save != true) return;
    try { await widget.db.updateOperatingPoint(widget.loopId, m.id, value); await refresh(); }
    catch (e) { if (mounted) setState(() => error = '$e'); }
  }

  bool running = false;
  Map<String, Object?>? lastResult;

  Future<void> runRobust() async {
    try {
      final chosen = models.where((m) => selected.contains(m.id)).toList();
      final selection = MultiModelSelection.validate(chosen, loopId:widget.loopId);
      setState(() { running = true; error = null; lastResult = null; });
      final result = await compute(calculateMultiModel, buildMultiModelArguments(selection));
      if (mounted) setState(() => lastResult = result);
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => running = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text('История · ${widget.loopTag}')),
    body: loading ? const Center(child: CircularProgressIndicator()) :
      ListView(padding: const EdgeInsets.all(12), children: [
        const Text('Выберите активную модель для Auto Tune и Stability. '
          'Отметьте несколько испытаний для просмотра диапазона параметров.'),
        if (error != null) Text(error!, style: const TextStyle(color: Colors.red)),
        for (final m in models) Card(child: ListTile(
          leading: Checkbox(value: selected.contains(m.id), onChanged: (v) =>
            setState(() { if (v == true) { selected.add(m.id); } else { selected.remove(m.id); } })),
          title: Text('Тест #${m.id} · ${m.source}${m.active ? ' · АКТИВНА' : ''}'),
          subtitle: Text('K=${m.k.toStringAsFixed(3)} · T=${m.tau.toStringAsFixed(2)} с · '
            'L=${m.delay.toStringAsFixed(2)} с\n'
            'R²=${m.rSquared?.toStringAsFixed(3) ?? 'н/д'} · '
            'NRMSE=${m.nrmse?.toStringAsFixed(3) ?? 'н/д'}\n'
            '${m.operatingPoint ?? 'Рабочая точка не указана'}'),
          isThreeLine: true,
          trailing: PopupMenuButton<String>(onSelected: (v) {
            if (v == 'activate') activate(m);
            if (v == 'point') editPoint(m);
          }, itemBuilder: (_) => [
            const PopupMenuItem(value: 'activate', child: Text('Сделать активной')),
            const PopupMenuItem(value: 'point', child: Text('Рабочая точка')),
          ]),
        )),
        if (selected.length >= 2) Builder(builder: (_) {
          final chosen = models.where((m) => selected.contains(m.id)).toList();
          double lo(Iterable<double> v) => v.reduce((a,b) => a < b ? a : b);
          double hi(Iterable<double> v) => v.reduce((a,b) => a > b ? a : b);
          return Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(
            crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Сравнение ${chosen.length} испытаний', style: Theme.of(context).textTheme.titleMedium),
              Text('K: ${lo(chosen.map((m) => m.k)).toStringAsFixed(3)} … ${hi(chosen.map((m) => m.k)).toStringAsFixed(3)}'),
              Text('T: ${lo(chosen.map((m) => m.tau)).toStringAsFixed(2)} … ${hi(chosen.map((m) => m.tau)).toStringAsFixed(2)} с'),
              Text('L: ${lo(chosen.map((m) => m.delay)).toStringAsFixed(2)} … ${hi(chosen.map((m) => m.delay)).toStringAsFixed(2)} с'),
              const Text('Для расчёта требуются ≥2 качественных Step Test с одинаковой рабочей точкой.'),
              const SizedBox(height: 8),
              FilledButton(onPressed: running ? null : runRobust,
                child: Text(running ? 'Вычисление…' : 'Robust Auto Tune + Stability')),
              if (running) const LinearProgressIndicator(),
              if (lastResult != null) ...[
                Text('Проверено сценариев: ${lastResult!['scenarioCount']} · '
                  'кандидатов: ${lastResult!['evaluated']} · '
                  'прошли оба критерия: ${lastResult!['accepted']}'),
                for (final c in (lastResult!['candidates'] as List).cast<Map<String, Object?>>().where((c)=>c['feasible'] == true).take(5))
                  Text('PB=${(c['pb'] as num).toStringAsFixed(2)}% · '
                    'Ti=${(c['ti'] as num).toStringAsFixed(2)} с · '
                    'Worst IAE=${(c['worstIae'] as num).toStringAsFixed(2)}'),
                Text(lastResult!['warning'] as String),
              ],
            ]))));
        }),
      ]),
  );
}

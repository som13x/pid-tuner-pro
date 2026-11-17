import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pid_tuner_pro_core/auto_tune.dart';
import 'package:pid_tuner_pro_core/dcs_controller_profiles.dart';
import 'main.dart' show AutoTuneScreen, StepTestScreen;
import 'package:pid_tuner_pro_core/step_identification.dart';
import 'stability_screen.dart' show StabilityScreen;
import 'project_store.dart';
import 'sqlite_project_store.dart';
import 'project_backup.dart';
import 'model_history_screen.dart';
import 'simulation_screen.dart';
import 'dual_valve_screen.dart';

class ProjectHome extends StatefulWidget {
  const ProjectHome({super.key});
  @override
  State<ProjectHome> createState() => _ProjectHomeState();
}

class _ProjectHomeState extends State<ProjectHome> {
  PidDatabase? _store;
  List<LoopProject> _projects = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final store = await PidDatabase.open(File('${dir.path}/pid_tuner/projects.sqlite'));
      await store.importLegacyIfEmpty(File('${dir.path}/pid_tuner/projects.json'));
      final projects = await store.load();
      if (!mounted) { await store.close(); return; }
      final oldStore = _store;
      setState(() { _store = store; _projects = projects; _error = null; _loading = false; });
      if (oldStore != null) await oldStore.close();
    } catch (e) {
      if (mounted) setState(() { _error = '$e'; _loading = false; });
    }
  }

  bool _backupBusy = false;

  Future<void> _exportBackup() async {
    if (_store == null || _backupBusy) return;
    setState(() => _backupBusy = true);
    try {
      final json = await _store!.exportProjectBackup();
      final fileName = 'pid-tuner-pro-backup-' +
        DateTime.now().toUtc().toIso8601String().substring(0, 10) + '.json';
      final location = await FilePicker.saveFile(
        dialogTitle: 'Сохранить резервную копию PID Tuner Pro',
        fileName: fileName,
        bytes: Uint8List.fromList(utf8.encode(json)),
      );
      if (!mounted || location == null) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Резервная копия сохранена. Храните файл вне приложения.')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалось экспортировать архив: ' + e.toString())));
    } finally {
      if (mounted) setState(() => _backupBusy = false);
    }
  }

  Future<void> _importBackup() async {
    if (_store == null || _backupBusy) return;
    setState(() => _backupBusy = true);
    try {
      final files = await FilePicker.pickFiles(
        type: FileType.custom, allowedExtensions: ['json']);
      if (files.isEmpty) return;
      final bytes = await files.single.readAsBytes();
      if (bytes.length > 25 * 1024 * 1024) {
        throw const FormatException('Архив превышает 25 МБ');
      }
      final json = utf8.decode(bytes, allowMalformed: false);
      final info = inspectProjectBackup(json);
      if (!mounted) return;
      final replace = _projects.isNotEmpty;
      final approved = await showDialog<bool>(context: context, builder: (ctx) =>
        AlertDialog(
          title: const Text('Восстановление архива'),
          content: Text('Найдено контуров: ' + info.loops.toString() +
            ', моделей: ' + info.identifications.toString() +
            ', событий: ' + info.events.toString() + '.\n\n' +
            (replace ? 'ВНИМАНИЕ: все текущие контуры и их история будут ЗАМЕНЕНЫ архивом. Сначала сохраните резервную копию существующих данных.' : 'Архив будет импортирован в пустую базу.')),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Отмена')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true),
              child: Text(replace ? 'Заменить данные' : 'Восстановить')),
          ],
        ));
      if (approved != true || !mounted) return;
      await _store!.restoreProjectBackup(json, replaceExisting: replace);
      final projects = await _store!.load();
      if (!mounted) return;
      setState(() => _projects = projects);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Проекты и история успешно восстановлены.')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка восстановления: ' + e.toString())));
    } finally {
      if (mounted) setState(() => _backupBusy = false);
    }
  }

  Future<void> _create() async {
    final tag = TextEditingController();
    final description = TextEditingController();
    var profile = DcsProfiles.yokogawaCentumVp;
    final result = await showDialog<bool>(context: context, builder: (context) =>
      StatefulBuilder(builder: (context, refreshDialog) => AlertDialog(title: const Text('Новый контур'), content: Column(
        mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: tag, decoration: const InputDecoration(labelText: 'Тег (например FIC-80B)')),
          TextField(controller: description, decoration: const InputDecoration(labelText: 'Описание')),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: profile.id, isExpanded: true,
            decoration: const InputDecoration(labelText: 'Профиль DCS'),
            items: [
              for (final p in DcsProfiles.all)
                DropdownMenuItem(value: p.id, child: Text(p.title,
                  overflow: TextOverflow.ellipsis)),
            ],
            onChanged: (id) {
              if (id != null) refreshDialog(() => profile = DcsProfiles.byId(id));
            },
          ),
          const SizedBox(height: 8),
          const Text('Только пересчёт PB/GAIN для нормированного PI. '
              'Не является эмулятором DCS.', style: TextStyle(fontSize: 12)),
        ]), actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Отмена')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Создать')),
        ])));
    if (!mounted || result != true || tag.text.trim().isEmpty || _store == null) {
      tag.dispose(); description.dispose(); return;
    }
    final now = DateTime.now().toUtc();
    final project = LoopProject(
      id: now.microsecondsSinceEpoch.toString(), tag: tag.text.trim(),
      description: description.text.trim(), vendor: profile.storedVendor,
      controllerBlock: profile.storedBlock, createdAt: now);
    tag.dispose(); description.dispose();
    try {
      final next = [..._projects, project];
      await _store!.save(next);
      if (mounted) setState(() => _projects = next);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Ошибка сохранения: $e')));
    }
  }

  Future<void> _changeProfile(LoopProject project) async {
    final current = DcsProfiles.forProject(project.vendor, project.controllerBlock);
    var profile = current ?? DcsProfiles.yokogawaCentumVp;
    final approved = await showDialog<bool>(context: context,
      builder: (ctx) => StatefulBuilder(builder: (context, refreshDialog) =>
        AlertDialog(
          title: Text('Профиль DCS · ' + project.tag),
          content: SingleChildScrollView(child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Текущий: ' + project.vendor + ' · ' + project.controllerBlock),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                initialValue: profile.id, isExpanded: true,
                decoration: const InputDecoration(labelText: 'Профиль'),
                items: [
                  for (final p in DcsProfiles.all)
                    DropdownMenuItem(value: p.id, child: Text(p.title,
                      overflow: TextOverflow.ellipsis)),
                ],
                onChanged: (id) {
                  if (id != null) refreshDialog(() => profile = DcsProfiles.byId(id));
                },
              ),
              const SizedBox(height: 12),
              const Text('Изменение профиля не меняет K/T/L и прошлые отчёты. '
                  'Перед применением настроек проверьте блок, алгоритм, '
                  'масштабирование PV/MV и направление действия.'),
            ],
          )),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Отмена')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Сохранить профиль')),
          ],
        )));
    if (!mounted || approved != true) return;
    try {
      await _update(project, project.withControllerProfile(
        vendorName: profile.storedVendor, blockName: profile.storedBlock));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка изменения профиля: $e')));
    }
  }

  Future<void> _remove(LoopProject project) async {
    final confirmed = await showDialog<bool>(context: context, builder: (context) => AlertDialog(
      title: Text('Удалить ${project.tag}?'),
      content: const Text('Локальная карточка контура будет удалена.'),
      actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Отмена')),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Удалить'))]));
    if (confirmed != true || _store == null) return;
    final next = _projects.where((p) => p.id != project.id).toList();
    try { await _store!.save(next); if (mounted) setState(() => _projects = next); }
    catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e'))); }
  }

  Future<void> _update(LoopProject original, LoopProject updated) async {
    final next = _projects.map((p) => p.id == original.id ? updated : p).toList();
    await _store!.save(next);
    if (mounted) setState(() => _projects = next);
  }

  Future<void> _stepTest(LoopProject project) async {
    final fit = await Navigator.of(context).push<IdentificationResult>(
      MaterialPageRoute(builder: (_) => const StepTestScreen()));
    if (fit == null || !mounted) return;
    if (!fit.suitableForAutoTune) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Качество идентификации недостаточно для Auto Tune')));
      return;
    }
    try {
      await _update(project, project.withIdentification(
        model: {'K': fit.plant.gain, 'T': fit.plant.tau, 'L': fit.plant.delay},
        source: 'Step Test CSV', rSquared: fit.rSquared,
        nrmse: fit.normalizedRmse));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> _autoTune(LoopProject project) async {
    final m = project.identifiedModel;
    if (m == null) return;
    final report = await Navigator.of(context).push<Map<String, dynamic>>(
      MaterialPageRoute(builder: (_) => AutoTuneScreen(
        initialPlant: Plant(gain: m['K']!, tau: m['T']!, delay: m['L']!),
        profile: DcsProfiles.forProject(project.vendor, project.controllerBlock),
        allowSave: true)));
    if (report == null || !mounted) return;
    try { await _update(project, project.withTuneReport(report)); }
    catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e'))); }
  }

  void _open(Widget screen) => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => screen));

  @override
  void dispose() {
    _store?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('PID Tuner Pro'), actions: [
      IconButton(tooltip: 'Обновить', onPressed: _load, icon: const Icon(Icons.refresh)),
      PopupMenuButton<String>(
        tooltip: 'Резервные копии',
        enabled: !_backupBusy && _store != null,
        icon: const Icon(Icons.save_alt),
        onSelected: (value) {
          if (value == 'export') { _exportBackup(); }
          if (value == 'import') { _importBackup(); }
        },
        itemBuilder: (_) => const [
          PopupMenuItem(value: 'export', child: Text('Экспортировать архив JSON')),
          PopupMenuItem(value: 'import', child: Text('Восстановить из JSON')),
        ],
      ),
    ]),
    floatingActionButton: FloatingActionButton.extended(onPressed: _create,
      icon: const Icon(Icons.add), label: const Text('Новый контур')),
    body: _loading ? const Center(child: CircularProgressIndicator())
      : _error != null ? Center(child: Text('Ошибка загрузки: $_error'))
      : ListView(padding: const EdgeInsets.all(16), children: [
          const Text('Проекты и контуры', style: TextStyle(fontSize: 23, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          const Text('Локальная инженерная среда. Расчёты не отправляются в DCS.'),
          const SizedBox(height: 16),
          if (_projects.isEmpty) const Card(child: Padding(padding: EdgeInsets.all(20),
            child: Text('Пока нет контуров. Создайте первый проект.'))),
          for (final p in _projects) Card(child: ExpansionTile(
            title: Text(p.tag), subtitle: Text('${p.description}\n${p.vendor} · ${p.controllerBlock}'),
            children: [
              Wrap(spacing: 8, children: [
                OutlinedButton(onPressed: () => _stepTest(p), child: const Text('Step Test')),
                OutlinedButton(onPressed: () => _changeProfile(p), child: const Text('Профиль DCS')),
                OutlinedButton(onPressed: _store == null ? null : () async {
                  await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) =>
                    ModelHistoryScreen(db: _store!, loopId: p.id, loopTag: p.tag)));
                  if (!mounted) return;
                  final refreshed = await _store!.load();
                  if (mounted) setState(() => _projects = refreshed);
                }, child: const Text('История моделей')),
                OutlinedButton(onPressed: p.identifiedModel == null ? null : () => _autoTune(p),
                  child: const Text('Auto Tune')),
                OutlinedButton(onPressed: p.identifiedModel == null ? null : () =>
                  _open(StabilityScreen(initialModel: p.identifiedModel)),
                  child: const Text('Stability')),
                OutlinedButton(onPressed: p.identifiedModel == null ? null : () =>
                  _open(SimulationScreen(initialModel: p.identifiedModel)),
                  child: const Text('Simulation')),
                OutlinedButton(onPressed: () => _open(DualValveScreen(loopTag: p.tag)),
                  child: const Text('Dual-Valve LNG')),
                IconButton(tooltip: 'Удалить контур', onPressed: () => _remove(p), icon: const Icon(Icons.delete_outline)),
              ]),
              if (p.identifiedModel == null) const Padding(padding: EdgeInsets.all(8),
                child: Text('Сначала выполните Step Test и сохраните модель.')),
              if (p.identifiedModel != null) Padding(padding: const EdgeInsets.all(8),
                child: Text('K=${p.identifiedModel!['K']} · T=${p.identifiedModel!['T']} с · L=${p.identifiedModel!['L']} с')),
              Padding(padding: const EdgeInsets.all(8),
                child: Text('Событий в истории: ${p.history.length}')),

            ],
          )),
        ]),
  );
}

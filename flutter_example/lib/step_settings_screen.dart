import 'package:flutter/material.dart';
import 'package:pid_tuner_pro_core/dcs_controller_profiles.dart';
import 'package:pid_tuner_pro_core/step_test_settings.dart';

/// Safari Settings preceding the Step Test. Saving is explicit and durable:
/// the screen only reports success when IndexedDB transaction completes.
class StepSettingsScreen extends StatefulWidget {
  final StepTestSettings? initialSettings;
  final Future<void> Function(StepTestSettings) onSave;

  const StepSettingsScreen({
    super.key,
    this.initialSettings,
    required this.onSave,
  });

  @override
  State<StepSettingsScreen> createState() => _StepSettingsScreenState();
}

class _StepSettingsScreenState extends State<StepSettingsScreen> {
  late final TextEditingController tag;
  late final TextEditingController comments;
  late String profileId;
  late ControlledVariable variable;
  late TuningMethod tuningMethod;
  late StepAcquisition acquisition;
  late bool selfRegulatingLevelConfirmed;
  bool saving = false;
  String? error;

  @override
  void initState() {
    super.initState();
    final initial = widget.initialSettings;
    tag = TextEditingController(text: initial?.tag ?? '');
    comments = TextEditingController(text: initial?.comments ?? '');
    profileId = initial?.profileId ?? DcsProfiles.yokogawaCentumVp.id;
    variable = initial?.controlledVariable ?? ControlledVariable.flow;
    tuningMethod = initial?.tuningMethod ??
      StepTestSettings.recommendedFor(variable);
    acquisition = initial?.acquisition ?? StepAcquisition.manualDelayAndT63;
    selfRegulatingLevelConfirmed =
      initial?.selfRegulatingLevelConfirmed ?? false;
  }

  @override
  void dispose() {
    tag.dispose();
    comments.dispose();
    super.dispose();
  }

  Future<void> save() async {
    setState(() { saving = true; error = null; });
    try {
      final selected = StepTestSettings(
        tag: tag.text,
        comments: comments.text,
        profileId: profileId,
        controlledVariable: variable,
        tuningMethod: tuningMethod,
        acquisition: acquisition,
        selfRegulatingLevelConfirmed: selfRegulatingLevelConfirmed,
      );
      selected.validate();
      await widget.onSave(selected);
    } catch (e) {
      if (mounted) setState(() => error = 'Не сохранено: ' + e.toString());
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  InputDecoration inputDecoration(String label) => InputDecoration(
    border: const OutlineInputBorder(), labelText: label,
    isDense: true,
  );

  @override
  Widget build(BuildContext context) {
    final profile = DcsProfiles.byId(profileId);
    final recommended = StepTestSettings.recommendedFor(variable);
    final label = profile.proportionalParameter ==
        ProportionalParameter.bandPercent
      ? 'PB (%) = 100 / Kc'
      : 'Kc (нормированный) = 100 / PB (%)';
    return ListView(
      key: const Key('settings-form'),
      padding: const EdgeInsets.all(16),
      children: [
        Text('Settings · параметры контура',
          style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        const Text('Поля Settings сохраняются в IndexedDB на этом '
          'устройстве. Данные не отправляются в облако.'),
        const SizedBox(height: 14),
        TextField(
          key: const Key('settings-tag'),
          controller: tag,
          maxLength: 120,
          decoration: inputDecoration('1. Название контура / TAG *'),
        ),
        const SizedBox(height: 10),
        TextField(
          key: const Key('settings-comments'),
          controller: comments,
          maxLines: 3,
          maxLength: 2000,
          decoration: inputDecoration('2. Комментарии'),
        ),
        const SizedBox(height: 10),
        DropdownButtonFormField<String>(
          key: const Key('settings-system'),
          initialValue: profileId,
          isExpanded: true,
          decoration: inputDecoration('3. Система DCS'),
          items: DcsProfiles.all.map((p) => DropdownMenuItem(
            value: p.id,
            child: Text(p.vendor + ' · ' + p.system),
          )).toList(),
          onChanged: (next) {
            if (next != null) setState(() => profileId = next);
          },
        ),
        const SizedBox(height: 10),
        Text('Предполагаемый блок: ' + profile.block +
          '. Отображение PI: ' + label + '.',
          style: const TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        Text(profile.warning,
          style: TextStyle(color: Theme.of(context).colorScheme.error)),
        const SizedBox(height: 16),
        DropdownButtonFormField<ControlledVariable>(
          key: const Key('settings-variable'),
          initialValue: variable,
          isExpanded: true,
          decoration: inputDecoration('4. Регулируемая величина'),
          items: ControlledVariable.values.map((v) => DropdownMenuItem(
            value: v, child: Text(v.title),
          )).toList(),
          onChanged: (next) {
            if (next == null) return;
            setState(() {
              variable = next;
              tuningMethod = StepTestSettings.recommendedFor(next);
              if (next != ControlledVariable.level) {
                selfRegulatingLevelConfirmed = false;
              }
            });
          },
        ),
        const SizedBox(height: 12),
        const Text('5. Рекомендуемый метод расчёта PI',
          style: TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        Text(recommended.title),
        Text(recommended.explanation),
        if (variable == ControlledVariable.level) ...[
          const SizedBox(height: 8),
          CheckboxListTile(
            key: const Key('settings-level-confirm'),
            title: const Text('Подтверждено, что процесс уровня '
              'самовыравнивающийся (не интегрирующий)'),
            subtitle: const Text('Для интегрирующего уровня '
              'модель FOPDT может быть неприменима.'),
            value: selfRegulatingLevelConfirmed,
            onChanged: (b) => setState(() =>
              selfRegulatingLevelConfirmed = b ?? false),
          ),
        ],
        const SizedBox(height: 16),
        DropdownButtonFormField<TuningMethod>(
          key: const Key('settings-tuning-method'),
          initialValue: tuningMethod,
          isExpanded: true,
          decoration: inputDecoration('6. Выбранный метод расчёта PI'),
          items: TuningMethod.values.map((m) => DropdownMenuItem(
            value: m,
            child: Text(m.title, overflow: TextOverflow.ellipsis),
          )).toList(),
          onChanged: (next) {
            if (next != null) setState(() => tuningMethod = next);
          },
        ),
        const SizedBox(height: 6),
        Text(tuningMethod.explanation),
        const SizedBox(height: 10),
        const Text('Формулы рассчитывают эквивалент PI (D = 0) в '
          'нормированных процентах MV/PV. Выбор производителя '
          'меняет отображаемый параметр, а НЕ передаточную функцию '
          'объекта. Алгоритм конкретного блока, время интегрирования '
          'и шкалы надо проверить по документации DCS.'),
        const SizedBox(height: 16),
        DropdownButtonFormField<StepAcquisition>(
          key: const Key('settings-step-method'),
          initialValue: acquisition,
          isExpanded: true,
          decoration: inputDecoration('7. Как проводить Step Test'),
          items: StepAcquisition.values.map((m) => DropdownMenuItem(
            value: m, child: Text(m.title,
              overflow: TextOverflow.ellipsis),
          )).toList(),
          onChanged: (next) {
            if (next != null) setState(() => acquisition = next);
          },
        ),
        const SizedBox(height: 12),
        Text('Инструкция · ' + acquisition.title,
          style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        SelectableText(acquisition.instructions),
        const SizedBox(height: 12),
        const Text('Важно: прежде чем воздействовать на '
          'действующий контур, необходимы оценка рисков, '
          'разрешение и утверждённая процедура испытания. '
          'Приложение не изменяет сигналы DCS.'),
        if (error != null) Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Text(error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error)),
        ),
        const SizedBox(height: 18),
        FilledButton.icon(
          key: const Key('settings-save'),
          onPressed: saving ? null : save,
          icon: const Icon(Icons.save_outlined),
          label: Text(saving ? 'Сохранение…'
            : 'Сохранить Settings и перейти в Step Test'),
        ),
        const SizedBox(height: 28),
      ],
    );
  }
}

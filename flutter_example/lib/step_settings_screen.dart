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
  late final TextEditingController stabilityMargin;
  late String profileId;
  late ControlledVariable variable;
  late TuningMethod tuningMethod;
  late StepAcquisition acquisition;
  late bool selfRegulatingLevelConfirmed;
  late bool integratingProcessConfirmed;
  late LevelControlMode levelControlMode;
  bool saving = false;
  String? error;

  @override
  void initState() {
    super.initState();
    final initial = widget.initialSettings;
    tag = TextEditingController(text: initial?.tag ?? '');
    comments = TextEditingController(text: initial?.comments ?? '');
    stabilityMargin = TextEditingController(
      text: (initial?.stabilityMargin ?? 2.0).toString());
    profileId = initial?.profileId ?? DcsProfiles.yokogawaCentumVp.id;
    variable = initial?.controlledVariable ?? ControlledVariable.flow;
    // Never silently turn an old saved SIMC calculation into
    // OptiControls. The user must review and save this new selection.
    tuningMethod = initial?.tuningMethod == TuningMethod.integratingProcessSimc
      ? TuningMethod.opticontrolsLevel
      : (initial?.tuningMethod ?? StepTestSettings.recommendedFor(variable));
    acquisition = initial?.acquisition ?? StepAcquisition.manualDelayAndT63;
    selfRegulatingLevelConfirmed =
      initial?.selfRegulatingLevelConfirmed ?? false;
    integratingProcessConfirmed =
      initial?.tuningMethod == TuningMethod.integratingProcessSimc
        ? false : (initial?.integratingProcessConfirmed ?? false);
    levelControlMode = initial?.levelControlMode ?? LevelControlMode.pi;
  }

  @override
  void dispose() {
    tag.dispose();
    comments.dispose();
    stabilityMargin.dispose();
    super.dispose();
  }

  Future<void> save() async {
    setState(() { saving = true; error = null; });
    try {
      final sm = double.parse(
        stabilityMargin.text.trim().replaceAll(',', '.'));
      final selected = StepTestSettings(
        tag: tag.text,
        comments: comments.text,
        profileId: profileId,
        controlledVariable: variable,
        tuningMethod: tuningMethod,
        acquisition: acquisition,
        selfRegulatingLevelConfirmed: selfRegulatingLevelConfirmed,
        integratingProcessConfirmed: integratingProcessConfirmed,
        // Keep old SIMC-specific lambda out of new calculations.
        lambdaSeconds: null,
        stabilityMargin: sm,
        levelControlMode: levelControlMode,
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
        if (widget.initialSettings?.tuningMethod ==
            TuningMethod.integratingProcessSimc)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text('Внимание: ранее сохранённые настройки SIMC '
              'не конвертируются автоматически. Проверьте SM, PI/PID '
              'и сохраните новый метод OptiControls перед расчётом.',
              style: TextStyle(
                color: Theme.of(context).colorScheme.error)),
          ),
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
              acquisition = tuningMethod == TuningMethod.integratingProcessSimc
                ? StepAcquisition.manualIntegratingSlope
                : StepAcquisition.manualDelayAndT63;
              integratingProcessConfirmed = false;
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
        if (variable == ControlledVariable.level &&
            tuningMethod != TuningMethod.opticontrolsLevel) ...[
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
          key: ValueKey('settings-tuning-method-' +
            variable.name + '-' + tuningMethod.name),
          initialValue: tuningMethod,
          isExpanded: true,
          decoration: inputDecoration('6. Выбранный метод расчёта PI'),
          items: TuningMethod.values
            .where((m) => m != TuningMethod.integratingProcessSimc)
            .map((m) => DropdownMenuItem(
              value: m,
              child: Text(m.title, overflow: TextOverflow.ellipsis),
            )).toList(),
          onChanged: (next) {
            if (next != null) setState(() {
              final wasIntegrating =
                tuningMethod == TuningMethod.opticontrolsLevel;
              tuningMethod = next;
              final isIntegrating = next == TuningMethod.opticontrolsLevel;
              if (isIntegrating != wasIntegrating) {
                acquisition = isIntegrating
                  ? StepAcquisition.manualIntegratingSlope
                  : StepAcquisition.manualDelayAndT63;
              }
            });
          },
        ),
        const SizedBox(height: 6),
        Text(tuningMethod.explanation),
        if (tuningMethod == TuningMethod.opticontrolsLevel) ...[
          const SizedBox(height: 10),
          CheckboxListTile(
            key: const Key('settings-integrating-confirm'),
            title: const Text('Подтверждён интегрирующий характер объекта '
              '(PV не выходит на новый установившийся уровень)'),
            subtitle: const Text('Без подтверждения измерения '
              'сохраняются, но параметры PI/PID не рассчитываются.'),
            value: integratingProcessConfirmed,
            onChanged: (v) => setState(() =>
              integratingProcessConfirmed = v ?? false),
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<LevelControlMode>(
            key: const Key('settings-level-mode'),
            initialValue: levelControlMode,
            decoration: inputDecoration('Алгоритм OptiControls: PI или PID'),
            items: const [
              DropdownMenuItem(value: LevelControlMode.pi,
                child: Text('PI · Td = 0')),
              DropdownMenuItem(value: LevelControlMode.pid,
                child: Text('PID · Td = td / 2')),
            ],
            onChanged: (next) {
              if (next != null) setState(() => levelControlMode = next);
            },
          ),
          const SizedBox(height: 10),
          TextField(
            key: const Key('settings-stability-margin'),
            controller: stabilityMargin,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: inputDecoration('Stability Margin SM (≥ 2)'),
          ),
          const SizedBox(height: 5),
          const Text('OptiControls: рекомендуется SM ≥ 2. '
            'Повышение SM делает настройку менее агрессивной. '
            'Коэффициент ri измеряется по изменению наклона PV; '
            'запаздывание td обязательно > 0. '
            'Для буферных ёмкостей с целью усреднения расхода '
            'нужны другие правила настройки.'),
        ],
        const SizedBox(height: 10),
        const Text('Настройки PI/PID рассчитываются в процентах '
          'шкал MV/PV. Для OptiControls исходные правила предполагают '
          'взаимодействующую форму PID; конкретную DCS, '
          'время интегрирования, производную и преобразование '
          'в параллельную форму нужно проверить по документации.'),
        const SizedBox(height: 16),
        DropdownButtonFormField<StepAcquisition>(
          key: ValueKey('settings-step-method-' +
            tuningMethod.name + '-' + acquisition.name),
          initialValue: acquisition,
          isExpanded: true,
          decoration: inputDecoration('7. Как проводить Step Test'),
          items: StepAcquisition.values.where((m) =>
            tuningMethod == TuningMethod.engineeringReview ||
            (tuningMethod == TuningMethod.opticontrolsLevel) ==
            (m == StepAcquisition.manualIntegratingSlope ||
              m == StepAcquisition.csvIntegratingTrend)
          ).map((m) => DropdownMenuItem(
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

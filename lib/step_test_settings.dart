import 'dart:math' as math;

import 'auto_tune.dart';
import 'integrating_step_identification.dart';
import 'dcs_controller_profiles.dart';

/// Step-test context is immutable and portable across browsers and DBs.
/// All tuning equations use percent-of-span PV/MV and ideal PI (Td=0).
enum ControlledVariable { flow, pressure, temperature, level, other }

enum TuningMethod {
  imcConservative,
  zieglerNicholsOpenLoop,
  cohenCoonOpenLoop,
  integratingProcessSimc,
  engineeringReview,
}

enum StepAcquisition {
  manualDelayAndT63,
  manualTwoPoints,
  csvTrend,
  manualIntegratingSlope,
  csvIntegratingTrend,
}

extension ControlledVariableText on ControlledVariable {
  String get title => switch (this) {
    ControlledVariable.flow => 'Расход',
    ControlledVariable.pressure => 'Давление',
    ControlledVariable.temperature => 'Температура',
    ControlledVariable.level => 'Уровень',
    ControlledVariable.other => 'Другое',
  };
}

extension TuningMethodText on TuningMethod {
  String get title => switch (this) {
    TuningMethod.imcConservative => 'IMC / Lambda (консервативный PI)',
    TuningMethod.zieglerNicholsOpenLoop =>
      'Ziegler–Nichols (разомкнутый контур, PI)',
    TuningMethod.cohenCoonOpenLoop =>
      'Cohen–Coon (разомкнутый контур, PI)',
    TuningMethod.integratingProcessSimc =>
      'Tuning Rules for an Integrating Process (SIMC PI)',
    TuningMethod.engineeringReview =>
      'Без автоматической настройки / инженерная проверка',
  };

  String get explanation => switch (this) {
    TuningMethod.imcConservative =>
      'PI, Kc = T / (|K| × (λ + L)), Ti = T. '
      'λ выбирается с запасом по скорости объекта. '
      'Рекомендация по умолчанию для самовыравнивающихся процессов.',
    TuningMethod.zieglerNicholsOpenLoop =>
      'PI, Kc = 0,9 × T / (|K| × L), Ti = 3,33 × L. '
      'Требуется L > 0. Может давать агрессивный переходный процесс.',
    TuningMethod.cohenCoonOpenLoop =>
      'PI: Kc = T / (|K| × L) × (0,9 + L/(12T)); '
      'Ti = L × (30 + 3L/T)/(9 + 20L/T). '
      'Требуется L > 0; контролируйте устойчивость.',
    TuningMethod.integratingProcessSimc =>
      'Для IPDT-модели G(s)=Ki·exp(-Ls)/s. '
      'SIMC PI: Kc=1/(|Ki|·(λ+L)), Ti=4(λ+L), Td=0. '
      'Ki в (%PV/с)/(%MV), λ и L в секундах. '
      'Обычные FOPDT K/T/L и время t63 здесь не применяются. '
      'Это теоретический расчёт, не готовые параметры блока DCS.',
    TuningMethod.engineeringReview =>
      'PID/PI автоматически не рассчитывается. Требуется адекватная '
      'модель процесса и проверка специалистом.',
  };
}

extension StepAcquisitionText on StepAcquisition {
  String get title => switch (this) {
    StepAcquisition.manualDelayAndT63 =>
      'Ручной: запаздывание L и 63,21% PV',
    StepAcquisition.manualTwoPoints =>
      'Ручной: 28,35% и 63,21% PV',
    StepAcquisition.csvTrend =>
      'CSV: запись тренда PV/MV во времени',
    StepAcquisition.manualIntegratingSlope =>
      'Интегрирующий: ручной замер наклона PV',
    StepAcquisition.csvIntegratingTrend =>
      'Интегрирующий: CSV ступени MV и наклона PV',
  };

  String get instructions => switch (this) {
    StepAcquisition.manualDelayAndT63 =>
      '1. Согласуйте безопасные границы изменения MV, ограничения '
      'оборудования и возможность испытания. Переведите контур '
      'в MAN только по утверждённой процедуре.\n'
      '2. После стабилизации зафиксируйте MV0 и PV0. '
      'Сделайте одну небольшую ступень MV, без повторных воздействий.\n'
      '3. Зафиксируйте момент ступени, измерьте видимое запаздывание L '
      'и время от подачи ступени до 63,21% полного изменения PV.\n'
      '4. Дождитесь установившейся PV1. Введите MV0, MV1, PV0, PV1 '
      'и границы инженерных шкал. Расчёт: T = t63 - L.',
    StepAcquisition.manualTwoPoints =>
      '1. Проверьте разрешения и ограничения; обеспечьте '
      'стабильный исходный режим, выполняйте только согласованное '
      'одиночное ступенчатое изменение MV в MAN.\n'
      '2. Запишите MV0, MV1, PV0 и конечную установившуюся PV1.\n'
      '3. От момента ступени MV засеките два абсолютных времени: '
      'при достижении 28,35% и 63,21% полного изменения PV.\n'
      '4. Введите времена t28 и t63 в секундах и шкалы MV/PV. '
      'T = 1,5(t63-t28); L = t63-T. '
      'Если результат не причинно-следственный, не применяйте модель.',
    StepAcquisition.manualIntegratingSlope =>
      '1. По утверждённой процедуре убедитесь, что изменение уровня '
      'или другой PV можно безопасно остановить; проверьте аварийные '
      'пределы, запасы ёмкости и безопасный выход из испытания.\n'
      '2. До одной небольшой ступени MV зафиксируйте исходный '
      'наклон PV (единицы PV в секунду), MV0 и MV1.\n'
      '3. Измерьте запаздывание L. На участке устойчивого '
      'линейного изменения PV ПОСЛЕ L запишите PV(t1), PV(t2) '
      'и t1/t2 от момента ступени. Не ждите новой установившейся PV: '
      'у интегрирующего объекта её может не быть.\n'
      '4. Ki=[(PV2-PV1)/(t2-t1)-наклон до ступени]/ΔMV; '
      'приложение нормирует шкалы MV/PV. Верните процесс '
      'в безопасное состояние по согласованной процедуре.',
    StepAcquisition.csvIntegratingTrend =>
      '1. Проверьте ограничения PV/MV и возможность безопасно '
      'прекратить испытание. Запишите равномерный тренд до и '
      'после одиночной ступени MV в ручном режиме.\n'
      '2. Сохраните CSV time,mv,pv с моментом изменения MV; '
      'записывайте как исходный наклон PV, так и линейный '
      'участок после запаздывания.\n'
      '3. Программа оценит изменение наклона PV и запаздывание L. '
      'Проверьте совпадение модели и фактического тренда.\n'
      '4. Не допускайте достижения пределов уровня/давления; '
      'не переносите расчётные PI в DCS без проверки.',
    StepAcquisition.csvTrend =>
      '1. Согласуйте безопасное испытание. Запишите равномерный 
      'тренд MV и PV, включая устойчивый участок ДО ступени '
      'и достаточно длинный участок ПОСЛЕ неё.\n'
      '2. По утверждённой процедуре выполняйте только одну '
      'устойчивую ступень MV в ручном режиме без посторонних возмущений.\n'
      '3. Экспортируйте CSV/TXT: time,mv,pv, где time в секундах. '
      'Укажите шкалы и, при необходимости, момент ступени.\n'
      '4. Проверьте качество идентификации R²/NRMSE и совпадение '
      'расчётной кривой с фактическим процессом.',
  };
}

class StepTestSettings {
  final String tag;
  final String comments;
  final String profileId;
  final ControlledVariable controlledVariable;
  final TuningMethod tuningMethod;
  final StepAcquisition acquisition;
  final bool selfRegulatingLevelConfirmed;
  final bool integratingProcessConfirmed;
  final double? lambdaSeconds;

  const StepTestSettings({
    required this.tag,
    this.comments = '',
    required this.profileId,
    required this.controlledVariable,
    required this.tuningMethod,
    required this.acquisition,
    this.selfRegulatingLevelConfirmed = false,
    this.integratingProcessConfirmed = false,
    this.lambdaSeconds,
  });

  DcsControllerProfile get profile => DcsProfiles.byId(profileId);

  static TuningMethod recommendedFor(ControlledVariable variable) =>
      variable == ControlledVariable.level
          ? TuningMethod.integratingProcessSimc
          : TuningMethod.imcConservative;

  TuningMethod get recommendedMethod =>
      recommendedFor(controlledVariable);

  bool get isIntegratingMethod =>
      tuningMethod == TuningMethod.integratingProcessSimc;

  bool get isIntegratingAcquisition =>
      acquisition == StepAcquisition.manualIntegratingSlope ||
      acquisition == StepAcquisition.csvIntegratingTrend;

  bool get canCalculate =>
      tuningMethod != TuningMethod.engineeringReview &&
      (isIntegratingMethod
        ? integratingProcessConfirmed
        : !isIntegratingAcquisition &&
          (controlledVariable != ControlledVariable.level ||
            selfRegulatingLevelConfirmed));

  String? get tuningBlockReason {
    if (tuningMethod == TuningMethod.engineeringReview) {
      return 'Выбран метод без автоматического PI-расчёта.';
    }
    if (isIntegratingMethod) {
      if (!integratingProcessConfirmed) {
        return 'Подтвердите по реакции PV, что объект интегрирующий.';
      }
       return null;
    }
    if (isIntegratingAcquisition) {
      return 'Для интегрирующего Step Test выберите SIMC-правила.';
    }
    if (controlledVariable == ControlledVariable.level &&
        !selfRegulatingLevelConfirmed) {
      return 'Для регулирования уровня требуется подтвердить, что '
          'процесс самовыравнивающийся. Интегрирующий уровень нельзя '
          'надёжно настроить по обычной FOPDT-модели.';
    }
    return null;
  }

  void validate() {
    if (tag.trim().isEmpty || tag.trim().length > 120 ||
        comments.length > 2000) {
      throw ArgumentError('Название контура обязательно; '
          'комментарий не должен превышать 2000 символов.');
    }
    profile;
    if (lambdaSeconds != null &&
        (!lambdaSeconds!.isFinite || lambdaSeconds! <= 0 ||
        lambdaSeconds! > 8640000)) {
      throw ArgumentError('Lambda must be in (0, 8640000] seconds');
    }
    if (isIntegratingMethod != isIntegratingAcquisition &&
        tuningMethod != TuningMethod.engineeringReview) {
      throw ArgumentError('Выбранный метод настройки не соответствует '
        'типу Step Test: FOPDT или интегрирующий (IPDT).');
    }
  }

  Map<String, Object?> toJson() => {
    'schemaVersion': 1,
    'tag': tag.trim(),
    'comments': comments.trim(),
    'profileId': profileId,
    'controlledVariable': controlledVariable.name,
    'tuningMethod': tuningMethod.name,
    'acquisition': acquisition.name,
    'selfRegulatingLevelConfirmed': selfRegulatingLevelConfirmed,
    'integratingProcessConfirmed': integratingProcessConfirmed,
    'lambdaSeconds': lambdaSeconds,
  };

  factory StepTestSettings.fromJson(Map<String, dynamic> raw) {
    if (raw['schemaVersion'] != 1) {
      throw const FormatException('Неподдерживаемая версия Settings');
    }
    T parse<T extends Enum>(List<T> values, Object? v, String field) {
      if (v is! String) throw FormatException('Неверное поле: ' + field);
      for (final value in values) {
        if (value.name == v) return value;
      }
      throw FormatException('Неизвестное значение: ' + field);
    }
    final s = StepTestSettings(
      tag: raw['tag'] as String,
      comments: raw['comments'] as String? ?? '',
      profileId: raw['profileId'] as String,
      controlledVariable: parse(ControlledVariable.values,
        raw['controlledVariable'], 'controlledVariable'),
      tuningMethod: parse(TuningMethod.values,
        raw['tuningMethod'], 'tuningMethod'),
      acquisition: parse(StepAcquisition.values,
        raw['acquisition'], 'acquisition'),
      selfRegulatingLevelConfirmed:
        raw['selfRegulatingLevelConfirmed'] == true,
      integratingProcessConfirmed:
        raw['integratingProcessConfirmed'] == true,
      lambdaSeconds: raw['lambdaSeconds'] == null ? null
        : (raw['lambdaSeconds'] as num).toDouble(),
    );
    s.validate();
    return s;
  }
}

class StepPiEstimate {
  final double kcNormalized;
  final double pbPercent;
  final double tiSeconds;
  final double tdSeconds;
  final double lambdaSeconds;
  final DcsTuningDisplay display;
  final TuningMethod method;

  const StepPiEstimate({
    required this.kcNormalized,
    required this.pbPercent,
    required this.tiSeconds,
    required this.tdSeconds,
    required this.lambdaSeconds,
    required this.display,
    required this.method,
  });

  Map<String, Object?> toJson() => {
    'algorithm': 'ideal-PI-normalized',
    'method': method.name,
    'kcNormalized': kcNormalized,
    'pbPercent': pbPercent,
    'tiSeconds': tiSeconds,
    'tdSeconds': tdSeconds,
    'lambdaSeconds': lambdaSeconds,
    'dcsDisplay': display.toJson(),
    'verifiedForDcsDeployment': false,
  };
}

/// Evaluates theoretical PI correlations for *offline review*.
/// A DCS vendor selection changes representation and warning, not plant
/// physics; proprietary block-specific implementation is NOT assumed.
class StepPiCalculator {
  const StepPiCalculator();

  StepPiEstimate calculate(Plant plant, StepTestSettings settings) {
    settings.validate();
    if (settings.isIntegratingMethod) {
      throw StateError('An IPDT model is required; '
        'use calculateIntegrating, not FOPDT');
    }
    plant.validate();
    if (!settings.canCalculate) {
      throw StateError(settings.tuningBlockReason ?? 'PI unavailable');
    }
    final k = plant.gain.abs();
    final t = plant.tau;
    final l = plant.delay;
    late double kc, ti;
    var lambda = 0.0;
    switch (settings.tuningMethod) {
      case TuningMethod.imcConservative:
        final factor = switch (settings.controlledVariable) {
          ControlledVariable.temperature => 2.0,
          ControlledVariable.level => 3.0,
          ControlledVariable.other => 2.0,
          _ => 1.0,
        };
        lambda = math.max(t * factor, l * 4);
        kc = t / (k * (lambda + l));
        ti = t;
      case TuningMethod.zieglerNicholsOpenLoop:
        if (l <= 0) {
          throw StateError('Ziegler–Nichols требует L > 0');
        }
        kc = 0.9 * t / (k * l);
        ti = 3.33 * l;
      case TuningMethod.cohenCoonOpenLoop:
        if (l <= 0) {
          throw StateError('Cohen–Coon требует L > 0');
        }
        final r = l / t;
        kc = (t / (k * l)) * (0.9 + r / 12);
        ti = l * (30 + 3 * r) / (9 + 20 * r);
      case TuningMethod.integratingProcessSimc:
        throw StateError('Use an integrating process model (IPDT)');
      case TuningMethod.engineeringReview:
        throw StateError('Automatic tuning disabled');
    }
    if (!kc.isFinite || kc <= 0 || !ti.isFinite || ti <= 0) {
      throw StateError('Невозможно рассчитать PI для этой модели');
    }
    final pb = 100 / kc;
    return StepPiEstimate(
      kcNormalized: kc,
      pbPercent: pb,
      tiSeconds: ti,
      tdSeconds: 0,
      lambdaSeconds: lambda,
      display: settings.profile.translate(
        pbPercent: pb,
        tiSeconds: ti,
        processGain: plant.gain,
      ),
      method: settings.tuningMethod,
    );
  }

  /// Skogestad original SIMC PI rules for G(s)=Ki*exp(-L*s)/s.
  /// Reference: https://skoge.folk.ntnu.no/publications/2012/skogestad-improved-simc-pid/PIDbook-chapter5.pdf
  StepPiEstimate calculateIntegrating(
      IntegratingPlant plant, StepTestSettings settings) {
    settings.validate();
    plant.validate();
    if (!settings.isIntegratingMethod) {
      throw StateError('Only SIMC integrating rules accept an IPDT model');
    }
    if (!settings.canCalculate) {
      throw StateError(settings.tuningBlockReason ?? 'IPDT tuning blocked');
    }
    // If λ is not explicitly entered, use a conservative 3×L
    // initial setting (ISA InTech integrating loop tuning guidance).
    // Zero effective delay requires an explicitly selected λ.
    final lambda = settings.lambdaSeconds ?? (3 * plant.delaySeconds);
    final sum = lambda + plant.delaySeconds;
    if (!lambda.isFinite || lambda <= 0 ||
        !sum.isFinite || sum <= 0) {
      throw StateError('Invalid lambda/dead-time units');
    }
    final kc = 1 / (plant.gainPerSecond.abs() * sum);
    final ti = 4 * sum;
    final pb = 100 / kc;
    if (![kc, ti, pb].every((n) => n.isFinite && n > 0)) {
      throw StateError('IPDT PI parameters out of range');
    }
    return StepPiEstimate(
      kcNormalized: kc, pbPercent: pb,
      tiSeconds: ti, tdSeconds: 0,
      lambdaSeconds: lambda,
      display: settings.profile.translate(
        pbPercent: pb, tiSeconds: ti,
        processGain: plant.gainPerSecond,
      ),
      method: settings.tuningMethod,
    );
  }

}

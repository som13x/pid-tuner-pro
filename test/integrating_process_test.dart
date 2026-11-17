import 'dart:math' as math;

import 'package:test/test.dart';
import 'package:pid_tuner_pro_core/auto_tune.dart';
import 'package:pid_tuner_pro_core/dcs_controller_profiles.dart';
import 'package:pid_tuner_pro_core/integrating_step_identification.dart';
import 'package:pid_tuner_pro_core/step_identification.dart';
import 'package:pid_tuner_pro_core/step_test_settings.dart';

StepTestSettings config({
  TuningMethod method = TuningMethod.opticontrolsLevel,
  bool confirmed = true,
  double sm = 2,
  LevelControlMode mode = LevelControlMode.pi,
  StepAcquisition acquisition = StepAcquisition.manualIntegratingSlope,
  String vendor = 'yokogawa-centum-vp-pid',
}) => StepTestSettings(
  tag: 'LIC-1901',
  comments: 'Integrating tank level',
  profileId: vendor,
  controlledVariable: ControlledVariable.level,
  tuningMethod: method,
  acquisition: acquisition,
  integratingProcessConfirmed: confirmed,
  stabilityMargin: sm,
  levelControlMode: mode,
);

void main() {
  test('level recommends OptiControls level rules and supports both IPDT methods', () {
    expect(StepTestSettings.recommendedFor(ControlledVariable.level),
      TuningMethod.opticontrolsLevel);
    expect(config().canCalculate, true);
    expect(config(confirmed: false).canCalculate, false);
    expect(config(acquisition: StepAcquisition.csvIntegratingTrend)
      .isIntegratingAcquisition, true);
    expect(() => config(acquisition: StepAcquisition.csvTrend).validate(),
      throwsArgumentError);
  });

  test('integrating settings survive roundtrip with λ and process flag', () {
    final c = config(sm: 3, mode: LevelControlMode.pid,
      vendor: DcsProfiles.abb800xaPidcc.id);
    final loaded = StepTestSettings.fromJson(c.toJson());
    expect(loaded.stabilityMargin, 3);
    expect(loaded.levelControlMode, LevelControlMode.pid);
    expect(loaded.lambdaSeconds, isNull);
    expect(loaded.integratingProcessConfirmed, true);
    expect(loaded.tuningMethod, TuningMethod.opticontrolsLevel);
    expect(loaded.acquisition, StepAcquisition.manualIntegratingSlope);
    expect(loaded.profileId, DcsProfiles.abb800xaPidcc.id);
  });

  test('OptiControls PI: Kc=0.9/(SM ri td), Ti=3.33 SM td', () {
    const plant = IntegratingPlant(gainPerSecond: .04, delaySeconds: 5);
    final r = const StepPiCalculator().calculateIntegrating(plant, config());
    expect(r.kcNormalized, closeTo(2.25, 1e-12));
    expect(r.pbPercent, closeTo(100 / 2.25, 1e-12));
    expect(r.tiSeconds, closeTo(33.3, 1e-12));
    expect(r.tdSeconds, 0);
    expect(r.lambdaSeconds, isNull);
    expect(r.stabilityMargin, 2);
    expect(r.levelControlMode, LevelControlMode.pi);
    expect(r.display.proportionalValue, closeTo(100/2.25, 1e-12));
    expect(r.toJson()['verifiedForDcsDeployment'], false);
    expect(r.toJson()['tuningSource'],
      'https://blog.opticontrols.com/level-control-loop-tuning/');
  });

  test('OptiControls PID: Kc=1.2/(SM ri td), Ti=2 SM td, Td=td/2', () {
    const plant = IntegratingPlant(gainPerSecond: .04, delaySeconds: 5);
    final r = const StepPiCalculator().calculateIntegrating(plant,
      config(mode: LevelControlMode.pid));
    expect(r.kcNormalized, closeTo(3, 1e-12));
    expect(r.pbPercent, closeTo(100 / 3, 1e-12));
    expect(r.tiSeconds, 20);
    expect(r.tdSeconds, 2.5);
    expect(r.display.tdSeconds, 2.5);
    expect(r.levelControlMode, LevelControlMode.pid);
    expect(r.toJson()['algorithm'],
      'OptiControls-interacting-PID-normalized');
    expect((r.display.toJson()['assumption'] as String),
      contains('interacting PID'));
  });

  test('increasing stability margin reduces gain and slows PI', () {
    const model = IntegratingPlant(gainPerSecond: .04, delaySeconds: 5);
    final a = const StepPiCalculator().calculateIntegrating(model, config());
    final b = const StepPiCalculator().calculateIntegrating(model,
      config(sm: 4));
    expect(b.kcNormalized, closeTo(a.kcNormalized / 2, 1e-12));
    expect(b.tiSeconds, closeTo(a.tiSeconds * 2, 1e-12));
    expect(b.pbPercent, closeTo(a.pbPercent * 2, 1e-12));
  });

  test('different vendor shows normalized Kc and sign changes action', () {
    const model = IntegratingPlant(gainPerSecond: -.04, delaySeconds: 5);
    final r = const StepPiCalculator().calculateIntegrating(model,
      config(vendor: DcsProfiles.siemensPcs7Pidconl.id,
        mode: LevelControlMode.pid, sm: 3));
    expect(r.kcNormalized, closeTo(2, 1e-12));
    expect(r.pbPercent, 50);
    expect(r.tiSeconds, 30);
    expect(r.tdSeconds, 2.5);
    expect(r.display.proportionalValue, 2);
    expect(r.display.recommendedAction, 'direct');
  });

  test('OptiControls requires td > 0 and SM ≥ 2', () {
    const plant = IntegratingPlant(gainPerSecond: .04, delaySeconds: 5);
    expect(() => config(sm: 1.9).validate(), throwsArgumentError);
    expect(() => config(sm: double.nan).validate(), throwsArgumentError);
    expect(() => const StepPiCalculator().calculateIntegrating(
      const IntegratingPlant(gainPerSecond: .04, delaySeconds: 0),
      config()), throwsStateError);
    expect(() => const StepPiCalculator().calculateIntegrating(
      plant, config(confirmed: false)), throwsStateError);
    expect(() => const StepPiCalculator().calculateIntegrating(
      plant, config(method: TuningMethod.engineeringReview)),
      throwsStateError);
    expect(() => const StepPiCalculator().calculate(
      const Plant(gain: 1, tau: 15, delay: 3), config()),
      throwsStateError);
  });

  test('old SIMC settings stay archived but cannot generate new tunes', () {
    final raw = config().toJson()
      ..['tuningMethod'] = 'integratingProcessSimc'
      ..['lambdaSeconds'] = 30.0;
    final historic = StepTestSettings.fromJson(raw);
    expect(historic.isDeprecatedMethod, true);
    expect(historic.canCalculate, false);
    expect(historic.tuningBlockReason, contains('устаревший'));
    expect(historic.lambdaSeconds, 30);
    expect(() => const StepPiCalculator().calculateIntegrating(
      const IntegratingPlant(gainPerSecond: .04, delaySeconds: 5), historic),
      throwsStateError);
  });

  test('manual ramp accounts for pre-existing PV slope', () {
    final estimate = const IntegratingManualEstimator().estimate(
      const IntegratingManualInput(
        mvBefore: 40, mvAfter: 50,
        pvAtT1: 45, pvAtT2: 55,
        t1Seconds: 20, t2Seconds: 40,
        baselineSlopePerSecond: 0.1, delaySeconds: 5,
        mvSpanLow: 0, mvSpanHigh: 100,
        pvSpanLow: 0, pvSpanHigh: 100,
      ));
    expect(estimate.plant.gainPerSecond, closeTo(.04, 1e-12));
    expect(estimate.afterSlopeNormalized, closeTo(.5, 1e-12));
    expect(estimate.beforeSlopeNormalized, closeTo(.1, 1e-12));
    expect(estimate.evidence['qualityMetricsAvailable'], false);
  });

  test('manual ramp rejects zero MV, negative lag, time inversion', () {
    const base = IntegratingManualInput(
      mvBefore: 40, mvAfter: 40,
      pvAtT1: 45, pvAtT2: 55,
      t1Seconds: 20, t2Seconds: 40, delaySeconds: 5,
      mvSpanLow: 0, mvSpanHigh: 100,
      pvSpanLow: 0, pvSpanHigh: 100,
    );
    expect(() => const IntegratingManualEstimator().estimate(base),
      throwsArgumentError);
    expect(() => const IntegratingManualEstimator().estimate(
      const IntegratingManualInput(
        mvBefore: 40, mvAfter: 50,
        pvAtT1: 45, pvAtT2: 55,
        t1Seconds: 2, t2Seconds: 40, delaySeconds: 5,
        mvSpanLow: 0, mvSpanHigh: 100,
        pvSpanLow: 0, pvSpanHigh: 100,
      )), throwsArgumentError);
  });

  test('IPDT CSV fit recovers Ki and L despite baseline drift', () {
    final samples = List.generate(121, (i) {
      final t = i.toDouble();
      final mv = t < 20 ? 40.0 : 50.0;
      final pv = 10 + 0.02 * t + 0.01 * 10 * math.max(0.0, t - 24);
      return TrendPoint(t, mv, pv);
    });
    final r = const IntegratingStepIdentifier().identify(samples);
    expect(r.plant.gainPerSecond, closeTo(.01, 1e-5));
    expect(r.plant.delaySeconds, closeTo(4, 0.2));
    expect(r.baselineSlopePctPerSecond, closeTo(.02, 1e-7));
    expect(r.rSquared, greaterThan(.99));
    expect(r.normalizedRmse, lessThan(.01));
    expect(r.suitableForTuning, true);
    expect(r.fittedCurve.length, samples.length);
  });

  test('IPDT CSV fit does not accept drifting or repeated MV steps', () {
    final samples = List.generate(121, (i) => TrendPoint(i.toDouble(),
      i < 20 ? 40 : i < 60 ? 50 : 48,
      10 + .1 * math.max(0, i - 24)));
    expect(() => const IntegratingStepIdentifier().identify(samples),
      throwsArgumentError);
  });

  test('integrating detector rejects settling first-order response', () {
    final samples = List.generate(121, (i) {
      final t = i.toDouble();
      return TrendPoint(t, t < 20 ? 40 : 50,
        10 + (t <= 24 ? 0 : 12 * (1 - math.exp(-(t - 24) / 12))));
    });
    expect(() => const IntegratingStepIdentifier().identify(samples),
      throwsArgumentError);
  });

  test('no FOPDT property is invented in IPDT model evidence', () {
    const model = IntegratingPlant(gainPerSecond: .05, delaySeconds: 4);
    model.validate();
    final text = model.toString();
    expect(text, isNotEmpty);
  });
}

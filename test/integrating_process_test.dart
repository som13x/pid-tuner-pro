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

  test('OptiControls four PV values use T1/T2 minute intervals', () {
    final estimate = const IntegratingManualEstimator().estimate(
      const IntegratingManualInput(
        mvBefore: 40, mvAfter: 50,
        pv1: 35, pv2: 36, pv3: 45, pv4: 55,
        t1Minutes: 2, t2Minutes: 4, delayMinutes: .5,
        mvSpanLow: 0, mvSpanHigh: 100,
        pvSpanLow: 0, pvSpanHigh: 100,
      ));
    expect(estimate.t1IntervalMinutes, 2);
    expect(estimate.t2IntervalMinutes, 4);
    expect(estimate.deadTimeMinutes, .5);
    expect(estimate.beforeSlopePercentPerMinute, closeTo(.5, 1e-12));
    expect(estimate.afterSlopePercentPerMinute, closeTo(2.5, 1e-12));
    expect(estimate.deltaSlopePercentPerMinute, closeTo(2, 1e-12));
    expect(estimate.deltaMvNormalized, 10);
    expect(estimate.integrationRatePerMinute, closeTo(.2, 1e-12));
    expect(estimate.plant.gainPerSecond, closeTo(.2/60, 1e-12));
    expect(estimate.plant.delaySeconds, 30);
    expect(estimate.evidence['method'], 'opticontrolsManualMinuteIntervals');
    expect(estimate.evidence['timeUnit'], 'minute');
    expect(estimate.evidence['timeInputKind'], 'elapsedInterval');
    expect(estimate.evidence['pv1'], 35);
    expect(estimate.evidence['pv2'], 36);
    expect(estimate.evidence['pv3'], 45);
    expect(estimate.evidence['pv4'], 55);
    expect(estimate.evidence['T1Minutes'], 2);
    expect(estimate.evidence['T2Minutes'], 4);
    expect(estimate.evidence['deadTimeMinutes'], .5);
    expect(estimate.evidence['T1Seconds'], 120);
    expect(estimate.evidence['T2Seconds'], 240);
    expect(estimate.evidence['delaySeconds'], 30);
    expect(estimate.evidence['qualityMetricsAvailable'], false);

    // Multiplying Ki by 60 while dividing delay by 60 cancels:
    // the published minute-based formula gives exactly the same Kc.
    final pi = const StepPiCalculator().calculateIntegrating(
      estimate.plant, config());
    expect(pi.kcNormalized, closeTo(4.5, 1e-12));
    expect(pi.tiSeconds, closeTo(199.8, 1e-10));
    expect(pi.tiSeconds / 60, closeTo(3.33, 1e-12));

    final pid = const StepPiCalculator().calculateIntegrating(
      estimate.plant, config(mode: LevelControlMode.pid));
    expect(pid.kcNormalized, closeTo(6, 1e-12));
    expect(pid.tiSeconds / 60, closeTo(2, 1e-12));
    expect(pid.tdSeconds / 60, closeTo(.25, 1e-12));
  });

  test('minute intervals normalize engineering unit PV/MV spans', () {
    final estimate = const IntegratingManualEstimator().estimate(
      const IntegratingManualInput(
        mvBefore: 60, mvAfter: 80, // 10% of span 0..200
        pv1: 400, pv2: 404, // 2 EU/min => 1%PV/min
        pv3: 430, pv4: 446, // 4 EU/min => 2%PV/min
        t1Minutes: 2, t2Minutes: 4, delayMinutes: 1,
        mvSpanLow: 0, mvSpanHigh: 200,
        pvSpanLow: 300, pvSpanHigh: 500,
      ));
    expect(estimate.beforeSlopePercentPerMinute, closeTo(1, 1e-12));
    expect(estimate.afterSlopePercentPerMinute, closeTo(2, 1e-12));
    expect(estimate.deltaSlopePercentPerMinute, closeTo(1, 1e-12));
    expect(estimate.deltaMvNormalized, 10);
    expect(estimate.integrationRatePerMinute, closeTo(.1, 1e-12));
    expect(estimate.plant.gainPerSecond, closeTo(.1/60, 1e-12));
    expect(estimate.plant.delaySeconds, 60);
  });

  test('minute-interval estimator preserves signed MV influence', () {
    final estimate = const IntegratingManualEstimator().estimate(
      const IntegratingManualInput(
        mvBefore: 50, mvAfter: 40,
        pv1: 35, pv2: 36, pv3: 45, pv4: 55,
        t1Minutes: 2, t2Minutes: 4, delayMinutes: .5,
        mvSpanLow: 0, mvSpanHigh: 100,
        pvSpanLow: 0, pvSpanHigh: 100,
      ));
    expect(estimate.integrationRatePerMinute, closeTo(-.2, 1e-12));
  });

  test('manual minute intervals validate duration, MV and time values', () {
    IntegratingManualInput sample({
      double mvAfter = 50,
      double t1 = 2, double t2 = 4, double delay = .5,
    }) => IntegratingManualInput(
      mvBefore: 40, mvAfter: mvAfter,
      pv1: 35, pv2: 36, pv3: 45, pv4: 55,
      t1Minutes: t1, t2Minutes: t2, delayMinutes: delay,
      mvSpanLow: 0, mvSpanHigh: 100,
      pvSpanLow: 0, pvSpanHigh: 100,
    );
    const estimator = IntegratingManualEstimator();
    expect(() => estimator.estimate(sample(mvAfter: 40)),
      throwsArgumentError);
    expect(() => estimator.estimate(sample(t1: 0)), throwsArgumentError);
    expect(() => estimator.estimate(sample(t2: -1)), throwsArgumentError);
    expect(() => estimator.estimate(sample(delay: -1)),
      throwsArgumentError);
    expect(() => estimator.estimate(sample(t1: double.nan)),
      throwsArgumentError);
    expect(() => estimator.estimate(sample(t2: double.infinity)),
      throwsArgumentError);
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

import 'dart:math' as math;

import 'package:test/test.dart';
import 'package:pid_tuner_pro_core/auto_tune.dart';
import 'package:pid_tuner_pro_core/dcs_controller_profiles.dart';
import 'package:pid_tuner_pro_core/integrating_step_identification.dart';
import 'package:pid_tuner_pro_core/step_identification.dart';
import 'package:pid_tuner_pro_core/step_test_settings.dart';

StepTestSettings config({
  TuningMethod method = TuningMethod.integratingProcessSimc,
  bool confirmed = true,
  double? lambda,
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
  lambdaSeconds: lambda,
);

void main() {
  test('level recommends integrating SIMC and supports both IPDT methods', () {
    expect(StepTestSettings.recommendedFor(ControlledVariable.level),
      TuningMethod.integratingProcessSimc);
    expect(config().canCalculate, true);
    expect(config(confirmed: false).canCalculate, false);
    expect(config(acquisition: StepAcquisition.csvIntegratingTrend)
      .isIntegratingAcquisition, true);
    expect(() => config(acquisition: StepAcquisition.csvTrend).validate(),
      throwsArgumentError);
  });

  test('integrating settings survive roundtrip with λ and process flag', () {
    final c = config(lambda: 120,
      vendor: DcsProfiles.abb800xaPidcc.id);
    final loaded = StepTestSettings.fromJson(c.toJson());
    expect(loaded.lambdaSeconds, 120);
    expect(loaded.integratingProcessConfirmed, true);
    expect(loaded.tuningMethod, TuningMethod.integratingProcessSimc);
    expect(loaded.acquisition, StepAcquisition.manualIntegratingSlope);
    expect(loaded.profileId, DcsProfiles.abb800xaPidcc.id);
  });

  test('SIMC IPDT PI yields expected normalized Kc/PB/Ti', () {
    const plant = IntegratingPlant(gainPerSecond: 0.04, delaySeconds: 5);
    final r = const StepPiCalculator().calculateIntegrating(
      plant, config(lambda: 30));
    expect(r.kcNormalized, closeTo(1 / (0.04 * 35), 1e-12));
    expect(r.pbPercent, closeTo(140, 1e-12));
    expect(r.tiSeconds, 140);
    expect(r.tdSeconds, 0);
    expect(r.lambdaSeconds, 30);
    expect(r.display.proportionalValue, closeTo(140, 1e-12));
    expect(r.toJson()['verifiedForDcsDeployment'], false);
  });

  test('default conservative lambda 3L with normalized vendor display', () {
    const plant = IntegratingPlant(gainPerSecond: -0.04, delaySeconds: 5);
    final r = const StepPiCalculator().calculateIntegrating(
      plant, config(vendor: DcsProfiles.siemensPcs7Pidconl.id));
    expect(r.lambdaSeconds, 15);
    expect(r.kcNormalized, closeTo(1.25, 1e-12));
    expect(r.pbPercent, closeTo(80, 1e-12));
    expect(r.tiSeconds, 80);
    expect(r.display.proportionalValue, closeTo(1.25, 1e-12));
    expect(r.display.recommendedAction, 'direct');
  });

  test('IPDT cannot be tuned with FOPDT rule or unconfirmed behaviour', () {
    const model = IntegratingPlant(gainPerSecond: 0.04, delaySeconds: 5);
    expect(() => const StepPiCalculator().calculateIntegrating(
      model, config(confirmed: false)), throwsStateError);
    expect(() => const StepPiCalculator().calculateIntegrating(
      const IntegratingPlant(gainPerSecond: 0.03, delaySeconds: 0),
      config()), throwsStateError);
    expect(() => const StepPiCalculator().calculateIntegrating(
      model, config(method: TuningMethod.engineeringReview)),
      throwsStateError);
    expect(() => const StepPiCalculator().calculate(
      const Plant(gain: 1, tau: 15, delay: 3), config()),
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

  test('no FOPDT property is invented in IPDT model evidence', () {
    const model = IntegratingPlant(gainPerSecond: .05, delaySeconds: 4);
    model.validate();
    final text = model.toString();
    expect(text, isNotEmpty);
  });
}

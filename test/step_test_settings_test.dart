import 'package:test/test.dart';
import 'package:pid_tuner_pro_core/auto_tune.dart';
import 'package:pid_tuner_pro_core/dcs_controller_profiles.dart';
import 'package:pid_tuner_pro_core/step_test_settings.dart';

const plant = Plant(gain: 1.5, tau: 15, delay: 3);

StepTestSettings settings({
  String profileId = 'yokogawa-centum-vp-pid',
  ControlledVariable variable = ControlledVariable.flow,
  TuningMethod method = TuningMethod.imcConservative,
  StepAcquisition acquisition = StepAcquisition.manualDelayAndT63,
  bool levelConfirmed = false,
}) => StepTestSettings(
  tag: 'FIC-1201', comments: 'LNG test',
  profileId: profileId, controlledVariable: variable,
  tuningMethod: method, acquisition: acquisition,
  selfRegulatingLevelConfirmed: levelConfirmed,
);

void main() {
  test('all five requested DCS profiles are available and labelled', () {
    expect(DcsProfiles.all.map((x) => x.vendor).toSet(),
      {'Yokogawa', 'ABB', 'Siemens', 'Honeywell', 'Emerson'});
    for (final profile in DcsProfiles.all) {
      expect(profile.warning, isNotEmpty);
      expect(profile.proportionalLabel, isNotEmpty);
    }
  });

  test('Settings serialize all fields and restore them', () {
    final original = settings(
      profileId: DcsProfiles.emersonDeltaVPid.id,
      variable: ControlledVariable.temperature,
      method: TuningMethod.cohenCoonOpenLoop,
      acquisition: StepAcquisition.csvTrend);
    final restored = StepTestSettings.fromJson(original.toJson());
    expect(restored.tag, 'FIC-1201');
    expect(restored.comments, 'LNG test');
    expect(restored.profileId, DcsProfiles.emersonDeltaVPid.id);
    expect(restored.controlledVariable, ControlledVariable.temperature);
    expect(restored.tuningMethod, TuningMethod.cohenCoonOpenLoop);
    expect(restored.acquisition, StepAcquisition.csvTrend);
  });

  test('Settings reject blank TAG and unknown DCS', () {
    expect(() => StepTestSettings(
      tag: ' ', profileId: DcsProfiles.yokogawaCentumVp.id,
      controlledVariable: ControlledVariable.flow,
      tuningMethod: TuningMethod.imcConservative,
      acquisition: StepAcquisition.csvTrend).validate(), throwsArgumentError);
    expect(() => settings(profileId: 'unknown').validate(), throwsArgumentError);
    final corrupt = settings().toJson()..['acquisition'] = 'broken';
    expect(() => StepTestSettings.fromJson(corrupt), throwsFormatException);
  });

  test('recommendation is conservative except integrating-prone level', () {
    for (final variable in [
      ControlledVariable.flow, ControlledVariable.pressure,
      ControlledVariable.temperature, ControlledVariable.other]) {
      expect(StepTestSettings.recommendedFor(variable),
        TuningMethod.imcConservative);
    }
    expect(StepTestSettings.recommendedFor(ControlledVariable.level),
      TuningMethod.engineeringReview);
    expect(settings(variable: ControlledVariable.level).canCalculate, false);
    expect(settings(
      variable: ControlledVariable.level,
      levelConfirmed: true).canCalculate, true);
  });

  test('known IMC PI correlation: PB 180% for Yokogawa', () {
    final calc = const StepPiCalculator().calculate(plant, settings());
    expect(calc.lambdaSeconds, 15);
    expect(calc.kcNormalized, closeTo(5 / 9, 1e-12));
    expect(calc.pbPercent, closeTo(180, 1e-10));
    expect(calc.tiSeconds, 15);
    expect(calc.tdSeconds, 0);
    expect(calc.display.proportionalValue, closeTo(180, 1e-10));
    expect(calc.display.profile.vendor, 'Yokogawa');
    expect(calc.toJson()['verifiedForDcsDeployment'], false);
  });

  test('same plant, system changes equivalent DCS display parameter', () {
    for (final profile in [
      DcsProfiles.abb800xaPidcc,
      DcsProfiles.siemensPcs7Pidconl,
      DcsProfiles.honeywellExperionPid,
      DcsProfiles.emersonDeltaVPid,
    ]) {
      final calc = const StepPiCalculator().calculate(
        plant, settings(profileId: profile.id));
      expect(calc.display.proportionalValue, closeTo(5 / 9, 1e-12));
      expect(calc.pbPercent, 180);
      expect(calc.display.profile.id, profile.id);
    }
  });

  test('Ziegler Nichols open-loop requires positive delay', () {
    final calc = const StepPiCalculator().calculate(plant,
      settings(method: TuningMethod.zieglerNicholsOpenLoop));
    expect(calc.kcNormalized, 3);
    expect(calc.tiSeconds, closeTo(9.99, 1e-10));
    expect(() => const StepPiCalculator().calculate(
      const Plant(gain: 1, tau: 10, delay: 0),
      settings(method: TuningMethod.zieglerNicholsOpenLoop)),
      throwsStateError);
  });

  test('Cohen Coon open-loop PI yields finite normalized values', () {
    final calc = const StepPiCalculator().calculate(plant,
      settings(method: TuningMethod.cohenCoonOpenLoop));
    expect(calc.kcNormalized, closeTo(3.05555555555, 1e-8));
    expect(calc.tiSeconds, closeTo(3 * 30.6 / 13, 1e-8));
    expect(calc.tdSeconds, 0);
  });

  test('process sign affects direction and not magnitude of Kc', () {
    final positive = const StepPiCalculator().calculate(plant, settings());
    final negative = const StepPiCalculator().calculate(
      const Plant(gain: -1.5, tau: 15, delay: 3), settings());
    expect(negative.kcNormalized, positive.kcNormalized);
    expect(negative.display.recommendedAction, 'direct');
    expect(positive.display.recommendedAction, 'reverse');
  });

  test('engineering review must never return automatic PI tuning', () {
    expect(() => const StepPiCalculator().calculate(plant, settings(
      method: TuningMethod.engineeringReview)), throwsStateError);
    expect(() => const StepPiCalculator().calculate(plant, settings(
      variable: ControlledVariable.level)), throwsStateError);
  });

  test('all Step Test acquisition modes include operational procedure', () {
    for (final method in StepAcquisition.values) {
      expect(method.instructions, contains('1.'));
      expect(method.instructions, contains('2.'));
    }
  });
}

import 'package:test/test.dart';
import 'package:pid_tuner_pro_core/dcs_controller_profiles.dart';

void main() {
  test('three supported, uniquely identified profiles', () {
    expect(DcsProfiles.all, hasLength(3));
    expect(DcsProfiles.all.map((p) => p.id).toSet(), hasLength(3));
    for (final p in DcsProfiles.all) {
      expect(DcsProfiles.byId(p.id), same(p));
      expect(DcsProfiles.forProject(p.storedVendor, p.storedBlock), same(p));
      expect(p.warning, isNotEmpty);
      expect(p.documentationUrl, startsWith('https://'));
    }
  });

  test('Yokogawa displays PB without unit conversion', () {
    final p = DcsProfiles.yokogawaCentumVp;
    expect(p.displayedProportional(125), 125);
    expect(p.pbFromDisplayed(125), 125);
    final result = p.translate(pbPercent: 125, tiSeconds: 15,
      processGain: 0.81).toJson();
    expect(result['parameterName'], 'PB (%)');
    expect(result['parameterValue'], 125);
    expect(result['equivalentKcNormalized'], closeTo(0.8, 1e-12));
    expect(result['actionToVerify'], 'reverse');
    expect(result['verifiedForDeployment'], false);
  });

  test('Siemens and ABB normalized proportional equivalence', () {
    for (final p in [DcsProfiles.siemensPcs7Pidconl,
                      DcsProfiles.abb800xaPidcc]) {
      expect(p.displayedProportional(80), closeTo(1.25, 1e-12));
      expect(p.pbFromDisplayed(1.25), closeTo(80, 1e-12));
      final result = p.translate(pbPercent: 80, tiSeconds: 30,
        processGain: -0.6).toJson();
      expect(result['actionToVerify'], 'direct');
      expect(result['tiSeconds'], 30);
      expect(result['parameterName'], contains('Gain'),
        reason: 'Siemens text uses upper case GAIN');
      expect(result['requiresBlockAndScalingVerification'], true);
    }
  });

  test('round trip across a broad normalized PB range', () {
    for (final p in DcsProfiles.all) {
      for (final pb in [10.0, 25.0, 40.0, 100.0, 250.0, 900.0]) {
        expect(p.pbFromDisplayed(p.displayedProportional(pb)),
          closeTo(pb, 1e-9));
      }
    }
  });

  test('input validation rejects zero, negative and non-finite settings', () {
    for (final p in DcsProfiles.all) {
      expect(() => p.displayedProportional(0), throwsArgumentError);
      expect(() => p.pbFromDisplayed(double.nan), throwsArgumentError);
      expect(() => p.translate(pbPercent: 120, tiSeconds: 0,
        processGain: 0.8), throwsArgumentError);
      expect(() => p.translate(pbPercent: 120, tiSeconds: 15,
        tdSeconds: double.infinity, processGain: 0.8), throwsArgumentError);
      expect(() => p.translate(pbPercent: 120, tiSeconds: 15,
        processGain: 0), throwsArgumentError);
    }
  });

  test('unknown controller blocks cannot silently masquerade as Yokogawa', () {
    expect(DcsProfiles.forProject('Yokogawa CENTUM VP', 'FIC'), isNull);
    expect(DcsProfiles.forProject('ABB 800xA', 'MOD300'), isNull);
    expect(() => DcsProfiles.byId('honeywell-experion'),
      throwsArgumentError);
  });
}

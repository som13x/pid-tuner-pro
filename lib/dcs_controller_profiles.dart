/// DCS profile catalogue for normalized PI tuning display.
///
/// A profile is NOT a vendor PID firmware emulator. v2.4 translates the
/// normalized proportional coefficient Kc = 100 / PB between common user
/// interfaces and labels the result with controller-specific terminology.
/// Real tuning also depends on block variant, PV/MV scaling, action, algorithm
/// selection, sample time, tracking, limits, filter, and special options.
/// No values are suitable for direct deployment without engineering review.
enum ProportionalParameter { bandPercent, dimensionlessGain }

class DcsControllerProfile {
  final String id;
  final String vendor;
  final String system;
  final String block;
  final String proportionalLabel;
  final ProportionalParameter proportionalParameter;
  final String documentationUrl;
  final String warning;

  const DcsControllerProfile({
    required this.id,
    required this.vendor,
    required this.system,
    required this.block,
    required this.proportionalLabel,
    required this.proportionalParameter,
    required this.documentationUrl,
    required this.warning,
  });

  String get title => '$vendor $system · $block';

  /// What is saved in the existing vendor field of LoopProject.
  /// Uses existing SQLite schema; no destructive migration.
  String get storedVendor => '$vendor $system';

  String get storedBlock => block;

  /// Calculated only in normalized 0-100% PV and MV coordinates.
  double displayedProportional(double pbPercent) {
    _positive(pbPercent, 'PB');
    return proportionalParameter == ProportionalParameter.bandPercent
        ? pbPercent : 100 / pbPercent;
  }

  double pbFromDisplayed(double parameterValue) {
    _positive(parameterValue, proportionalLabel);
    return proportionalParameter == ProportionalParameter.bandPercent
        ? parameterValue : 100 / parameterValue;
  }

  DcsTuningDisplay translate({
    required double pbPercent,
    required double tiSeconds,
    double tdSeconds = 0,
    required double processGain,
  }) {
    _positive(pbPercent, 'PB');
    _positive(tiSeconds, 'Ti');
    if (!tdSeconds.isFinite || tdSeconds < 0) {
      throw ArgumentError.value(tdSeconds, 'tdSeconds');
    }
    if (!processGain.isFinite || processGain == 0) {
      throw ArgumentError.value(processGain, 'processGain');
    }
    return DcsTuningDisplay(
      profile: this,
      proportionalValue: displayedProportional(pbPercent),
      pbPercent: pbPercent,
      tiSeconds: tiSeconds,
      tdSeconds: tdSeconds,
      recommendedAction: processGain > 0 ? 'reverse' : 'direct',
    );
  }

  static void _positive(double value, String name) {
    if (!value.isFinite || value <= 0) {
      throw ArgumentError.value(value, name, 'Must be finite and positive');
    }
  }
}

class DcsTuningDisplay {
  final DcsControllerProfile profile;
  final double proportionalValue, pbPercent, tiSeconds, tdSeconds;
  final String recommendedAction;

  const DcsTuningDisplay({
    required this.profile,
    required this.proportionalValue,
    required this.pbPercent,
    required this.tiSeconds,
    required this.tdSeconds,
    required this.recommendedAction,
  });

  /// A labelled engineering calculation, never a deployable set of DCS writes.
  Map<String, Object?> toJson() => {
    'profileId': profile.id,
    'vendor': profile.vendor,
    'system': profile.system,
    'block': profile.block,
    'parameterName': profile.proportionalLabel,
    'parameterValue': proportionalValue,
    'equivalentPbPercent': pbPercent,
    'equivalentKcNormalized': 100 / pbPercent,
    'tiSeconds': tiSeconds,
    'tdSeconds': tdSeconds,
    'actionToVerify': recommendedAction,
    'assumption': tdSeconds > 0
        ? 'PV/MV normalized 0..100%; Kc=100/PB; '
          'the source rule assumes interacting PID, not a validated '
          'native block setting (parallel form requires conversion).'
        : 'PV/MV normalized 0..100%; Kc=100/PB; '
          'integral time and controller algorithm require verification.',
    'requiresBlockAndScalingVerification': true,
    'verifiedForDeployment': false,
    'warning': profile.warning,
    'documentation': profile.documentationUrl,
  };
}

class DcsProfiles {
  static const yokogawaCentumVp = DcsControllerProfile(
    id: 'yokogawa-centum-vp-pid',
    vendor: 'Yokogawa',
    system: 'CENTUM VP',
    block: 'PID',
    proportionalLabel: 'PB (%)',
    proportionalParameter: ProportionalParameter.bandPercent,
    documentationUrl:
        'https://www.yokogawa.com/library/resources/white-papers/pid-tuning-in-distributed-control-systems/',
    warning: 'CENTUM VP PID has several algorithms, including I-PD and '
        'automatic selection. This calculation uses simplified ideal PI only. '
        'Verify algorithm, scaling, control direction and block options.',
  );

  static const siemensPcs7Pidconl = DcsControllerProfile(
    id: 'siemens-pcs7-pidconl',
    vendor: 'Siemens',
    system: 'PCS 7',
    block: 'PIDConL',
    proportionalLabel: 'GAIN (normalized equivalent)',
    proportionalParameter: ProportionalParameter.dimensionlessGain,
    documentationUrl:
        'https://www.automation.siemens.com/sce-static/learning-training-documents/pcs7/v9-0/p01-06-control-loop-v9-tud-0719-en.pdf',
    warning: 'PIDConL uses GAIN, TI and TD, with block-specific normalization, '
        'setpoint weighting and direction settings. This is a normalized '
        'Kc equivalent, NOT an automatically transferable GAIN setting.',
  );

  static const abb800xaPidcc = DcsControllerProfile(
    id: 'abb-800xa-ac800m-pidcc',
    vendor: 'ABB',
    system: '800xA AC 800M',
    block: 'PidCC',
    proportionalLabel: 'Gain (normalized equivalent)',
    proportionalParameter: ProportionalParameter.dimensionlessGain,
    documentationUrl:
        'https://library.e.abb.com/public/01044bb4edcc4608b3a61391722b72fe/3BSE035981-600_A_en_System_800xA_Control_6.0_AC_800M_Binary_and_Analog_Handling.pdf',
    warning: 'ABB 800xA can host different controller platforms. PidCC '
        'on AC 800M is only one case; check Gain scaling, setpoint '
        'weighting beta, selected PI/PID type, tracking and direction.',
  );

  /// Representative profiles for the two additional requested DCS families.
  /// The exact vendor block/algorithm must be verified before field use.
  static const honeywellExperionPid = DcsControllerProfile(
    id: 'honeywell-experion-pks-pid',
    vendor: 'Honeywell',
    system: 'Experion PKS',
    block: 'PID',
    proportionalLabel: 'Kc (normalized equivalent)',
    proportionalParameter: ProportionalParameter.dimensionlessGain,
    documentationUrl: 'https://process.honeywell.com/',
    warning: 'Honeywell Experion PID variants have controller-dependent '
      'equations, engineering-unit scaling, and tuning parameterization. '
      'The displayed Kc is a normalized ideal-PI equivalent only, '
      'NOT an automatically transferable block parameter.',
  );

  static const emersonDeltaVPid = DcsControllerProfile(
    id: 'emerson-deltav-pid',
    vendor: 'Emerson',
    system: 'DeltaV',
    block: 'PID',
    proportionalLabel: 'GAIN (normalized equivalent)',
    proportionalParameter: ProportionalParameter.dimensionlessGain,
    documentationUrl: 'https://www.emerson.com/',
    warning: 'DeltaV PID forms, gain units and reset parameterization '
      'depend on selected block options and scaling. The displayed '
      'GAIN is a normalized ideal-PI equivalent only, not validated '
      'for direct deployment.',
  );

  static const all = [
    yokogawaCentumVp,
    abb800xaPidcc,
    siemensPcs7Pidconl,
    honeywellExperionPid,
    emersonDeltaVPid,
  ];

  static DcsControllerProfile byId(String id) {
    for (final profile in all) {
      if (profile.id == id) return profile;
    }
    throw ArgumentError.value(id, 'id', 'Unknown DCS controller profile');
  }

  /// Old projects used 'Yokogawa CENTUM VP' + 'PID'. Keep that spelling.
  ///
  /// Unknown legacy systems must NOT be treated as a known Yokogawa block.
  static DcsControllerProfile? forProject(String vendor, String block) {
    for (final profile in all) {
      if (profile.storedVendor == vendor && profile.storedBlock == block) {
        return profile;
      }
    }
    return null;
  }
}

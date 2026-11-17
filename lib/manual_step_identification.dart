import 'dart:math' as math;

import 'auto_tune.dart';

/// Manual engineering estimate from a *measured* sustained MV step.
/// Timing offsets are measured from the instant the MV step was applied.
/// Unlike CSV identification, this method cannot calculate R²/NRMSE or
/// independently verify whether the step was isolated or reached steady state.
enum ManualStepMethod { knownDelayAndT63, twoResponseTimes }

class ManualStepInput {
  final double mvBefore, mvAfter, pvBefore, pvAfter;
  final double mvSpanLow, mvSpanHigh, pvSpanLow, pvSpanHigh;
  /// Elapsed seconds since MV step to 1-exp(-1) = 63.212% PV response.
  final double t63Seconds;
  /// Independently estimated apparent dead time, required in one-point mode.
  final double? delaySeconds;
  /// Elapsed seconds since MV step to 1-exp(-1/3) = 28.347% PV response.
  final double? t28Seconds;
  final ManualStepMethod method;

  const ManualStepInput({
    required this.mvBefore,
    required this.mvAfter,
    required this.pvBefore,
    required this.pvAfter,
    required this.mvSpanLow,
    required this.mvSpanHigh,
    required this.pvSpanLow,
    required this.pvSpanHigh,
    required this.t63Seconds,
    this.delaySeconds,
    this.t28Seconds,
    this.method = ManualStepMethod.knownDelayAndT63,
  });
}

class ManualStepPoint {
  final double seconds;
  final double mv, pv;
  const ManualStepPoint(this.seconds, this.mv, this.pv);
}

class ManualStepEstimate {
  final Plant plant;
  final ManualStepInput input;
  final double gainEngineering;
  final double normalizedMvChange;
  final double normalizedPvChange;

  const ManualStepEstimate(this.plant, this.input,
    this.gainEngineering, this.normalizedMvChange,
    this.normalizedPvChange);

  /// Synthetic FOPDT response, *not measured* samples.
  List<ManualStepPoint> syntheticCurve({int samples = 160}) {
    if (samples < 2 || samples > 10000) {
      throw ArgumentError('Synthetic curve sample count must be 2..10000');
    }
    final horizon = math.max(
      input.t63Seconds + 2 * plant.tau,
      plant.delay + 4 * plant.tau,
    );
    return List.unmodifiable(List.generate(samples, (index) {
      final t = horizon * index / (samples - 1);
      final x = t <= plant.delay
        ? 0.0 : 1 - math.exp(-(t - plant.delay) / plant.tau);
      return ManualStepPoint(t, input.mvAfter,
        input.pvBefore + (input.pvAfter - input.pvBefore) * x);
    }));
  }

  /// Only raw input evidence and method. No invented goodness-of-fit.
  Map<String, Object?> get evidence => <String, Object?>{
    'method': input.method.name,
    'mvBefore': input.mvBefore, 'mvAfter': input.mvAfter,
    'pvBefore': input.pvBefore, 'pvAfter': input.pvAfter,
    'mvSpanLow': input.mvSpanLow, 'mvSpanHigh': input.mvSpanHigh,
    'pvSpanLow': input.pvSpanLow, 'pvSpanHigh': input.pvSpanHigh,
    't63Seconds': input.t63Seconds,
    'delaySeconds': input.method == ManualStepMethod.knownDelayAndT63
      ? input.delaySeconds : plant.delay,
    if (input.method == ManualStepMethod.twoResponseTimes)
      't28Seconds': input.t28Seconds,
    'measuredTrendAvailable': false,
    'qualityMetricsAvailable': false,
    'requiresEngineeringReview': true,
  };
}

class ManualStepEstimator {
  const ManualStepEstimator();

  ManualStepEstimate estimate(ManualStepInput input) {
    final values = <double>[
      input.mvBefore, input.mvAfter, input.pvBefore, input.pvAfter,
      input.mvSpanLow, input.mvSpanHigh,
      input.pvSpanLow, input.pvSpanHigh, input.t63Seconds,
    ];
    if (input.delaySeconds != null) values.add(input.delaySeconds!);
    if (input.t28Seconds != null) values.add(input.t28Seconds!);
    if (values.any((v) => !v.isFinite) ||
        input.mvSpanHigh <= input.mvSpanLow ||
        input.pvSpanHigh <= input.pvSpanLow ||
        input.mvBefore < input.mvSpanLow ||
        input.mvBefore > input.mvSpanHigh ||
        input.mvAfter < input.mvSpanLow ||
        input.mvAfter > input.mvSpanHigh ||
        input.pvBefore < input.pvSpanLow ||
        input.pvBefore > input.pvSpanHigh ||
        input.pvAfter < input.pvSpanLow ||
        input.pvAfter > input.pvSpanHigh ||
        input.t63Seconds <= 0) {
      throw ArgumentError('Invalid span, measurement, or response time');
    }

    final deltaMv = input.mvAfter - input.mvBefore;
    final deltaPv = input.pvAfter - input.pvBefore;
    final mvChangePct = deltaMv * 100 /
        (input.mvSpanHigh - input.mvSpanLow);
    final pvChangePct = deltaPv * 100 /
        (input.pvSpanHigh - input.pvSpanLow);
    if (mvChangePct.abs() < 1e-9 || pvChangePct.abs() < 1e-9) {
      throw ArgumentError('MV and PV changes must be nonzero');
    }

    late final double delay, tau;
    if (input.method == ManualStepMethod.knownDelayAndT63) {
      final l = input.delaySeconds;
      if (l == null || l < 0 || l >= input.t63Seconds) {
        throw ArgumentError('Require 0 <= L < t63 after the MV step');
      }
      delay = l;
      tau = input.t63Seconds - l;
    } else {
      final t28 = input.t28Seconds;
      if (t28 == null || t28 <= 0 || t28 >= input.t63Seconds) {
        throw ArgumentError('Require 0 < t28 < t63 after the MV step');
      }
      // t28 at (1-exp(-1/3)), t63 at (1-exp(-1)).
      // t28 = L + T/3; t63 = L + T.
      tau = 1.5 * (input.t63Seconds - t28);
      delay = input.t63Seconds - tau;
      if (delay < -1e-8) {
        throw ArgumentError('Response times imply negative dead time');
      }
    }
    final physicalGain = deltaPv / deltaMv;
    final normalizedGain = pvChangePct / mvChangePct;
    final plant = Plant(
      gain: normalizedGain,
      tau: tau,
      delay: delay < 0 ? 0 : delay,
    );
    plant.validate();
    return ManualStepEstimate(plant, input,
      physicalGain, mvChangePct, pvChangePct);
  }
}

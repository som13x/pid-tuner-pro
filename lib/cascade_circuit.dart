import 'dart:math' as math;

import 'auto_tune.dart';
import 'centum_pid_simulator.dart';

/// Fixed, typed signal terminals supported by the first cascade editor.
/// RL1 is observational only: block-specific Yokogawa terminal semantics
/// are deliberately NOT inferred from the spelling of a terminal.
enum CircuitPort {
  ticMv, ficSv, ficPv, lagIn, lagOut, ticRl1, asMmv, ficRl1,
}

extension CircuitPortName on CircuitPort {
  String get label => switch (this) {
    CircuitPort.ticMv => 'TIC1.MV',
    CircuitPort.ficSv => 'FIC1.SV',
    CircuitPort.ficPv => 'FIC1.PV',
    CircuitPort.lagIn => 'LAG.IN',
    CircuitPort.lagOut => 'LAG.OUT',
    CircuitPort.ticRl1 => 'TIC1.RL1 (monitor)',
    CircuitPort.asMmv => 'AS-M.MV',
    CircuitPort.ficRl1 => 'FIC1.RL1 (monitor)',
  };
}

class CircuitLink {
  final CircuitPort from, to;
  const CircuitLink(this.from, this.to);

  String get label => from.label + ' → ' + to.label;

  @override
  bool operator ==(Object other) => other is CircuitLink &&
      other.from == from && other.to == to;

  @override
  int get hashCode => Object.hash(from, to);
}

class CircuitWiring {
  /// Only links with understood simulated meaning are enabled.
  /// Unexpected port combinations are rejected rather than guessed.
  static const cascade = CircuitLink(CircuitPort.ticMv, CircuitPort.ficSv);
  static const pvToLag = CircuitLink(CircuitPort.ficPv, CircuitPort.lagIn);
  static const lagToTicRl = CircuitLink(CircuitPort.lagOut, CircuitPort.ticRl1);
  static const directPvRl = CircuitLink(CircuitPort.ficPv, CircuitPort.ticRl1);
  static const actualMvRl = CircuitLink(CircuitPort.asMmv, CircuitPort.ficRl1);

  static const catalogue = <CircuitLink>[
    cascade, pvToLag, lagToTicRl, directPvRl, actualMvRl,
  ];

  static const initial = <CircuitLink>[
    cascade, pvToLag, lagToTicRl, actualMvRl,
  ];

  final List<CircuitLink> links;
  CircuitWiring(Iterable<CircuitLink> links) :
      links = List.unmodifiable(links);

  bool contains(CircuitLink link) => links.contains(link);

  CircuitWiring toggle(CircuitLink link, bool enabled) {
    if (!catalogue.contains(link)) {
      throw ArgumentError('Unsupported connection: ' + link.label);
    }
    return CircuitWiring(enabled
      ? [...links.where((x) => x != link), link]
      : links.where((x) => x != link));
  }

  void validate() {
    final destinations = <CircuitPort>{};
    final known = <CircuitLink>{};
    for (final link in links) {
      if (!catalogue.contains(link)) {
        throw ArgumentError('Unsupported connection: ' + link.label);
      }
      if (!known.add(link)) throw ArgumentError('Duplicate connection');
      if (!destinations.add(link.to)) {
        throw ArgumentError('Multiple sources to ' + link.to.label);
      }
    }
    if (contains(lagToTicRl) && !contains(pvToLag)) {
      throw ArgumentError('LAG output is not driven by FIC1.PV');
    }
  }

  Map<String, Object?> toJson() => {
    'schemaVersion': 1,
    'links': links.map((l) =>
      <String, Object?>{'from': l.from.name, 'to': l.to.name}).toList(),
  };

  static CircuitWiring fromJson(Map<String, dynamic> json) {
    if (json['schemaVersion'] != 1 || json['links'] is! List) {
      throw const FormatException('Unsupported circuit wiring format');
    }
    final raw = json['links'] as List;
    if (raw.length > catalogue.length) {
      throw const FormatException('Too many connections');
    }
    final links = <CircuitLink>[];
    for (final item in raw) {
      if (item is! Map) throw const FormatException('Invalid link');
      final from = item['from'], to = item['to'];
      CircuitPort getPort(Object? name) {
        if (name is! String) throw const FormatException('Invalid port name');
        for (final p in CircuitPort.values) {
          if (p.name == name) return p;
        }
        throw FormatException('Unknown port: ' + name);
      }
      links.add(CircuitLink(getPort(from), getPort(to)));
    }
    final wiring = CircuitWiring(links);
    wiring.validate();
    return wiring;
  }
}

class CascadeCircuitConfig {
  /// Both models are synthetic *individual* plant segments, not the saved
  /// one-loop FOPDT. Inner: FIC MV -> flow PV; outer: flow PV -> TIC PV.
  final Plant flow, temperature;
  final double ticPb, ticTi, ficPb, ficTi;
  final double dt, duration, stepAt, stepAmplitude;
  final double lagSeconds, actuatorSeconds;
  final double flowDisturbanceAt, flowDisturbance;

  const CascadeCircuitConfig({
    this.flow = const Plant(gain: 0.8, tau: 5, delay: 1),
    this.temperature = const Plant(gain: 0.8, tau: 17, delay: 3),
    this.ticPb = 180, this.ticTi = 45,
    this.ficPb = 110, this.ficTi = 12,
    this.dt = 0.2, this.duration = 180,
    this.stepAt = 30, this.stepAmplitude = 5,
    this.lagSeconds = 2, this.actuatorSeconds = 1,
    this.flowDisturbanceAt = 90, this.flowDisturbance = 2,
  });

  void validate() {
    flow.validate();
    temperature.validate();
    final numbers = <double>[
      ticPb, ticTi, ficPb, ficTi, dt, duration,
      stepAt, stepAmplitude, lagSeconds, actuatorSeconds,
      flowDisturbanceAt, flowDisturbance,
    ];
    if (numbers.any((x) => !x.isFinite) ||
        ticPb <= 0 || ticTi <= 0 || ficPb <= 0 || ficTi <= 0 ||
        dt <= 0 || duration <= 0 || duration / dt > 12000 ||
        dt > math.min(flow.tau, temperature.tau) / 2 ||
        stepAt < 0 || stepAt >= duration ||
        flowDisturbanceAt < 0 || flowDisturbanceAt > duration ||
        lagSeconds < 0 || actuatorSeconds < 0) {
      throw ArgumentError('Invalid cascade experiment');
    }
  }
}

class CircuitPoint {
  final double t, ticSp, ticPv, ticMv, ficSv, ficPv, ficMv, actualMv;
  final double? ticRl1, ficRl1;
  const CircuitPoint(this.t, this.ticSp, this.ticPv, this.ticMv,
    this.ficSv, this.ficPv, this.ficMv, this.actualMv,
    this.ticRl1, this.ficRl1);
}

class CircuitMetrics {
  final double temperatureIae, flowIae, totalMvTravel;
  const CircuitMetrics(this.temperatureIae, this.flowIae,
    this.totalMvTravel);
}

class CircuitRun {
  final List<CircuitPoint> points;
  final CircuitMetrics metrics;
  final CircuitWiring wiring;
  const CircuitRun(this.points, this.metrics, this.wiring);
}

/// Standalone normalized offline approximation, not CENTUM VP firmware.
/// Only TIC1.MV -> FIC1.SV is a live controller connection. The RL monitor
/// links expose signals on charts and do not secretly alter PID algorithms.
class CascadeCircuitSimulator {
  static CircuitRun simulate(CascadeCircuitConfig config, CircuitWiring wiring) {
    config.validate();
    wiring.validate();
    final dt = config.dt;
    final outerPid = CentumPidSimulator(CentumPidConfig(
      pb: config.ticPb, ti: config.ticTi, dt: dt,
      action: config.temperature.gain * config.flow.gain > 0
          ? ControllerAction.reverse : ControllerAction.direct));
    final innerPid = CentumPidSimulator(CentumPidConfig(
      pb: config.ficPb, ti: config.ficTi, dt: dt,
      action: config.flow.gain > 0
          ? ControllerAction.reverse : ControllerAction.direct));

    final innerA = math.exp(-dt / config.flow.tau);
    final outerA = math.exp(-dt / config.temperature.tau);
    final lagA = config.lagSeconds == 0
        ? 0.0 : math.exp(-dt / config.lagSeconds);
    final actuatorA = config.actuatorSeconds == 0
        ? 0.0 : math.exp(-dt / config.actuatorSeconds);
    final actualHistory = <double>[];
    final flowHistory = <double>[];
    final points = <CircuitPoint>[];

    var temperature = 50.0, flow = 50.0, actualMv = 50.0;
    var lagPv = flow, lastFicMv = 50.0;
    var temperatureIae = 0.0, flowIae = 0.0, mvTravel = 0.0;
    final steps = (config.duration / dt).ceil();

    double delayed(List<double> history, double lag, int k) {
      final pos = k - lag / dt;
      if (pos < 0) return 50;
      final lower = pos.floor();
      final upper = math.min(lower + 1, history.length - 1);
      final fraction = pos - lower;
      return history[lower] * (1 - fraction) +
          history[upper] * fraction;
    }

    for (var k = 0; k <= steps; k++) {
      final t = k * dt;
      final ticSp = 50 + (t >= config.stepAt ? config.stepAmplitude : 0.0);
      final tic = outerPid.step(sp: ticSp, pv: temperature,
        mode: ControllerMode.auto);
      final ficSv = wiring.contains(CircuitWiring.cascade) ? tic.mv : 50.0;
      final fic = innerPid.step(sp: ficSv, pv: flow,
        mode: ControllerMode.auto);
      actualMv = actuatorA * actualMv + (1 - actuatorA) * fic.mv;
      if (wiring.contains(CircuitWiring.pvToLag)) {
        lagPv = lagA * lagPv + (1 - lagA) * flow;
      }
      final ticRl1 = wiring.contains(CircuitWiring.directPvRl)
          ? flow
          : wiring.contains(CircuitWiring.lagToTicRl) ? lagPv : null;
      final ficRl1 = wiring.contains(CircuitWiring.actualMvRl)
          ? actualMv : null;

      if (![tic.mv, fic.mv, ficSv, actualMv, flow, temperature, lagPv]
          .every((x) => x.isFinite)) {
        throw StateError('Non-finite cascade experiment');
      }
      if (k > 0) {
        temperatureIae += (ticSp - temperature).abs() * dt;
        flowIae += (ficSv - flow).abs() * dt;
        mvTravel += (fic.mv - lastFicMv).abs();
      }
      points.add(CircuitPoint(t, ticSp, temperature, tic.mv, ficSv,
          flow, fic.mv, actualMv, ticRl1, ficRl1));
      lastFicMv = fic.mv;
      actualHistory.add(actualMv);
      flowHistory.add(flow);
      if (k == steps) break;

      final disturbance = t >= config.flowDisturbanceAt
          ? config.flowDisturbance : 0.0;
      final innerTarget = 50 +
          config.flow.gain * (delayed(actualHistory, config.flow.delay, k) - 50)
          + disturbance;
      final outerTarget = 50 +
          config.temperature.gain *
              (delayed(flowHistory, config.temperature.delay, k) - 50);
      flow = innerA * flow + (1 - innerA) * innerTarget;
      temperature = outerA * temperature + (1 - outerA) * outerTarget;
    }
    return CircuitRun(List.unmodifiable(points),
      CircuitMetrics(temperatureIae, flowIae, mvTravel), wiring);
  }
}

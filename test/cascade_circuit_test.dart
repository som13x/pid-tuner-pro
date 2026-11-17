import 'package:test/test.dart';
import 'package:pid_tuner_pro_core/auto_tune.dart';
import 'package:pid_tuner_pro_core/cascade_circuit.dart';

void main() {
  test('default graph reproduces the four intended named connections', () {
    final wiring = CircuitWiring(CircuitWiring.initial);
    wiring.validate();
    expect(wiring.links, hasLength(4));
    expect(wiring.contains(CircuitWiring.cascade), isTrue);
    expect(wiring.contains(CircuitWiring.pvToLag), isTrue);
    expect(wiring.contains(CircuitWiring.lagToTicRl), isTrue);
    expect(wiring.contains(CircuitWiring.actualMvRl), isTrue);
    expect(wiring.contains(CircuitWiring.directPvRl), isFalse);
  });

  test('links are serialized, restored, and validated with stable endpoint names', () {
    final graph = CircuitWiring(CircuitWiring.initial);
    final encoded = graph.toJson();
    final restored = CircuitWiring.fromJson(encoded);
    expect(restored.links, unorderedEquals(graph.links));
    expect(restored.contains(CircuitWiring.cascade), isTrue);
  });

  test('a destination cannot have two sources', () {
    expect(() => CircuitWiring([
      CircuitWiring.pvToLag, CircuitWiring.lagToTicRl,
      CircuitWiring.directPvRl,
    ]).validate(), throwsArgumentError);
  });

  test('filter output without input and unknown connection are rejected', () {
    expect(() => CircuitWiring([CircuitWiring.lagToTicRl]).validate(),
      throwsArgumentError);
    expect(() => CircuitWiring([
      const CircuitLink(CircuitPort.ticMv, CircuitPort.ficRl1),
    ]).validate(), throwsArgumentError);
    expect(() => CircuitWiring([CircuitWiring.cascade,
      CircuitWiring.cascade]).validate(), throwsArgumentError);
    expect(() => CircuitWiring.fromJson({
      'schemaVersion': 1,
      'links': [{'from': 'missing', 'to': 'ficSv'}],
    }), throwsFormatException);
    expect(() => CircuitWiring.fromJson({
      'schemaVersion': 999, 'links': [],
    }), throwsFormatException);
  });

  test('wiring changes which signal actually drives the FIC setpoint', () {
    const config = CascadeCircuitConfig(duration: 90);
    final connected = CascadeCircuitSimulator.simulate(
      config, CircuitWiring(CircuitWiring.initial));
    final disconnected = CascadeCircuitSimulator.simulate(
      config, CircuitWiring([]));
    expect(connected.points, isNotEmpty);
    expect(connected.points.length, disconnected.points.length);
    final afterStep = connected.points.firstWhere((p) => p.t > 33);
    final noLink = disconnected.points.firstWhere((p) => p.t > 33);
    expect(afterStep.ficSv, isNot(closeTo(50, 1e-5)));
    expect(noLink.ficSv, 50);
    expect(connected.points.last.ficPv, isNot(closeTo(50, 1e-4)));
    expect(disconnected.points.last.ficPv, greaterThanOrEqualTo(50));
  });

  test('RL1 is a monitored signal, not an undeclared controller reset input', () {
    const config = CascadeCircuitConfig(duration: 80, flowDisturbanceAt: 40);
    final base = CircuitWiring([CircuitWiring.cascade]);
    final monitored = CircuitWiring([
      CircuitWiring.cascade, CircuitWiring.pvToLag,
      CircuitWiring.lagToTicRl, CircuitWiring.actualMvRl,
    ]);
    final plain = CascadeCircuitSimulator.simulate(config, base);
    final extra = CascadeCircuitSimulator.simulate(config, monitored);
    for (var i = 0; i < plain.points.length; i++) {
      final a = plain.points[i], b = extra.points[i];
      expect(a.ficMv, closeTo(b.ficMv, 1e-10));
      expect(a.ticMv, closeTo(b.ticMv, 1e-10));
      expect(a.ticRl1, null);
      expect(a.ficRl1, null);
    }
    expect(extra.points.last.ticRl1, isNotNull);
    expect(extra.points.last.ficRl1, isNotNull);
    expect((extra.points.last.ficRl1! -
      extra.points.last.actualMv).abs(), lessThan(1e-10));
  });

  test('direct RL monitor bypasses the lag', () {
    const config = CascadeCircuitConfig(duration: 90, lagSeconds: 12);
    final direct = CascadeCircuitSimulator.simulate(config,
      CircuitWiring([CircuitWiring.cascade, CircuitWiring.directPvRl]));
    for (final p in direct.points) {
      expect(p.ticRl1, closeTo(p.ficPv, 1e-10));
    }
  });

  test('zero and negative process gains handled appropriately', () {
    final run = CascadeCircuitSimulator.simulate(
      const CascadeCircuitConfig(
        flow: Plant(gain: -0.7, tau: 5, delay: 1),
        temperature: Plant(gain: -0.6, tau: 17, delay: 3),
        duration: 80, flowDisturbanceAt: 40),
      CircuitWiring([CircuitWiring.cascade]));
    expect(run.points.every((p) => p.ticPv.isFinite &&
      p.ficPv.isFinite && p.ficMv.isFinite), isTrue);
    expect(() => CascadeCircuitSimulator.simulate(
      const CascadeCircuitConfig(
        flow: Plant(gain: 0, tau: 5, delay: 1)),
      CircuitWiring([CircuitWiring.cascade])), throwsArgumentError);
  });

  test('scenario rejects invalid time, lag, tuning and sample resolution', () {
    for (final config in [
      const CascadeCircuitConfig(dt: 20),
      const CascadeCircuitConfig(lagSeconds: -1),
      const CascadeCircuitConfig(ticTi: 0),
      const CascadeCircuitConfig(stepAt: 200),
      const CascadeCircuitConfig(duration: double.infinity),
      const CascadeCircuitConfig(actuatorSeconds: -1),
    ]) {
      expect(() => CascadeCircuitSimulator.simulate(
        config, CircuitWiring([CircuitWiring.cascade])),
        throwsArgumentError);
    }
  });
}

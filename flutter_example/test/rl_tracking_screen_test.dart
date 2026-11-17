import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pid_tuner_pro_demo/rl_tracking_screen.dart';

void main() {
  testWidgets('RL and tracking lab is distinct from a real DCS terminal',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: RlTrackingScreen(loopTag: 'FIC-80B')));
    expect(find.text('RL / External Tracking Lab'), findsOneWidget);
    expect(find.textContaining('RL1/RL2'), findsOneWidget);
    expect(find.textContaining('Демонстрационная FOPDT-модель'),
      findsOneWidget);
  });

  testWidgets('identified model suppresses demo-model warning',
      (tester) async {
    await tester.pumpWidget(MaterialApp(home: RlTrackingScreen(
      loopTag: 'FIC-80B', initialModel: const {
        'K': 0.81, 'T': 10, 'L': 3,
      })));
    expect(find.textContaining('Демонстрационная FOPDT-модель'),
      findsNothing);
    expect(find.text('RL / External Tracking Lab'), findsOneWidget);
  });
}

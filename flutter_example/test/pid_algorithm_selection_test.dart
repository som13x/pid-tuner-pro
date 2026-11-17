import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pid_tuner_pro_demo/simulation_screen.dart';

void main() {
  testWidgets('structure selector offers PID, PI-D, I-PD and comparison',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: SimulationScreen()));
    expect(find.text('Структура алгоритма'), findsOneWidget);
    await tester.tap(find.text('Сравнить PID / PI-D / I-PD'));
    await tester.pumpAndSettle();
    expect(find.text('PID: P, I, D по ошибке'), findsOneWidget);
    expect(find.text('PI-D: D по PV'), findsOneWidget);
    expect(find.text('I-PD: P и D по PV'), findsOneWidget);
    await tester.tap(find.text('I-PD: P и D по PV').last);
    await tester.pumpAndSettle();
    expect(find.text('I-PD: P и D по PV'), findsOneWidget);
    expect(find.textContaining('AUTO/MAN здесь означает режим'), findsOneWidget);
  });
}

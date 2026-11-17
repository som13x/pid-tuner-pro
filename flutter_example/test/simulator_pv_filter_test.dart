import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pid_tuner_pro_demo/simulation_screen.dart';

void main() {
  testWidgets('PV and derivative filter settings appear in simulation form',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: SimulationScreen()));
    expect(find.text('PV-фильтр, с (0=выкл)'), findsOneWidget);
    expect(find.text('D-фильтр, с'), findsOneWidget);
    expect(find.textContaining('Нулевое значение отключает фильтрацию'),
        findsOneWidget);
  });

  testWidgets('action can be chosen independently of algorithm structure',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: SimulationScreen()));
    final automatic = find.text('По знаку K (проверить на объекте)');
    await tester.ensureVisible(automatic);
    await tester.tap(automatic);
    await tester.pumpAndSettle();
    final direct = find.text('Direct action').last;
    await tester.tap(direct);
    await tester.pumpAndSettle();
    expect(find.text('Direct action'), findsOneWidget);
    await tester.ensureVisible(find.text('Структура алгоритма'));
    expect(find.text('Структура алгоритма'), findsOneWidget);
  });
}

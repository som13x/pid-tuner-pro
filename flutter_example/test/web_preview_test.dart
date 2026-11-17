import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pid_tuner_pro_demo/web_main.dart';

void main() {
  testWidgets('Safari preview opens only Step Test on an iPhone-sized screen',
      (tester) async {
    tester.view.physicalSize = const Size(430, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const PidTunerWebPreview());
    await tester.pumpAndSettle();

    expect(find.text('PID Tuner Pro · Step Test'), findsOneWidget);
    expect(find.text('Ручная оценка FOPDT по ступени MV'), findsOneWidget);
    expect(find.text('Ручной ввод'), findsOneWidget);
    expect(find.text('CSV / тренд'), findsOneWidget);
    expect(find.byType(ChoiceChip), findsNWidgets(2));
    expect(find.textContaining('Данные не сохраняются'), findsOneWidget);

    // Navigation to other labs must not be reachable in Safari preview.
    for (final section in [
      'Auto Tune', 'Simulation', 'Circuit Studio', 'Stability',
      'RL Tracking', 'Dual Valve LNG',
    ]) {
      expect(find.text(section), findsNothing);
    }
  });

  testWidgets('CSV remains accessible from the Step Test method selector',
      (tester) async {
    await tester.pumpWidget(const PidTunerWebPreview());
    await tester.tap(find.text('CSV / тренд'));
    await tester.pumpAndSettle();

    expect(find.byType(ChoiceChip), findsNWidgets(2));
    expect(find.text('Выбрать CSV-файл'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Идентифицировать по CSV'), 250,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('Идентифицировать по CSV'), findsOneWidget);
    expect(find.text('Ручная оценка FOPDT по ступени MV'), findsNothing);
  });

  testWidgets('returning from CSV restores manual Step Test',
      (tester) async {
    await tester.pumpWidget(const PidTunerWebPreview());
    await tester.tap(find.text('CSV / тренд'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ручной ввод'));
    await tester.pumpAndSettle();
    expect(find.text('Ручная оценка FOPDT по ступени MV'), findsOneWidget);
  });
}

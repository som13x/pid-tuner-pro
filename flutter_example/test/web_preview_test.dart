import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pid_tuner_pro_demo/web_main.dart';

void main() {
  testWidgets('web starts in Manual Step Test without native database', (tester) async {
    tester.view.physicalSize = const Size(430, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const PidTunerWebPreview());
    await tester.pumpAndSettle();
    expect(find.text('PID Tuner Pro · Web Preview'), findsOneWidget);
    expect(find.text('Ручной ввод'), findsOneWidget);
    expect(find.text('Ручная оценка FOPDT по ступени MV'), findsOneWidget);
    expect(find.textContaining('SQLite и резервные копии'), findsOneWidget);
  });

  testWidgets('web Auto Tune lets user enter an FOPDT plant', (tester) async {
    await tester.pumpWidget(const PidTunerWebPreview());
    await tester.tap(find.byKey(const Key('web-section-1')));
    await tester.pumpAndSettle();
    expect(find.text('Auto Tune · офлайн PI'), findsOneWidget);
    expect(find.text('Запустить Auto Tune'), findsOneWidget);
  });

  testWidgets('web allows switching from manual to CSV Step Test', (tester) async {
    await tester.pumpWidget(const PidTunerWebPreview());
    await tester.tap(find.text('CSV / тренд'));
    await tester.pumpAndSettle();
    expect(find.text('Выбрать CSV-файл'), findsOneWidget);
    expect(find.text('Идентифицировать по CSV'), findsOneWidget);
    expect(find.text('Ручная оценка FOPDT по ступени MV'), findsNothing);
  });
}

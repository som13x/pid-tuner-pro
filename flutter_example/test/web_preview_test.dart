import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:idb_shim/idb_shim.dart';
import 'package:pid_tuner_pro_core/dcs_controller_profiles.dart';
import 'package:pid_tuner_pro_core/step_test_settings.dart';
import 'package:pid_tuner_pro_demo/step_web_database.dart';
import 'package:pid_tuner_pro_demo/web_main.dart';

void main() {
  testWidgets('Safari opens Settings first on an iPhone-sized viewport',
      (tester) async {
    tester.view.physicalSize = const Size(430, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final db = StepWebDatabase(factory: newIdbFactoryMemory());
    await tester.pumpWidget(PidTunerWebPreview(database: db));
    await tester.pumpAndSettle();
    expect(find.text('PID Tuner Pro'), findsOneWidget);
    expect(find.text('Settings · параметры контура'), findsOneWidget);
    expect(find.byKey(const Key('top-settings')), findsOneWidget);
    expect(find.byKey(const Key('top-step-test')), findsOneWidget);
    expect(find.byKey(const Key('settings-tag')), findsOneWidget);
    db.close();
  });

  testWidgets('saved Settings restore to Step Test on the same browser DB',
      (tester) async {
    final factory = newIdbFactoryMemory();
    final initial = StepWebDatabase(factory: factory);
    await initial.saveSettings(const StepTestSettings(
      tag: 'PIC-17',
      comments: 'Pressure test',
      profileId: 'siemens-pcs7-pidconl',
      controlledVariable: ControlledVariable.pressure,
      tuningMethod: TuningMethod.imcConservative,
      acquisition: StepAcquisition.manualDelayAndT63,
    ));
    initial.close();

    final db = StepWebDatabase(factory: factory);
    await tester.pumpWidget(PidTunerWebPreview(database: db));
    await tester.pumpAndSettle();
    expect(find.text('Settings · параметры контура'), findsOneWidget);
    expect(tester.widget<TextField>(
      find.byKey(const Key('settings-tag'))).controller!.text, 'PIC-17');
    await tester.tap(find.byKey(const Key('top-step-test')));
    await tester.pumpAndSettle();
    expect(find.text('Step Test · PIC-17'), findsOneWidget);
    expect(find.text('Ручная оценка FOPDT по ступени MV'), findsOneWidget);
    expect(find.text('Ручной ввод'), findsNothing);
    expect(find.text('CSV / тренд'), findsNothing);
    expect(find.text('Auto Tune'), findsNothing);
    db.close();
  });

  testWidgets('DCS selections are available in the Settings form',
      (tester) async {
    final db = StepWebDatabase(factory: newIdbFactoryMemory());
    await tester.pumpWidget(PidTunerWebPreview(database: db));
    await tester.pumpAndSettle();
    final menu = tester.widget<DropdownButton<String>>(
      find.descendant(
        of: find.byKey(const Key('settings-system')),
        matching: find.byType(DropdownButton<String>),
      ));
    expect(menu.items!.map((e) => e.value).toSet(),
      DcsProfiles.all.map((p) => p.id).toSet());
    db.close();
  });
}

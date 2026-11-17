import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:idb_shim/idb_shim.dart';
import 'package:pid_tuner_pro_core/integrating_step_identification.dart';
import 'package:pid_tuner_pro_core/step_test_settings.dart';
import 'package:pid_tuner_pro_demo/integrating_manual_form.dart';
import 'package:pid_tuner_pro_demo/step_web_database.dart';
import 'package:pid_tuner_pro_demo/web_main.dart';

import 'fake_step_web_database.dart';

const levelSettings = StepTestSettings(
  tag: 'LIC-FOUR',
  profileId: 'yokogawa-centum-vp-pid',
  controlledVariable: ControlledVariable.level,
  tuningMethod: TuningMethod.opticontrolsLevel,
  acquisition: StepAcquisition.manualIntegratingSlope,
  integratingProcessConfirmed: true,
  stabilityMargin: 2,
  levelControlMode: LevelControlMode.pi,
);

void main() {
  testWidgets('Settings -> Step Test has four PV and T1/T2 minute inputs',
      (tester) async {
    tester.view.physicalSize = const Size(430, 2200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final db = FakeStepWebDatabase(configuration: levelSettings);
    await tester.pumpWidget(MaterialApp(home: WebPreviewHome(database: db)));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('top-step-test')));
    await tester.pumpAndSettle();

    for (final key in ['pv1','pv2','pv3','pv4','T1','T2','delay']) {
      expect(find.byKey(Key('integrating-' + key)), findsOneWidget);
    }
    for (final obsolete in ['t1','t2','t3','t4','baselineSlope']) {
      expect(find.byKey(Key('integrating-' + obsolete)), findsNothing);
    }
    expect(find.text('Slope 1 · до ступени MV'), findsOneWidget);
    expect(find.text('Slope 2 · после запаздывания'), findsOneWidget);
    expect(find.text('T1, мин'), findsOneWidget);
    expect(find.text('T2, мин'), findsOneWidget);
    expect(find.text('Запаздывание td, мин'), findsOneWidget);
    db.close();
  });

  testWidgets('minute interval form computes DS and passes evidence',
      (tester) async {
    tester.view.physicalSize = const Size(430, 2200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    IntegratingManualEstimate? estimate;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(child: IntegratingManualForm(
          onAccept: (result) => estimate = result,
        )),
      ),
    ));
    const inputs = <String, String>{
      'mvBefore': '40', 'mvAfter': '50',
      'pv1': '35', 'pv2': '36',
      'pv3': '45', 'pv4': '55',
      'T1': '2', 'T2': '4', 'delay': '0.5',
    };
    for (final item in inputs.entries) {
      await tester.enterText(
        find.byKey(Key('integrating-' + item.key)), item.value);
    }
    await tester.tap(find.byKey(const Key('integrating-calculate')));
    await tester.pumpAndSettle();

    expect(find.textContaining('ri = 0.200000 1/мин'), findsOneWidget);
    expect(find.textContaining('T1 = 2.000 мин; T2 = 4.000 мин'),
      findsOneWidget);
    expect(find.textContaining('DS = 2.00000 %/мин'), findsOneWidget);
    await tester.tap(find.byKey(const Key('integrating-save')));
    expect(estimate, isNotNull);
    expect(estimate!.plant.gainPerSecond, closeTo(.2 / 60, 1e-12));
    expect(estimate!.plant.delaySeconds, 30);
    expect(estimate!.evidence['pv3'], 45);
    expect(estimate!.evidence['T2Minutes'], 4);
    expect(estimate!.evidence['deadTimeMinutes'], .5);
  });

  test('IndexedDB preserves four PV and minute durations separately',
      () async {
    final factory = newIdbFactoryMemory();
    final db = StepWebDatabase(factory: factory);
    const input = IntegratingManualInput(
      mvBefore: 40, mvAfter: 50,
      pv1: 35, pv2: 36, pv3: 45, pv4: 55,
      t1Minutes: 2, t2Minutes: 4, delayMinutes: .5,
      mvSpanLow: 0, mvSpanHigh: 100,
      pvSpanLow: 0, pvSpanHigh: 100,
    );
    final result = const IntegratingManualEstimator().estimate(input);
    await db.saveSettings(levelSettings);
    await db.addIntegratingResult(
      settings: levelSettings,
      plant: result.plant,
      source: 'Manual Integrating Step (OptiControls minute intervals)',
      evidence: result.evidence,
    );
    db.close();
    final reloaded = StepWebDatabase(factory: factory);
    final rows = await reloaded.getResults();
    expect(rows, hasLength(1));
    final evidence = rows.single['evidence'] as Map;
    for (final key in ['pv1','pv2','pv3','pv4',
      'T1Minutes','T2Minutes','deadTimeMinutes']) {
      expect(evidence.containsKey(key), true,
        reason: 'Must preserve ' + key + ' for test audit');
    }
    for (final key in [
      't1Seconds','t2Seconds','t3Seconds','t4Seconds',
    ]) {
      expect(evidence.containsKey(key), false,
        reason: 'No synthetic absolute timestamps should be stored');
    }
    expect(evidence['timeUnit'], 'minute');
    expect(evidence['timeInputKind'], 'elapsedInterval');
    expect(evidence['pv3'], 45);
    expect(evidence['pv4'], 55);
    expect(evidence['T1Minutes'], 2);
    expect(evidence['T2Minutes'], 4);
    expect(evidence['deadTimeMinutes'], .5);
    expect(evidence['T1Seconds'], 120);
    expect(evidence['T2Seconds'], 240);
    expect((rows.single['model'] as Map)['KiPerSecond'],
      closeTo(.2/60, 1e-12));
    expect((rows.single['model'] as Map)['L'], 30);
    reloaded.close();
  });
}

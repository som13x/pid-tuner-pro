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
  testWidgets('Settings -> Step Test shows all PV1..PV4 and t1..t4 fields',
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

    for (final key in ['pv1','pv2','pv3','pv4',
      't1','t2','t3','t4']) {
      expect(find.byKey(Key('integrating-' + key)), findsOneWidget);
    }
    expect(find.text('Slope 1 · до ступени MV'), findsOneWidget);
    expect(find.text('Slope 2 · после запаздывания'), findsOneWidget);
    expect(find.byKey(const Key('integrating-baselineSlope')), findsNothing);
    db.close();
  });

  testWidgets('4-point form calculates slopes, DS and passes evidence',
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
      't1': '-20', 't2': '-10',
      't3': '20', 't4': '40',
      'delay': '5',
    };
    for (final item in inputs.entries) {
      await tester.enterText(
        find.byKey(Key('integrating-' + item.key)), item.value);
    }
    await tester.tap(find.byKey(const Key('integrating-calculate')));
    await tester.pumpAndSettle();

    expect(find.textContaining('ri = 0.040000 1/с'), findsOneWidget);
    expect(find.textContaining('T1 = 10.00 с; T2 = 20.00 с'), findsOneWidget);
    expect(find.textContaining('DS = 0.40000 %/с'), findsOneWidget);
    await tester.tap(find.byKey(const Key('integrating-save')));
    expect(estimate, isNotNull);
    expect(estimate!.plant.gainPerSecond, closeTo(.04, 1e-12));
    expect(estimate!.evidence['pv3'], 45);
    expect(estimate!.evidence['t4Seconds'], 40);
  });

  test('IndexedDB preserves all eight measured point values for audit',
      () async {
    final factory = newIdbFactoryMemory();
    final db = StepWebDatabase(factory: factory);
    const input = IntegratingManualInput(
      mvBefore: 40, mvAfter: 50,
      pv1: 35, pv2: 36, pv3: 45, pv4: 55,
      t1Seconds: -20, t2Seconds: -10,
      t3Seconds: 20, t4Seconds: 40,
      delaySeconds: 5,
      mvSpanLow: 0, mvSpanHigh: 100,
      pvSpanLow: 0, pvSpanHigh: 100,
    );
    final result = const IntegratingManualEstimator().estimate(input);
    await db.saveSettings(levelSettings);
    await db.addIntegratingResult(
      settings: levelSettings,
      plant: result.plant,
      source: 'Manual Integrating Step (OptiControls 4 points)',
      evidence: result.evidence,
    );
    db.close();
    final reloaded = StepWebDatabase(factory: factory);
    final rows = await reloaded.getResults();
    expect(rows, hasLength(1));
    final evidence = rows.single['evidence'] as Map;
    for (final key in ['pv1','pv2','pv3','pv4',
      't1Seconds','t2Seconds','t3Seconds','t4Seconds']) {
      expect(evidence.containsKey(key), true,
        reason: 'Must preserve ' + key + ' for the test audit');
    }
    expect(evidence['pv3'], 45);
    expect(evidence['pv4'], 55);
    expect(evidence['t3Seconds'], 20);
    expect(evidence['t4Seconds'], 40);
    expect(evidence['T1Seconds'], 10);
    expect(evidence['T2Seconds'], 20);
    expect(rows.single['model'], containsPair('KiPerSecond', .04));
    reloaded.close();
  });
}

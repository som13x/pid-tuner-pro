import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:idb_shim/idb_shim.dart';
import 'package:pid_tuner_pro_core/auto_tune.dart';
import 'package:pid_tuner_pro_core/integrating_step_identification.dart';
import 'package:pid_tuner_pro_core/dcs_controller_profiles.dart';
import 'package:pid_tuner_pro_core/step_test_settings.dart';
import 'package:pid_tuner_pro_demo/step_web_database.dart';
import 'package:pid_tuner_pro_demo/web_main.dart';
import 'fake_step_web_database.dart';

StepTestSettings example({
  String? profile,
  StepAcquisition method = StepAcquisition.manualDelayAndT63,
}) => StepTestSettings(
  tag: 'FIC-221',
  comments: 'Тестовый контур расхода',
  profileId: profile ?? DcsProfiles.yokogawaCentumVp.id,
  controlledVariable: ControlledVariable.flow,
  tuningMethod: TuningMethod.imcConservative,
  acquisition: method,
);

void main() {
  test('IndexedDB persists Settings and measured model between connections',
      () async {
    final factory = newIdbFactoryMemory();
    final first = StepWebDatabase(factory: factory);
    final configuration = example();
    await first.saveSettings(configuration);
    const model = Plant(gain: 1.5, tau: 15, delay: 3);
    final pi = const StepPiCalculator().calculate(model, configuration);
    await first.addResult(
      settings: configuration,
      plant: model,
      source: 'Manual Step 63.2%',
      evidence: {
        'method': 'knownDelayAndT63',
        'mvBefore': 40, 'mvAfter': 50,
        'pvBefore': 800, 'pvAfter': 950,
        't63Seconds': 18,
      },
      piEstimate: pi,
    );
    first.close();
    final reopened = StepWebDatabase(factory: factory);
    final loaded = await reopened.loadSettings();
    expect(loaded!.tag, 'FIC-221');
    expect(loaded.comments, 'Тестовый контур расхода');
    expect(loaded.profileId, DcsProfiles.yokogawaCentumVp.id);
    final rows = await reopened.getResults();
    expect(rows, hasLength(1));
    expect((rows.single['model'] as Map)['K'], 1.5);
    expect((rows.single['evidence'] as Map)['mvBefore'], 40);
    expect((rows.single['settings'] as Map)['tag'], 'FIC-221');
    expect((rows.single['piEstimate'] as Map)['method'], 'imcConservative');
    expect(rows.single['requiresEngineeringReview'], true);
    reopened.close();
  });

  test('each result keeps original settings snapshot after changes',
      () async {
    final db = StepWebDatabase(factory: newIdbFactoryMemory());
    final yokogawa = example();
    await db.saveSettings(yokogawa);
    await db.addResult(
      settings: yokogawa,
      plant: const Plant(gain: 1, tau: 10, delay: 2),
      source: 'Manual Step 63.2%',
      evidence: {'method': 'manual'},
    );
    final abb = example(profile: DcsProfiles.abb800xaPidcc.id,
      method: StepAcquisition.csvTrend);
    await db.saveSettings(abb);
    await db.addResult(
      settings: abb,
      plant: const Plant(gain: 2, tau: 20, delay: 4),
      source: 'Step Test CSV',
      evidence: {'rSquared': .94, 'nrmse': .06},
      originalCsv: 'time,mv,pv\n0,40,10\n1,50,11',
    );
    final records = await db.getResults();
    expect(records.length, 2);
    expect((records[0]['settings'] as Map)['profileId'],
      DcsProfiles.abb800xaPidcc.id);
    expect(records[0]['csvText'], contains('time,mv,pv'));
    expect((records[1]['settings'] as Map)['profileId'],
      DcsProfiles.yokogawaCentumVp.id);
    expect((await db.loadSettings())!.acquisition, StepAcquisition.csvTrend);
    db.close();
  });

  test('invalid settings are rejected and the earlier DB record stays',
      () async {
    final db = StepWebDatabase(factory: newIdbFactoryMemory());
    await db.saveSettings(example());
    final invalid = StepTestSettings(
      tag: '', profileId: DcsProfiles.yokogawaCentumVp.id,
      controlledVariable: ControlledVariable.flow,
      tuningMethod: TuningMethod.imcConservative,
      acquisition: StepAcquisition.csvTrend,
    );
    await expectLater(db.saveSettings(invalid), throwsArgumentError);
    expect((await db.loadSettings())!.tag, 'FIC-221');
    db.close();
  });

  test('IndexedDB stores typed IPDT results independently of FOPDT',
      () async {
    final factory = newIdbFactoryMemory();
    final db = StepWebDatabase(factory: factory);
    const ipdt = StepTestSettings(
      tag: 'LIC-50',
      profileId: 'yokogawa-centum-vp-pid',
      controlledVariable: ControlledVariable.level,
      tuningMethod: TuningMethod.opticontrolsLevel,
      acquisition: StepAcquisition.manualIntegratingSlope,
      integratingProcessConfirmed: true,
      stabilityMargin: 3,
      levelControlMode: LevelControlMode.pid,
    );
    await db.saveSettings(ipdt);
    final pi = const StepPiCalculator().calculateIntegrating(
      const IntegratingPlant(gainPerSecond: .04, delaySeconds: 5), ipdt);
    await db.addIntegratingResult(
      settings: ipdt,
      plant: const IntegratingPlant(gainPerSecond: .04, delaySeconds: 5),
      source: 'Manual Integrating Step',
      evidence: {'method': 'manualIntegratingRamp', 'slope': 0.4},
      piEstimate: pi,
    );
    db.close();
    final reopened = StepWebDatabase(factory: factory);
    final storedSettings = await reopened.loadSettings();
    expect(storedSettings!.tuningMethod,
      TuningMethod.opticontrolsLevel);
    final rows = await reopened.getResults();
    expect(rows, hasLength(1));
    final model = rows.single['model'] as Map;
    expect(model['type'], 'IPDT');
    expect(model['KiPerSecond'], .04);
    expect(model['L'], 5);
    expect(model.containsKey('T'), false);
    expect((rows.single['evidence'] as Map)['method'],
      'manualIntegratingRamp');
    expect((rows.single['settings'] as Map)['stabilityMargin'], 3);
    expect((rows.single['settings'] as Map)['levelControlMode'], 'pid');
    expect((rows.single['piEstimate'] as Map)['tiSeconds'], 30);
    expect((rows.single['piEstimate'] as Map)['tdSeconds'], 2.5);
    expect((rows.single['piEstimate'] as Map)['method'], 'opticontrolsLevel');
    reopened.close();
  });

  testWidgets('saved integrating choice opens true ramp model form',
      (tester) async {
    final db = FakeStepWebDatabase(configuration: const StepTestSettings(
      tag: 'LIC-33',
      profileId: 'yokogawa-centum-vp-pid',
      controlledVariable: ControlledVariable.level,
      tuningMethod: TuningMethod.opticontrolsLevel,
      acquisition: StepAcquisition.manualIntegratingSlope,
      integratingProcessConfirmed: true,
    ));
    await tester.pumpWidget(MaterialApp(home: WebPreviewHome(database: db)));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('top-step-test')));
    await tester.pumpAndSettle();
    expect(find.text('Step Test · LIC-33'), findsOneWidget);
    expect(find.text('OptiControls · Step Test (T1/T2 в минутах)'), findsOneWidget);
    expect(find.text('Ручная оценка FOPDT по ступени MV'), findsNothing);
    db.close();
  });

  testWidgets('saved integrating CSV selection stays in CSV mode',
      (tester) async {
    final db = FakeStepWebDatabase(configuration: const StepTestSettings(
      tag: 'LIC-34',
      profileId: 'siemens-pcs7-pidconl',
      controlledVariable: ControlledVariable.level,
      tuningMethod: TuningMethod.opticontrolsLevel,
      acquisition: StepAcquisition.csvIntegratingTrend,
      integratingProcessConfirmed: true,
    ));
    await tester.pumpWidget(MaterialApp(home: WebPreviewHome(database: db)));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('top-step-test')));
    await tester.pumpAndSettle();
    expect(find.text('Выбрать CSV-файл'), findsOneWidget);
    expect(find.text('Интегрирующий процесс · IPDT'), findsNothing);
    db.close();
  });

  testWidgets('Settings is the first tab, Step Test locked until saved',
      (tester) async {
    final db = FakeStepWebDatabase();
    await tester.pumpWidget(MaterialApp(home: WebPreviewHome(database: db)));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('top-settings')), findsOneWidget);
    expect(find.byKey(const Key('top-step-test')), findsOneWidget);
    expect(find.text('Settings · параметры контура'), findsOneWidget);
    expect(find.byKey(const Key('settings-tag')), findsOneWidget);
    final stepChip = tester.widget<ChoiceChip>(
      find.byKey(const Key('top-step-test')));
    expect(stepChip.onSelected, isNull);
    expect(find.text('Ручная оценка FOPDT по ступени MV'), findsNothing);
    db.close();
  });

  testWidgets('Settings exposes five DCS, process, tuning and step methods',
      (tester) async {
    final db = FakeStepWebDatabase();
    await tester.pumpWidget(MaterialApp(home: WebPreviewHome(database: db)));
    await tester.pumpAndSettle();
    final vendorDropdown = tester.widget<DropdownButton<String>>(
      find.descendant(
        of: find.byKey(const Key('settings-system')),
        matching: find.byType(DropdownButton<String>),
      ));
    expect(vendorDropdown.items, hasLength(5));
    await tester.drag(find.byKey(const Key('settings-form')),
      const Offset(0, -470));
    await tester.pumpAndSettle();
    expect(find.text('5. Рекомендуемый метод расчёта PI'), findsOneWidget);
    expect(find.text('IMC / Lambda (консервативный PI)'), findsWidgets);
    db.close();
  });

  testWidgets('saved CSV selection leads to Step Test with no other labs',
      (tester) async {
    final db = FakeStepWebDatabase(
      configuration: example(method: StepAcquisition.csvTrend));
    await tester.pumpWidget(MaterialApp(home: WebPreviewHome(database: db)));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('top-step-test')));
    await tester.pumpAndSettle();
    expect(find.text('Step Test · FIC-221'), findsOneWidget);
    expect(find.text('Выбрать CSV-файл'), findsOneWidget);
    expect(find.text('Ручная оценка FOPDT по ступени MV'), findsNothing);
    for (final section in [
      'Auto Tune', 'Simulation', 'Circuit Studio', 'Stability',
      'RL Tracking', 'Dual Valve LNG',
    ]) {
      expect(find.text(section), findsNothing);
    }
    db.close();
  });

  testWidgets('saved two-point selection configures manual Step Test',
      (tester) async {
    final db = FakeStepWebDatabase(
      configuration: example(method: StepAcquisition.manualTwoPoints));
    await tester.pumpWidget(MaterialApp(home: WebPreviewHome(database: db)));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('top-step-test')));
    await tester.pumpAndSettle();
    expect(find.text('Ручная оценка FOPDT по ступени MV'), findsOneWidget);
    expect(find.text('t28,35%, с'), findsOneWidget);
    expect(find.text('Запаздывание L, с'), findsNothing);
    db.close();
  });

  testWidgets('saving Settings unlocks Step Test and stores the TAG',
      (tester) async {
    tester.view.physicalSize = const Size(430, 3300);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final db = FakeStepWebDatabase();
    await tester.pumpWidget(MaterialApp(home: WebPreviewHome(database: db)));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('settings-tag')), 'FIC-900');
    await tester.ensureVisible(find.byKey(const Key('settings-save')));
    await tester.tap(find.byKey(const Key('settings-save')));
    await tester.pumpAndSettle();

    expect(db.configuration, isNotNull);
    expect(db.configuration!.tag, 'FIC-900');
    expect(db.configuration!.profileId, DcsProfiles.yokogawaCentumVp.id);
    expect(find.text('Step Test · FIC-900'), findsOneWidget);
    expect(tester.widget<ChoiceChip>(
      find.byKey(const Key('top-step-test'))).selected, true);
    db.close();
  });


  testWidgets('OptiControls Settings offer PI/PID, SM and no SIMC option',
      (tester) async {
    tester.view.physicalSize = const Size(430, 3300);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final db = FakeStepWebDatabase(configuration: const StepTestSettings(
      tag: 'LIC-200',
      profileId: 'yokogawa-centum-vp-pid',
      controlledVariable: ControlledVariable.level,
      tuningMethod: TuningMethod.opticontrolsLevel,
      acquisition: StepAcquisition.manualIntegratingSlope,
      integratingProcessConfirmed: true,
      stabilityMargin: 2,
    ));
    await tester.pumpWidget(MaterialApp(home: WebPreviewHome(database: db)));
    await tester.pumpAndSettle();
    final tuneDrop = tester.widget<DropdownButton<TuningMethod>>(
      find.descendant(
        of: find.byType(DropdownButtonFormField<TuningMethod>),
        matching: find.byType(DropdownButton<TuningMethod>),
      ));
    expect(tuneDrop.items!.any((item) =>
      item.value == TuningMethod.integratingProcessSimc), false);
    expect(tuneDrop.items!.any((item) =>
      item.value == TuningMethod.opticontrolsLevel), true);
    final typeDrop = tester.widget<DropdownButton<LevelControlMode>>(
      find.descendant(
        of: find.byKey(const Key('settings-level-mode')),
        matching: find.byType(DropdownButton<LevelControlMode>),
      ));
    expect(typeDrop.items, hasLength(2));
    expect(find.byKey(const Key('settings-stability-margin')), findsOneWidget);
    db.close();
  });

  testWidgets('saving OptiControls PID mode and SM retains input',
      (tester) async {
    tester.view.physicalSize = const Size(430, 3500);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final db = FakeStepWebDatabase(configuration: const StepTestSettings(
      tag: 'LIC-300',
      profileId: 'yokogawa-centum-vp-pid',
      controlledVariable: ControlledVariable.level,
      tuningMethod: TuningMethod.opticontrolsLevel,
      acquisition: StepAcquisition.manualIntegratingSlope,
      integratingProcessConfirmed: true,
    ));
    await tester.pumpWidget(MaterialApp(home: WebPreviewHome(database: db)));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('settings-stability-margin')), '3.5');
    await tester.tap(find.byKey(const Key('settings-level-mode')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('PID · Td = td / 2').last);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const Key('settings-save')), 300,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.byKey(const Key('settings-save')));
    await tester.pumpAndSettle();
    expect(db.configuration!.tag, 'LIC-300');
    expect(db.configuration!.levelControlMode, LevelControlMode.pid);
    expect(db.configuration!.stabilityMargin, 3.5);
    expect(db.configuration!.lambdaSeconds, isNull);
    expect(find.text('Step Test · LIC-300'), findsOneWidget);
    db.close();
  });

  test('existing archived SIMC record is not rewritten as OptiControls',
      () async {
    final db = StepWebDatabase(factory: newIdbFactoryMemory());
    const legacy = StepTestSettings(
      tag: 'LIC-OLD',
      profileId: 'yokogawa-centum-vp-pid',
      controlledVariable: ControlledVariable.level,
      tuningMethod: TuningMethod.integratingProcessSimc,
      acquisition: StepAcquisition.manualIntegratingSlope,
      integratingProcessConfirmed: true,
      lambdaSeconds: 25,
    );
    await db.addIntegratingResult(
      settings: legacy,
      plant: const IntegratingPlant(gainPerSecond: .01, delaySeconds: 5),
      source: 'Manual Integrating Step (legacy SIMC)',
      evidence: {'method':'manualIntegratingRamp'},
    );
    const current = StepTestSettings(
      tag: 'LIC-NEW',
      profileId: 'yokogawa-centum-vp-pid',
      controlledVariable: ControlledVariable.level,
      tuningMethod: TuningMethod.opticontrolsLevel,
      acquisition: StepAcquisition.manualIntegratingSlope,
      integratingProcessConfirmed: true,
      stabilityMargin: 2.5,
    );
    await db.saveSettings(current);
    await db.addIntegratingResult(
      settings: current,
      plant: const IntegratingPlant(gainPerSecond: .01, delaySeconds: 5),
      source: 'Manual Integrating Step (OptiControls)',
      evidence: {'method':'manualIntegratingRamp'},
      piEstimate: const StepPiCalculator().calculateIntegrating(
        const IntegratingPlant(gainPerSecond: .01, delaySeconds: 5), current),
    );
    final rows = await db.getResults();
    expect(rows, hasLength(2));
    expect((rows.first['settings'] as Map)['tuningMethod'],
      'opticontrolsLevel');
    expect((rows.last['settings'] as Map)['tuningMethod'],
      'integratingProcessSimc');
    expect((rows.last['settings'] as Map)['lambdaSeconds'], 25);
    expect(rows.last.containsKey('piEstimate'), false);
    db.close();
  });

}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:idb_shim/idb_shim.dart';
import 'package:pid_tuner_pro_core/auto_tune.dart';
import 'package:pid_tuner_pro_core/dcs_controller_profiles.dart';
import 'package:pid_tuner_pro_core/step_test_settings.dart';
import 'package:pid_tuner_pro_demo/step_web_database.dart';
import 'package:pid_tuner_pro_demo/web_main.dart';

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

  testWidgets('Settings is the first tab, Step Test locked until saved',
      (tester) async {
    final db = StepWebDatabase(factory: newIdbFactoryMemory());
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
    final db = StepWebDatabase(factory: newIdbFactoryMemory());
    await tester.pumpWidget(MaterialApp(home: WebPreviewHome(database: db)));
    await tester.pumpAndSettle();
    final vendorField = tester.widget<DropdownButtonFormField<String>>(
      find.byKey(const Key('settings-system')));
    expect(vendorField.items, hasLength(5));
    expect(find.text('5. Рекомендуемый метод расчёта PI'), findsOneWidget);
    expect(find.text('IMC / Lambda (консервативный PI)'), findsWidgets);
    db.close();
  });

  testWidgets('saved CSV selection leads to Step Test with no other labs',
      (tester) async {
    final db = StepWebDatabase(factory: newIdbFactoryMemory());
    await db.saveSettings(example(method: StepAcquisition.csvTrend));
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
    final db = StepWebDatabase(factory: newIdbFactoryMemory());
    await db.saveSettings(example(method: StepAcquisition.manualTwoPoints));
    await tester.pumpWidget(MaterialApp(home: WebPreviewHome(database: db)));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('top-step-test')));
    await tester.pumpAndSettle();
    expect(find.text('Ручная оценка FOPDT по ступени MV'), findsOneWidget);
    expect(find.text('t28,35%, с'), findsOneWidget);
    expect(find.text('Запаздывание L, с'), findsNothing);
    db.close();
  });
}

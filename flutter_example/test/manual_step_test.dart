import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pid_tuner_pro_core/manual_step_identification.dart';
import 'package:pid_tuner_pro_demo/main.dart' show StepTestScreen;
import 'package:pid_tuner_pro_demo/manual_step_form.dart';
import 'package:pid_tuner_pro_demo/project_store.dart';
import 'package:pid_tuner_pro_demo/sqlite_project_store.dart';
import 'package:pid_tuner_pro_demo/step_test_selection.dart';

ManualStepEstimate manualExample() => const ManualStepEstimator().estimate(
  const ManualStepInput(
    mvBefore: 40, mvAfter: 50,
    pvBefore: 800, pvAfter: 950,
    mvSpanLow: 0, mvSpanHigh: 100,
    pvSpanLow: 0, pvSpanHigh: 1000,
    t63Seconds: 18, delaySeconds: 3,
  ));

LoopProject newProject() => LoopProject(
  id: 'manual-test', tag: 'FIC-MAN',
  description: 'Manual estimated FOPDT',
  vendor: 'Yokogawa', controllerBlock: 'PID',
  createdAt: DateTime.utc(2026, 11, 17),
);

void main() {
  test('manual route result has no fabricated regression metrics', () {
    final selected = StepTestSelection.fromManual(manualExample());
    expect(selected.isManual, true);
    expect(selected.source, 'Manual Step 63.2%');
    expect(selected.rSquared, null);
    expect(selected.nrmse, null);
    expect(selected.manualEvidence!['qualityMetricsAvailable'], false);
    expect(selected.plant.gain, closeTo(1.5, 1e-12));
  });

  test('manual model and evidence round-trip through project SQLite', () async {
    final db = await PidDatabase.inMemory();
    try {
      final selected = StepTestSelection.fromManual(manualExample());
      final p = newProject().withIdentification(
        model: {
          'K': selected.plant.gain,
          'T': selected.plant.tau,
          'L': selected.plant.delay,
        },
        source: selected.source,
        rSquared: selected.rSquared,
        nrmse: selected.nrmse,
        manualEvidence: selected.manualEvidence,
      );
      await db.save([p]);
      final actual = (await db.load()).single;
      expect(actual.identifiedModel!['K'], 1.5);
      expect(actual.history.single['rSquared'], null);
      expect(actual.history.single['normalizedRmse'], null);
      expect(actual.history.single['requiresEngineeringReview'], true);
      final evidence = actual.history.single['manualEvidence'] as Map;
      expect(evidence['mvBefore'], 40);
      expect(evidence['t63Seconds'], 18);
      expect(evidence['measuredTrendAvailable'], false);
    } finally {
      await db.close();
    }
  });

  test('project refuses to mislabel manual fit as statistical validation', () {
    final selected = StepTestSelection.fromManual(manualExample());
    expect(() => newProject().withIdentification(
      model: {
        'K': selected.plant.gain,
        'T': selected.plant.tau,
        'L': selected.plant.delay,
      },
      source: selected.source,
      rSquared: 0.999,
      nrmse: 0.001,
      manualEvidence: selected.manualEvidence,
    ), throwsArgumentError);
  });

  testWidgets('Step Test lets the user choose CSV or manual inputs', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: StepTestScreen()));
    expect(find.text('CSV / тренд'), findsOneWidget);
    expect(find.text('Ручной ввод'), findsOneWidget);
    expect(find.text('Выбрать CSV-файл'), findsOneWidget);
    await tester.tap(find.text('Ручной ввод'));
    await tester.pumpAndSettle();
    expect(find.text('Ручная оценка FOPDT по ступени MV'), findsOneWidget);
    expect(find.text('MV до'), findsOneWidget);
    expect(find.text('PV после'), findsOneWidget);
    expect(find.text('Выбрать CSV-файл'), findsNothing);
  });

  testWidgets('manual calculation requires explicit confirmation',
      (tester) async {
    ManualStepEstimate? saved;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: SingleChildScrollView(
        child: ManualStepForm(onAccept: (estimate) { saved = estimate; }),
      )),
    ));
    final compute = find.text('Рассчитать K / T / L');
    await tester.ensureVisible(compute);
    await tester.tap(compute);
    await tester.pumpAndSettle();
    expect(find.textContaining('K = 1.5000'), findsOneWidget);
    expect(find.textContaining('R² и NRMSE не вычисляются'), findsOneWidget);
    final accept = find.byKey(const Key('manual-step-accept'));
    expect(tester.widget<FilledButton>(accept).onPressed, isNull);
    final consent = find.byKey(const Key('manual-step-confirm'));
    await tester.ensureVisible(consent);
    await tester.tap(consent);
    await tester.pumpAndSettle();
    await tester.ensureVisible(accept);
    await tester.tap(accept);
    expect(saved, isNotNull);
    expect(saved!.plant.tau, 15);
  });

  testWidgets('switching to two-point method changes form requirements',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: SingleChildScrollView(
        child: ManualStepForm(onAccept: (_) {}),
      )),
    ));
    final method = find.text('Время 28,35% и 63,21%');
    await tester.ensureVisible(method);
    await tester.tap(method);
    await tester.pumpAndSettle();
    expect(find.text('t28,35%, с'), findsOneWidget);
    expect(find.text('Запаздывание L, с'), findsNothing);
    final compute = find.text('Рассчитать K / T / L');
    await tester.ensureVisible(compute);
    await tester.tap(compute);
    await tester.pumpAndSettle();
    expect(find.textContaining('T = 15.00 с, L = 3.00 с'), findsOneWidget);
  });
}

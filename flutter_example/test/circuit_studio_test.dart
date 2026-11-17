import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pid_tuner_pro_core/cascade_circuit.dart';
import 'package:pid_tuner_pro_demo/circuit_studio_screen.dart';
import 'package:pid_tuner_pro_demo/project_store.dart';
import 'package:pid_tuner_pro_demo/sqlite_project_store.dart';

LoopProject project() => LoopProject(
  id: 'tic-fic-demo', tag: 'TIC1-FIC1',
  description: 'Synthetic cascade example',
  vendor: 'Yokogawa CENTUM VP', controllerBlock: 'PID',
  createdAt: DateTime.utc(2026, 11, 17),
);

void main() {
  test('wiring saves append-only with previous identification unchanged', () {
    final original = project().withIdentification(
      model: {'K': 0.8, 'T': 12, 'L': 2},
      source: 'Step Test', rSquared: 0.96, nrmse: 0.04);
    final graph = CircuitWiring(CircuitWiring.initial).toJson();
    final updated = original.withCircuitWiring(graph);
    final restored = CircuitWiring.fromJson(updated.latestCircuitWiring!);
    expect(restored.links, unorderedEquals(CircuitWiring.initial));
    expect(updated.history, hasLength(2));
    expect(updated.history.first, original.history.first);
    expect(updated.history.last['type'], 'circuitWiring');
    expect(updated.history.last['verifiedForDcsDeployment'], false);
    expect(updated.identifiedModel, original.identifiedModel);
  });

  test('repeated project saves retain all historical wiring versions', () async {
    final db = await PidDatabase.inMemory();
    try {
      var p = project();
      await db.save([p]);
      p = p.withCircuitWiring(
        CircuitWiring(CircuitWiring.initial).toJson());
      await db.save([p]);
      p = (await db.load()).single;
      p = p.withCircuitWiring(
        CircuitWiring([CircuitWiring.cascade]).toJson());
      await db.save([p]);
      final stored = (await db.load()).single;
      expect(stored.history, hasLength(2));
      expect(stored.latestCircuitWiring!['schemaVersion'], 1);
      expect(CircuitWiring.fromJson(stored.latestCircuitWiring!).links,
        [CircuitWiring.cascade]);
      expect(stored.history.first['type'], 'circuitWiring');
      expect(stored.history.last['type'], 'circuitWiring');
    } finally {
      await db.close();
    }
  });

  testWidgets('editor displays the active links and blocks', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: CircuitStudioScreen(loopTag: 'TIC1-FIC1')));
    expect(find.text('PID Tuner Pro · Circuit Studio v2.8'), findsOneWidget);
    expect(find.textContaining('TIC1.MV'), findsWidgets);
    expect(find.textContaining('FIC1.PV'), findsWidgets);
    expect(find.text('Схема'), findsOneWidget);
    expect(find.text('Связи'), findsOneWidget);
    expect(find.text('Тренды'), findsOneWidget);
  });

  testWidgets('links can be switched off and the diagram updates',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: CircuitStudioScreen()));
    await tester.tap(find.text('Связи'));
    await tester.pumpAndSettle();
    expect(find.text('TIC1.MV → FIC1.SV'), findsOneWidget);
    final switchRow = find.ancestor(
      of: find.text('TIC1.MV → FIC1.SV'),
      matching: find.byType(SwitchListTile));
    expect(switchRow, findsOneWidget);
    await tester.tap(find.descendant(
      of: switchRow, matching: find.byType(Switch)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Схема'));
    await tester.pumpAndSettle();
    expect(find.text('Активных связей: 3'), findsOneWidget);
  });

  testWidgets('saving exposes the edited typed graph', (tester) async {
    Map<String, dynamic>? saved;
    await tester.pumpWidget(MaterialApp(
      home: CircuitStudioScreen(onSave: (wiring) async {
        saved = wiring;
      }),
    ));
    await tester.tap(find.text('Сохранить схему в проект'));
    await tester.pumpAndSettle();
    expect(saved, isNotNull);
    expect(CircuitWiring.fromJson(saved!).links, hasLength(4));
  });
}

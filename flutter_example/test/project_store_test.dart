import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:pid_tuner_pro_demo/project_store.dart';

void main() {
  test('project JSON round trip retains loop identity and model', () async {
    final dir = await Directory.systemTemp.createTemp('pid_store_');
    try {
      final store = ProjectStore(File('${dir.path}/projects.json'));
      expect(await store.load(), isEmpty);
      final project = LoopProject(id: 'a', tag: 'FIC-80B',
        description: 'LNG flow', vendor: 'Yokogawa CENTUM VP',
        controllerBlock: 'PID', createdAt: DateTime.utc(2026, 11, 17),
        identifiedModel: {'K': 0.8, 'T': 12, 'L': 3});
      await store.save([project]);
      final loaded = await store.load();
      expect(loaded.single.tag, 'FIC-80B');
      expect(loaded.single.identifiedModel!['L'], 3);
      expect(loaded.single.createdAt, DateTime.utc(2026, 11, 17));
    } finally { await dir.delete(recursive: true); }
  });

  test('duplicate project IDs are rejected', () async {
    final dir = await Directory.systemTemp.createTemp('pid_store_');
    try {
      final store = ProjectStore(File('${dir.path}/projects.json'));
      final p = LoopProject(id: 'duplicate', tag: 'FIC', description: '',
        vendor: 'Generic', controllerBlock: 'PI', createdAt: DateTime.utc(2026));
      await expectLater(store.save([p, p]), throwsArgumentError);
    } finally { await dir.delete(recursive: true); }
  });

  test('unknown schema versions are rejected', () async {
    final dir = await Directory.systemTemp.createTemp('pid_store_');
    try {
      final file = File('${dir.path}/projects.json');
      await file.writeAsString('{"schemaVersion":99,"projects":[]}');
      await expectLater(ProjectStore(file).load(), throwsFormatException);
    } finally { await dir.delete(recursive: true); }
  });
}

// Workflow regression tests for schema v1 backwards compatibility and history.

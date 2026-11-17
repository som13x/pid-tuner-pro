import 'package:flutter_test/flutter_test.dart';
import 'package:pid_tuner_pro_core/dcs_controller_profiles.dart';
import 'package:pid_tuner_pro_demo/project_store.dart';
import 'package:pid_tuner_pro_demo/sqlite_project_store.dart';

LoopProject exampleLoop() => LoopProject(
  id: 'flow-80b', tag: 'FIC-80B', description: 'LNG total flow',
  vendor: DcsProfiles.yokogawaCentumVp.storedVendor,
  controllerBlock: DcsProfiles.yokogawaCentumVp.storedBlock,
  createdAt: DateTime.utc(2026, 11, 17),
);

void main() {
  test('changing DCS profile leaves fitted model unchanged and logs change', () {
    final original = exampleLoop().withIdentification(
      model: {'K': 0.81, 'T': 10, 'L': 3},
      source: 'Measured CSV', rSquared: 0.97, nrmse: 0.04);
    final updated = original.withControllerProfile(
      vendorName: DcsProfiles.siemensPcs7Pidconl.storedVendor,
      blockName: DcsProfiles.siemensPcs7Pidconl.storedBlock);
    expect(updated.identifiedModel, original.identifiedModel);
    expect(updated.history, hasLength(2));
    expect(updated.history.first, original.history.first);
    expect(updated.history.last['type'], 'profileChanged');
    expect(updated.history.last['previousVendor'], 'Yokogawa CENTUM VP');
    expect(DcsProfiles.forProject(updated.vendor, updated.controllerBlock),
      same(DcsProfiles.siemensPcs7Pidconl));
    expect(original.vendor, 'Yokogawa CENTUM VP');
  });

  test('no-op profile switch creates no spurious history entry', () {
    final old = exampleLoop();
    final updated = old.withControllerProfile(
      vendorName: old.vendor, blockName: old.controllerBlock);
    expect(updated, same(old));
    expect(() => old.withControllerProfile(vendorName: '', blockName: 'PID'),
      throwsArgumentError);
  });

  test('SQLite round trip preserves vendor, block, and audit history', () async {
    final db = await PidDatabase.inMemory();
    try {
      final original = exampleLoop().withIdentification(
        model: {'K': 0.81, 'T': 10, 'L': 3},
        source: 'Measured CSV', rSquared: 0.97, nrmse: 0.04);
      await db.save([original]);
      final updated = original.withControllerProfile(
        vendorName: DcsProfiles.abb800xaPidcc.storedVendor,
        blockName: DcsProfiles.abb800xaPidcc.storedBlock);
      await db.save([updated]);
      final fromDb = (await db.load()).single;
      expect(DcsProfiles.forProject(fromDb.vendor, fromDb.controllerBlock),
        same(DcsProfiles.abb800xaPidcc));
      expect(fromDb.identifiedModel!['K'], 0.81);
      expect(fromDb.history, hasLength(2));
      expect(fromDb.history.last['type'], 'profileChanged');
      expect(fromDb.history.last['previousBlock'], 'PID');
    } finally {
      await db.close();
    }
  });

  test('legacy and unknown profiles have explicit handling', () {
    expect(DcsProfiles.forProject('Yokogawa CENTUM VP', 'PID'),
      same(DcsProfiles.yokogawaCentumVp));
    expect(DcsProfiles.forProject('Legacy unknown vendor', 'PID'), isNull);
  });
}

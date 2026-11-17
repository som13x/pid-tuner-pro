import 'package:idb_shim/idb_shim.dart';

import 'step_web_factory_stub.dart'
  if (dart.library.js_interop) 'step_web_factory_browser.dart' as platform;

/// Browser IndexedDB, in-memory only when running Flutter VM tests.
IdbFactory makeStepDatabaseFactory() => platform.makeStepDatabaseFactory();

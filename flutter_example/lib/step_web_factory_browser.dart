import 'package:idb_shim/idb_shim.dart';
import 'package:idb_shim/idb_browser.dart';

/// Fail visibly if browser persistent storage is unavailable;
/// never silently substitute volatile memory as a durable database.
IdbFactory makeStepDatabaseFactory() => idbFactoryWeb;

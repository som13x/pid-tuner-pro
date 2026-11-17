# PID Tuner Pro v1.2 Preview

## Implemented

- SQLite persistence using Drift's native database connection and parameterized SQL.
- Separate relational tables for loops, identification results and append-only events.
- Transactional snapshot saves and ON DELETE CASCADE cleanup.
- One-time import from legacy `projects.json` when database is empty. The JSON file is preserved.
- Existing ProjectHome now uses SQLite by default.
- Four new repository tests using in-memory SQLite.

## Limitations

- SDK build and test execution have not been verified in this environment.
- Multi-Step Test selection UI, full trend-point persistence, report export and production migration/versioning are not implemented yet.
- Drift is used as the SQL execution/connection layer with hand-authored schema; generated Drift table classes are not yet used.
- Import is one-time and only when the database is empty. Back up files before migration.

## Run

```sh
cd flutter_example
flutter pub get
flutter test
flutter run
```

On iOS/Android, build requires the corresponding platform toolchains. The archive contains a Flutter package skeleton; generate missing platform scaffolding with `flutter create .` if necessary.

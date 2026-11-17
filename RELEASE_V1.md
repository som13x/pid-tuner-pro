# PID Tuner Pro v1.0 shell (source preview)

This release builds on v0.9 and adds a Flutter project home screen, local JSON-backed loop catalogue, creation/deletion, and navigation to the existing Step Test, Auto Tune, and Stability screens.

## Run

Install Flutter SDK (Dart >=3), then:

```sh
cd flutter_example
flutter pub get
flutter test
flutter run
```

Core tests:

```sh
cd ..
dart pub get
dart test
```

## Honest scope

- The Step Test and Stability screens are still separate prototype workflows.
- Identified models are **not yet persisted into project records** by the Step Test screen. The project model field is supported in the persistence schema but there is no UI binding for it yet.
- Auto Tune defaults to a demonstration model when no project-specific model exists.
- No PDF export, SQLite/Drift migration, native iOS/Android project scaffolding, or release signing is included.
- Existing stability demo includes placeholder quality values; never treat them as measured plant evidence.
- File persistence is offline and per-app, but the replace-by-rename strategy is not a fully transactional database. Migrate to Drift/SQLite before production use.
- Tests and compilation have **not** been run in this environment because Flutter and Dart SDKs are unavailable.
- No live DCS connection or approved field tuning.

## New files

- `flutter_example/lib/project_store.dart`
- `flutter_example/lib/project_home.dart`
- `flutter_example/test/project_store_test.dart`

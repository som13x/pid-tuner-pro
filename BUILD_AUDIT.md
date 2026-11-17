# Build audit (static), 2026-11-17

## Confirmed issue and fix

`flutter_example/test/*.dart` imports `package:flutter_test/flutter_test.dart`, but `flutter_example/pubspec.yaml` did not declare `flutter_test` as a dev dependency. Added `dev_dependencies: flutter_test: sdk: flutter`.

## Verified

- Source ZIP archive integrity.
- GitHub Actions workflow exists and creates Android host via `flutter create --platforms=android`.
- No `package:pid_tuner_pro/` stale imports in Dart files.

## Not verified

- `dart test`, `flutter test`, `flutter analyze`, and APK build: Dart/Flutter SDK unavailable in this execution environment.
- SQLite native library behavior on a physical device.
- Controller fidelity versus Yokogawa CENTUM VP.

## Next verification

Run `.github/workflows/android-preview.yml` on GitHub Actions, inspect the first failing step if any, then fix and rerun. Do not treat this archive as a verified installable app.

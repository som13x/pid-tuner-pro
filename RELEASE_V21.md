# PID Tuner Pro v2.1 — Build Readiness

This release focuses on getting an actual Android APK rather than adding unverified simulation features.

## Build in GitHub Actions

1. Upload the **contents of `pid_tuner_pro/`** to the root of a GitHub repository.
2. Open Actions > **Android preview APK and tests** > Run workflow.
3. The workflow installs Flutter, runs core Dart tests, creates Android host scaffolding with `flutter create`, runs Flutter tests, analyzes the app and builds a **debug APK**.
4. If all steps succeed, download the `pid-tuner-pro-android-debug` workflow artifact, unzip it and install `app-debug.apk` on Android.

If any step fails, **no verified APK is delivered**. Fix the failing diagnostics before claiming readiness. Debug builds are for internal testing, not production distribution.

## Build locally

```bash
cd pid_tuner_pro
flutter pub get
dart test
cd flutter_example
flutter create --platforms=android --project-name pid_tuner_pro_demo .
flutter pub get
flutter test
flutter analyze --no-fatal-infos
flutter build apk --debug
```

Output: `flutter_example/build/app/outputs/flutter-apk/app-debug.apk` after a successful build.

## Important

- This ZIP contains Flutter source but not a prebuilt APK or iOS IPA.
- iOS requires macOS, Xcode, signing and device provisioning or TestFlight distribution.
- PID/FOPDT models and the dual-valve feedforward are research approximations, **not validated CENTUM VP replicas**. Do not transfer settings to a live LNG plant without engineering review.
- Local environment used to package this release did not have Dart/Flutter SDK, so compilation and tests have **not** been executed here.

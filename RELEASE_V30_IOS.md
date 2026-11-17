# PID Tuner Pro v3.0 — iOS build and TestFlight foundation

This branch brings the existing Flutter app to **iOS** without changing
Android features or the control algorithms.

## What is actually ready

- Reproducible native Flutter iOS Runner using
  \`bash scripts/bootstrap_ios.sh\` from the repository root.
- Stable default bundle identifier \`com.som13x.pidtunerpro\` and
  display name **PID Tuner Pro**, minimum iOS 14.0.
- A macOS GitHub Actions job that checks Flutter tests, builds a
  **simulator .app** and unsigned physical-device .app, and attempts
  to launch the simulator build on an available iPhone simulator.
- A screenshot of the simulator launch when macOS has a compatible
  simulator runtime; a skipped simulator launch is reported explicitly.
- The native \`ios/\` folder is generated from the pinned-to-current
  stable Flutter template. The first trusted branch push can commit it
  to the feature branch through the workflow token.
- No new PI/PID features and no changes to Android Gradle config.

**Neither the simulator app nor the unsigned iPhoneOS app is installable
directly on a physical iPhone.** iOS requires Apple code signing for
device installation, and TestFlight requires App Store Connect access.
Do not try to rename the unsigned archive to \`.ipa\` or install the
simulator artifact on an iPhone.

## Build on a Mac

Prerequisites: macOS, compatible Xcode + Xcode command-line tools,
Flutter stable, CocoaPods (as required by your Flutter/plugin version).

From the repository root:

    bash scripts/bootstrap_ios.sh
    cd flutter_example
    flutter pub get
    flutter test
    flutter build ios --simulator --debug
    flutter build ios --release --no-codesign

Open \`flutter_example/ios/Runner.xcworkspace\` in Xcode (not only the
.xcodeproj if CocoaPods are in use). Select the Runner target, Signing &
Capabilities, set your Apple Development Team, and choose a unique
registered bundle ID if needed. On a trusted iPhone with Developer Mode
enabled, use Xcode's Run or \`flutter run -d <DEVICE_ID>\` with a valid
development provisioning profile.

A personal/free Apple ID can often be used for *local* development
signing in Xcode, subject to Apple's current device/provisioning rules;
it does **not** grant TestFlight distribution.

## TestFlight: steps that remain external

1. Enrol in the Apple Developer Program and obtain access to App Store Connect.
2. Register the exact bundle ID you will distribute and create an app record
   in App Store Connect.
3. Provision distribution certificates/profiles (or Xcode automatic
   signing in a trusted Mac), set up secure signing material and an
   App Store Connect API key for a release workflow.
4. Increase the version/build number, build a **signed** iOS archive,
   upload it to App Store Connect, and invite internal or external
   TestFlight testers as appropriate.

**Never commit .p12 certificates, .mobileprovision profiles, .p8 API
keys, private passwords, or signing credentials to GitHub.** The
\`com.som13x.pidtunerpro\` bundle ID is a starting suggestion, not proof
that it is registered to an Apple Developer team. App Store distribution
is intentionally not attempted by the unsigned CI.

## Manual smoke-test checklist (device or simulator)

- Launch / project creation and local SQLite persistence.
- Step Test: CSV file import through the iOS document picker.
- Step Test: manual K/T/L form and the 28.35% / 63.21% methods.
- Auto Tune, stability curves, RL Tracking, and Circuit Studio.
- Project JSON backup export and import using the iOS document picker.
- Navigate back and reopen a saved project; verify histories and graphs.
- Test on a real iPhone before calling the application iOS-verified.

Successful compilation and an iOS simulator launch do **not** by themselves
prove all file dialogs, SQLite persistence or control calculations work
on a physical phone. All process simulations remain offline.

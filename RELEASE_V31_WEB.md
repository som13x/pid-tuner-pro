# PID Tuner Pro v3.1 — Safari Web Preview

This is a **Flutter Web preview**, not a signed iOS application. It
uses the same Dart core and the pure Flutter simulator screens as the
Android and iOS versions.

## Safari-compatible functionality

- Manual FOPDT Step Test using 63.21% or two response times
- CSV Step Test via document picker or pasted \`time,mv,pv\` trend
- Offline Auto Tune with K/T/L from Step Test or manual input
- Closed-loop Simulation, Circuit Studio, Stability Studio,
  RL Tracking Lab, and Dual Valve LNG scenario
- Model accepted from Step Test is available to the simulation and
  Auto Tune screens while the page remains open

**Deliberate limits of this initial browser preview:**

- No persistent loop projects, native SQLite, model history or backups.
  All accepted models and wiring exist **only in this browser tab**.
- Refreshing or closing Safari discards the session.
- No DCS connection or plant control.
- No claims of validated plant performance from synthetic simulations.
- Some physical keyboard/file dialogs differ between browser and
  the native iOS app.
- This release does **not** include an iPhone IPA or a TestFlight build.

## Build

From the repository root with Flutter stable:

    cd flutter_example
    flutter create --platforms=web --project-name pid_tuner_pro_demo --no-pub .
    flutter pub get
    flutter test
    flutter build web --release --target lib/web_main.dart --base-href /pid-tuner-pro/

Web entry point: \`flutter_example/lib/web_main.dart\`.

## GitHub Pages publishing

Workflow \`.github/workflows/safari-preview.yml\` runs on pushes to
\`feature/v3.1-safari-web-preview\`, verifies Dart / Flutter, publishes
the compiled site as a downloadable artifact and pushes it to
the \`gh-pages\` branch.

The repository owner must enable Pages in:
**Settings → Pages → Build and deployment → Deploy from a branch**,
then choose **gh-pages / (root)**.

The expected URL, once the Pages configuration is enabled and its
deployment completes:

    https://som13x.github.io/pid-tuner-pro/

Do **not** claim this URL is live until it has been verified.

This preview needs no Apple Developer certificate or Mac to open on
iPhone Safari. Browser persistence / web backups are separate future work.

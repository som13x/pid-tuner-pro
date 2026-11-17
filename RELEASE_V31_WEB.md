# PID Tuner Pro v3.1 — Safari Step Test Preview

This is a Flutter Web **Step Test–only** preview for iPhone Safari,
not a signed native iOS app. Android and native iOS builds are unchanged.

## Features retained

- Manual Step Test: enter MV/PV values and low/high spans, determine
  FOPDT K/T/L by known dead time and 63.21% time or by the
  28.35% and 63.21% response times.
- CSV Step Test: import a local CSV/TXT through Safari or paste a
  time,mv,pv trend, identify FOPDT and display fit quality.
- Predicted/observed trend visualizations and estimated model results.
- Two Step Test input modes: **Ручной ввод** and **CSV / тренд**.

The Safari interface has **no section/navigation tabs** for Auto Tune,
Simulation, Circuit Studio, Stability, RL Tracking or Dual Valve LNG.
Those features remain available in the Android/native iOS source app,
but are intentionally excluded from this Safari build.

## Browser-specific limits

- No persistent project store, SQLite, model history or backup support.
  Results exist only while the browser tab stays open.
- A model accepted inside Step Test is marked session-only. Reloading
  Safari discards it.
- No plant connection, actual MV step command or DCS setting changes.
- A synthetic FOPDT graph is not a measurement. Manual estimates
  have no statistical fit quality metrics.

## Build

From repository root with Flutter stable:

    cd flutter_example
    flutter create --platforms=web --project-name pid_tuner_pro_demo --no-pub .
    flutter pub get
    flutter test
    flutter build web --release --target lib/web_main.dart --base-href /pid-tuner-pro/

Entry point: \`flutter_example/lib/web_main.dart\`.

Workflow \`.github/workflows/safari-preview.yml\` runs tests, builds
web and pushes static files to \`gh-pages\` on
\`feature/v3.1-safari-web-preview\` pushes.

Deployment URL once GitHub Pages is configured and live:
https://som13x.github.io/pid-tuner-pro/

On GitHub, Pages should be configured to serve **gh-pages / (root)**.
Check the URL after the workflow completes before declaring it live.

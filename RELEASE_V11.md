# PID Tuner Pro v1.1 preview

## New
- Step Test result can now be attached to the selected project, subject to `suitableForAutoTune`.
- Auto Tune and Stability buttons require an identified model in that project.
- Stability screen accepts the selected project's model and removes the unrelated demonstration model.
- Auto Tune report can be explicitly saved to the selected project.
- Project JSON retains identification and tuning history; schema version stays 1, history is optional for old files.
- Four new workflow tests.

## Limitations
- JSON history can grow large because tuning reports include sample arrays; migrate to Drift/SQLite before production.
- No native file sharing or PDF export yet.
- The Step Test source currently records a generic CSV label, not a cryptographic source hash.
- Stability uses a single identified model; robust ensemble from several Step Tests remains a separate workflow.
- No automatic application to DCS. Vendor PID emulation remains unverified.
- Dart/Flutter SDK unavailable in this environment: build/tests not executed.

# PID Tuner Pro v1.3 Preview

Adds Loop History & Model Management to the existing Flutter example.

- Non-destructive schema migration: optional `operating_point` field and `active_models` table.
- List identification records per loop with source, date, K/T/L and quality indicators.
- Select active identification for existing Auto Tune / Stability screens.
- Store a free-form operating point note per identification.
- Compare parameter ranges across selected identifications (descriptive only).
- Three new Flutter tests for selection, loop isolation and metadata persistence.

## Limitations

- This is a source preview, not an installable Android/iOS application.
- Robust Auto Tune is not yet launched from multi-selection in the history screen.
- Operating point is free text, not yet a validated structured process record.
- Existing v1.2 database is migrated on opening; back up before production use.
- Dart / Flutter tests and compilation have not been executed in this environment.

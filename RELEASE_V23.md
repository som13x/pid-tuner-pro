# PID Tuner Pro v2.3 (Android preview)

## Local project backups

The projects screen has a backup menu (save icon) with **Export JSON** and **Restore JSON**.
Export uses the system Save As picker; it does not upload anything to a server.

The versioned backup contains:
- loop IDs, tags, descriptions and controller metadata;
- *all* FOPDT identifications (K/T/L), fit quality, source, timestamp and operating point;
- the currently active identification for every loop;
- append-only history events including stored Auto Tune reports.

Restore validates the JSON and model constraints before writing. Existing projects
are never replaced without explicit user confirmation. Replacement runs inside
one SQLite transaction; on database failure, the previous data must remain intact.

**Not included:** original CSV trend files, device settings, external Yokogawa
DCS configuration, and other files not stored in the local database. Keep the
exported JSON outside the application's storage before uninstalling or changing devices.

## Verification

New tests cover the backup round-trip, non-overwrite default, invalid input,
active model selection and rollback on SQL errors. CI runs Flutter tests and
Android debug APK build on the pull request. Do not treat CI build success
as verification of CENTUM VP dynamics or plant-safe tuning.

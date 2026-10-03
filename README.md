# Pharmacy Ledger

A simple, secure, **offline** digital ledger for a pharmacy owner.
Fast entry + automatic calculations + clear reports + secure access + reliable local data.

- Package: `com.pharmacy.ledger` · Version 1.0.0 · Android 7.0+ (API 24)
- Flutter (Dart 3.6+ / Flutter 3.27+), SQLite, no internet permission, no account

## What it does

| Area | Details |
|---|---|
| Sales | Always TRY. Amount only; the local time is recorded automatically. |
| Warehouse payments | Warehouse (pick or "+ Add New Warehouse"), amount, USD / SYP / TRY, optional invoice number and note. |
| Reports | Home dashboard (Today / This Week / This Month / This Year), Today screen, Week (weeks 1-7, 8-14, 15-21, 22-28, 29-end), Month (totals + calendar + weeks), Year (12 months + annual totals). |
| Currency rule | Currencies are **never** added together or converted. Every total is shown per currency. |
| Edit / delete | Every transaction; delete always asks "Are you sure you want to delete this transaction?". |
| Warehouses | Totals per currency, number of payments, paginated history, rename, deactivate (history kept). |
| Search | Warehouse name or invoice number; filter by date range, currency, warehouse. |
| Security | App Lock with PIN (salted PBKDF2 hash in Keystore-backed storage, escalating lockout), fingerprint via the official Android BiometricPrompt, lock timing (immediately / 30 s / 1 min / 5 min). |
| Backup | JSON backup with SHA-256 checksum, optional AES-256-GCM password encryption. Save to device or share to Google Drive etc. Restore validates everything first, asks for confirmation, keeps a safety snapshot, and replaces data atomically. |
| Appearance | Light, Dark, System. English UI, LTR, Western digits (`12,345`). |

## Build the APK

Requirements: Flutter stable (3.27 or newer), Android SDK, JDK 17.

```bash
cd pharmacy_ledger
flutter pub get                   # the Gradle wrapper and local.properties are generated automatically
flutter test                      # unit tests (Linux needs: sudo apt install libsqlite3-dev)
flutter build apk --release       # -> build/app/outputs/flutter-apk/app-release.apk
```

Install on a phone: `flutter install` or copy `app-release.apk` to the phone and open it.

### Signing with your own key (recommended for real use)

```bash
keytool -genkey -v -keystore ~/pharmacy-ledger-release.jks -keyalg RSA -keysize 2048 -validity 10000 -alias pharmacyledger
cp android/key.properties.example android/key.properties   # then fill in the values
flutter build apk --release
```

Keep the keystore safe: Android only accepts updates signed with the same key.
Without `key.properties` the release APK is signed with the debug key (fine for personal installs).

### No local Flutter? Build in the cloud

Push this folder to a GitHub repository. The included workflow
`.github/workflows/build-apk.yml` runs the tests and builds the release APK;
download it from the workflow run's **Artifacts**.

## Project structure

```
lib/
  main.dart, app.dart, services.dart      entry point, lock gate, composition root
  core/        currency, money (integer minor units), dates & reporting weeks, theme
  data/        SQLite schema, models, repositories (warehouses, transactions, settings)
  domain/      validation rules, PeriodSummary, ReportService (all aggregation)
  security/    PIN hashing, biometric wrapper, AppLockController
  backup/      backup create / validate / restore
  ui/          screens (home, today, reports, warehouses, search, settings, lock, welcome) and widgets
android/app/src/main/kotlin/.../MainActivity.kt   FlutterFragmentActivity + Keystore key that detects fingerprint enrollment changes
test/          money, dates, transactions & reports, backup, security
```

See `docs/SPECIFICATION_ANALYSIS.md` for the architecture, schema, flows, business rules and test plan.

## Manual device test checklist

Automated tests cover business logic, reports, backup and the lock state machine with a fake biometric sensor.
Verify these on a real phone before relying on the app:

1. Enable App Lock + Biometric Unlock, close the app fully, reopen: Android fingerprint prompt appears.
2. Wrong finger 3-5 times: message shown, PIN pad still works.
3. Tap "Use PIN" on the prompt: PIN pad works.
4. Add a new fingerprint in Android Settings, reopen the app: biometric unlock is switched off with an explanation, PIN works.
5. Remove the phone's screen lock: the app falls back to PIN without crashing.
6. Send the app to background for longer than the lock timing: it locks. Short switches do not re-prompt.
7. Create a backup (with and without password), restore it, try a random file: rejected safely.
8. Dark mode, large system font, small screen: nothing overlaps.

# Pharmacy Ledger: Specification Analysis (Section 68)

## 1. Architecture

Layered, clean-architecture style; dependencies point inward only.

```
UI (screens, widgets, controllers)            lib/ui
   │  reads via Provider, never touches SQL
Domain (validation, reports, summaries)       lib/domain
   │
Data (SQLite schema, repositories, models)    lib/data
Security (PIN, biometrics, lock state)        lib/security
Backup (create / validate / restore)          lib/backup
Core (money, currency, dates, theme)          lib/core
Platform (Kotlin Keystore guard key)          android/.../MainActivity.kt
```

* `AppServices` (lib/services.dart) is the composition root.
* `LedgerStore` is bumped after every write; screens re-run cheap indexed aggregate
  queries, so nothing on screen can drift from the stored transactions.
* Extensible: new transaction types (EXPENSE, SALARY, RENT...) and currencies only need
  a new enum value + CHECK constraint migration; reports already group by type/currency.

## 2. Database schema (SQLite, schema v1)

```sql
warehouses(
  id INTEGER PK AUTOINCREMENT,
  name TEXT NOT NULL,                 -- display name, whitespace-normalized
  name_key TEXT NOT NULL UNIQUE,      -- lower-case normalized name (duplicate guard)
  is_active INTEGER NOT NULL DEFAULT 1 CHECK (is_active IN (0,1)),
  created_at TEXT NOT NULL, updated_at TEXT NOT NULL)

transactions(
  id INTEGER PK AUTOINCREMENT,
  type TEXT NOT NULL CHECK (type IN ('SALE','PAYMENT')),
  amount_minor INTEGER NOT NULL CHECK (amount_minor > 0),   -- 1 TRY = 100
  currency TEXT NOT NULL CHECK (currency IN ('TRY','USD','SYP')),
  warehouse_id INTEGER REFERENCES warehouses(id) ON DELETE RESTRICT,
  invoice_number TEXT, note TEXT,
  transaction_date TEXT NOT NULL,     -- 'yyyy-MM-dd' local date
  transaction_time TEXT NOT NULL,     -- 'HH:mm:ss' local time
  created_at TEXT NOT NULL, updated_at TEXT NOT NULL,
  CHECK ((type='SALE' AND currency='TRY' AND warehouse_id IS NULL)
      OR (type='PAYMENT' AND warehouse_id IS NOT NULL)))

INDEX (transaction_date, type, currency)   -- every period report
INDEX (warehouse_id, transaction_date)     -- warehouse history
INDEX (invoice_number)                     -- search
INDEX (is_active, name_key)                -- warehouse lists
```

Money is stored as 64-bit integer minor units. No floating point anywhere.
Max single amount: 999,999,999,999 (whole units).

## 3. Entity relationships

`warehouses 1 ── * transactions (PAYMENT only)`. SALE rows have `warehouse_id = NULL`.
`ON DELETE RESTRICT` + "deactivate instead of delete" keeps historical payments valid forever.
A warehouse can only be hard-deleted if it has never been used.

## 4. Screen map

```
Welcome ─ Get Started ─ (optional) Set up App PIN
Lock screen (fingerprint prompt → PIN pad)
Bottom navigation:
  Home        dashboard cards: Today · This Week · This Month · This Year,  + Add Sale  + Add Payment,  Search
  Today       date, Today's Sales + sale lines, Payments + totals per currency
  Reports     [Week | Month | Year]
     Week   month selector → Week 1..5 cards → Week detail (total + Day 1..n) → Day
     Month  month selector → totals, calendar (tap day → sheet → View transactions), weeks, Monthly Total
     Year   year selector → 12 month cards → Month report,  Annual Total
  Warehouses  list/search → detail (count, TRY/USD/SYP totals, paged history, rename/deactivate)
  Settings    Appearance · Security · Backup · Warehouses · About
Forms: Add/Edit Sale, Add/Edit Payment (warehouse picker with + Add New Warehouse)
```

## 5. Navigation flow

Drill-down required by §51 works: Reports → Year 2026 → September 2026 → Week 3 → September 18 → transactions.
Android back returns to Home from other tabs before leaving the app.

## 6. Business rules

* Sale: type SALE, currency TRY (not selectable), no warehouse, time = device time at save.
* Payment: warehouse required, currency USD/SYP/TRY required, invoice & note optional.
* Currencies are never summed together or converted. No profit is calculated or displayed.
* Totals are never stored; always aggregated from `transactions`.
* Editing/deleting any transaction immediately affects its day, week, month and year.
* Warehouse names: trimmed, internal whitespace collapsed, case-insensitive unique.
* Adding a name that matches a deactivated warehouse reactivates the original record.

## 7. Validation rules (English messages)

| Case | Message |
|---|---|
| empty / zero / negative / non-numeric amount | Please enter a valid amount. |
| more than 12 whole digits | This amount is too large. |
| payment without warehouse | Please select a warehouse. |
| payment without currency | Please select a currency. |
| empty warehouse name | Please enter a warehouse name. |
| duplicate warehouse | A warehouse with this name already exists. (existing one is selected) |

Enforced three times: form validators, `Validators.validateTransaction`, and SQLite CHECK constraints.

## 8. Reporting rules

* Day: `transaction_date = d`.
* Reporting week of a month: days 1-7, 8-14, 15-21, 22-28, 29-end. A 28-day February has 4 weeks;
  no empty 5th week; every day belongs to exactly one week. ISO weeks are not used.
* Dashboard "This Week" = the reporting week that contains today.
* Month: first..last day (handles 28/29/30/31 and leap years). Year: Jan 1..Dec 31.
* Query: `SELECT type, currency, SUM(amount_minor), COUNT(*) ... WHERE transaction_date BETWEEN ? AND ? GROUP BY type, currency`.
  Daily / monthly breakdowns add `transaction_date` / month to the GROUP BY.

## 9. Security flow

```
Cold start ─ App Lock on? ─ no → app
                         └ yes → Lock screen
                                   ├ Biometric on? → check Keystore guard key
                                   │     invalidated/missing → turn biometric off, explain, PIN
                                   │     availability: none / not enrolled / unavailable → message, PIN
                                   │     BiometricPrompt: success → unlock
                                   │                      cancel / fail / lockout → message, PIN
                                   └ PIN pad → PBKDF2 verify → unlock
                                         5 wrong → 30 s lock, doubling up to 15 min
Background → resume after ≥ timeout → locked again (own system dialogs are ignored)
```

* PIN: 4-8 digits, PBKDF2-HMAC-SHA256 (120k iterations, 16-byte salt) in Keystore-backed secure storage;
  never stored or shown in plaintext.
* Enabling biometric requires a successful system biometric prompt; disabling it or App Lock requires the PIN.
* Security flags live in secure storage, not plain preferences. `allowBackup=false` so Android cloud backup
  can't restore undecryptable secrets.
* If secure storage is wiped (device credentials reset) the app fails safe to "unlocked + App Lock off"
  instead of locking the owner out of their data.

## 10. Backup / restore flow

Create: optional password → choose Save to device / Share → JSON file
`{format, format_version, schema_version, app_version, created_at, counts, checksum_sha256, data | encrypted payload}`.
Encrypted payload: AES-256-GCM, key = PBKDF2-SHA256(password, 16-byte salt, 150k iterations).

Restore: pick file → parse → format/version check → (password) → checksum → per-row structural and
business-rule validation → summary + "Restoring this backup will replace the current application data.
Do you want to continue?" [Cancel] [Restore] → safety snapshot of current data (last 3 kept) →
single SQLite transaction: delete all + insert all. Any failure rolls back; current data is untouched.

## 11. Test cases

Automated (`flutter test`):

* money_test: parsing, 0.1+0.2 exactness, invalid input, huge amounts, formatting `1,250 TRY`, validators.
* dates_test: 28-day, leap 29-day, 30-day, 31-day months, no day lost (2024-2030), year transitions, English dates.
* ledger_test: add/edit/delete sale & payment, all 3 currencies, validation errors, DB constraint defense,
  §54 calculation test on day/week/month/year, weekly 2,100 TRY example, historical edit propagation,
  month & year boundaries, empty database, dashboard periods, warehouse normalization, deactivation,
  search/filter, pagination, 20,000-row performance.
* backup_test: create + restore, encrypted backup and wrong password, non-backup files, tampering,
  invalid rows, newer version, failed restore keeps data.
* security_test: PIN hash storage, lockout, format; relaunch lock; fingerprint success/failure/cancel/lockout;
  PIN fallback; no hardware; not enrolled; enrollment change; fingerprints removed; background timeout;
  immediate lock; system dialogs not locking; disabling requires PIN.
* widget_test: per-currency display without combined totals, huge amounts on narrow dark screen, empty state.

Manual on device: see README checklist (real BiometricPrompt behavior can't be unit tested).

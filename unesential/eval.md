Here is a structured audit of the vanessa3 project backend and repository.

---

## Project Overview

A Flutter mobile/web POS app (298 `.dart` files) backed by a Node.js/Express API server with a PostgreSQL database. The backend is deployed via PM2. The domain is `vanessa.id` / `mobile.vanessa.id`.

---

## 1. Backend Structure (`backend/`)

**Entry points**
- `app.js` — Express app factory: CORS logic, security headers, body parsing, request logger
- `server.js` — Route registration, rate limiters, WebSocket, cron jobs, `app.listen()`
- `db.js` — `pg.Pool` with SSL and strict-env enforcement

**Routes** (35 files, ~12,476 lines total):

| File | Lines | Domain |
|---|---|---|
| `orders_create.js` | 1,012 | Order creation |
| `items.js` | 958 | Inventory |
| `payments_core.js` | 830 | Payments |
| `orders_read.js` | 797 | Order reads |
| `dashboard_orders.js` | 777 | Dashboard |
| `workshop_orders.js` | 738 | Workshop |
| `transfers.js` | 728 | Stock transfers |
| `import_data.js` | 458 | XLSX/CSV import |

**Lib helpers** (`backend/lib/`, ~2,870 lines): `audit_log`, `idempotency_helpers`, `sql_migrations`, `google_drive_backup`, `query_limits`, `order_scope_helpers`, etc.

**Middleware**: `auth.js` (JWT), `require_login_body.js`, `request_logger.js`, `uploads_auth.js`

**WebSocket**: `attach.js`, `emit.js`, `presence_registry.js` — live session tracking + force-logout for superadmin

---

## 2. Security Findings

### Critical

**`backend/.env` contains real production credentials locally** — and more importantly, `backend/.env.example` (which _is_ tracked by git) contains what appears to be an actual JWT secret value:

```63:.env.example
JWT_SECRET=vanessa_jwt_super_secret_2025 de3d07f5785680db...c88
```

The live `.env` also contains the production DB password `Aza|ia2I{28gQbLk` and the same JWT secret. The `.gitignore` correctly excludes `/backend/.env` and `/backend/.env.*`, but `.env.example` is explicitly _not_ excluded — and it currently holds a real secret. **Anyone with repo access can sign arbitrary JWTs or connect to the production database.**

**Recommended fix**: Rotate the JWT secret and DB password immediately; replace `.env.example` line 63 with `JWT_SECRET=your-strong-secret-here`.

---

### Significant Gaps

1. **No `Content-Security-Policy` header.** `app.js` sets `X-Content-Type-Options`, `X-Frame-Options`, `Referrer-Policy`, and `Permissions-Policy` manually, but there is no `helmet` or CSP. No HSTS header is emitted either (relying on the nginx reverse-proxy to add it).

2. **`DB_SSL=false` in production `.env`.** The `db.js` startup check requires `DB_SSL=true` when `NODE_ENV=production`, but the current `.env` has both `NODE_ENV=development` and `DB_SSL=false`, which bypasses that guard entirely. If the server is actually running in production mode against `vanessa.id`, the Postgres connection is unencrypted.

3. **`ALLOW_LEGACY_PLAINTEXT_PASSWORD` flag.** The login route supports comparing passwords stored as plaintext if this env flag is set. The auto-migration to bcrypt on first login is correct, but the flag's existence is a persistent risk if inadvertently enabled.

---

### Strengths

- All SQL queries use `pg` parameterized queries (`$1`, `$2`, ...) throughout the codebase. Template literals in SQL are only used for **server-validated column names** (e.g. column names looked up from `information_schema.columns`) or for the timezone constant (`ORDER_CALENDAR_TIMEZONE`), which is validated against `/^[\w/-]+$/` in `business_timezone.js`. **No obvious SQL injection vectors.**
- JWT is verified on every authenticated route; `requireRoles()` enforces role-based access hierarchically.
- Upload endpoint (`/uploads`) requires a valid JWT (via header or `?access_token=`).
- Rate limiting is thoughtfully implemented: per-username+IP for login (only failed attempts counted), per-user-token for writes.
- The CORS logic handles `*.vanessa.id` wildcard subdomains cleanly and always allows localhost for dev.
- `X-Idempotency-Key` support prevents duplicate payments/orders on retry.
- The audit log (`audit_log` table) records `action`, `entity_type`, `entity_id`, `payload`, and `ip_address` with best-effort writes.

---

## 3. Test Coverage

### Backend (Node.js) — 15 test files in `unesential/test/`

| File | What it covers |
|---|---|
| `login.routes.smoke.test.js` | 401 on unknown user, 401/400 on switch-context |
| `orders_core.smoke.test.js` | Validation errors (400) on orders, pickup, store-op |
| `payments_core.smoke.test.js` | Payment route smoke |
| `items_routes.smoke.test.js` | Items route smoke |
| `branches_transfers.smoke.test.js` | Transfers smoke |
| `security-headers.test.js` | `Permissions-Policy` header check |
| `audit_log.test.js` | Audit log write |
| `sql_migrations.test.js` | Migration runner logic |
| `query_limits.test.js` | `parseQueryLimit` unit test |
| `request_logger.test.js` | Logger unit test |
| `health.routes.test.js` | Health endpoint |
| `orders_daily_handler.test.js` | Daily handler unit test |
| + 3 more smoke tests | login_body, items_stock_opname, store_operational |

Tests run via `node --test` (Node.js built-in runner) + `supertest`. CI script is at `unesential/scripts/ci.sh`.

**Weaknesses in test coverage:**
- All backend tests use **mock DB objects** — no integration tests against a real PostgreSQL instance.
- The `import_data.js` route (XLSX/CSV bulk import, 458 lines) has no test file.
- `reports.js`, `users.js`, `employees.js`, `admin_api.js`, `suppliers.js` are not tested.
- The 15-file WebSocket layer has no tests.

### Flutter — 1 test file (`test/user_state_workshop_session_test.dart`)

Tests only `UserState.workshopSessionBlockReason` for three edge cases. For a 298-file Flutter app, test coverage is essentially zero. There are no widget tests, integration tests, or golden tests.

---

## 4. Technical Debt (Git + Code)

**Commit message convention** — All recent commits use timestamp-in-message style (`optimize 090626:23.04`, `2216:22052026`, etc.) with no semantic meaning. This makes git history unusable for bisecting bugs or understanding changes.

**Massive recent refactor** — The commit `optimize2` (Jun 5) moved a single 2,703-line `workshop.js` file into 11 separate files. This is good decomposition but the original monolith suggests the workshop feature was never properly structured.

**Unstamped migration files** — 7 migration files in `backend/migrations/` lack date-prefix naming (`add_kode_produk_to_order_items.sql`, `fix_order_items_foreign_key.sql`, etc.). The migration runner sorts by filename, so these will always run before any `2026*` files, which could be unpredictable on fresh databases.

**`server.js` has stale comment stubs** — Lines 1–4 are `// ...existing code...` placeholder comments from a code editor suggestion that were never removed.

**Two parallel ecosystem configs** — Both `ecosystem.config.cjs` (for the repo structure) and `ecosystem.flat.config.cjs` (for a "flat" deploy layout without the `backend/` subfolder) exist. This implies two different server deployment topologies, which is an operational complexity risk.

**Active Android Kotlin migration (in-progress git diff)** — The two unstaged modified files (`android/app/build.gradle.kts`, `android/gradle.properties`) reflect an in-progress migration from the legacy Kotlin Gradle plugin to built-in Kotlin. `android.builtInKotlin` is being flipped to `true` and `kotlinOptions` replaced with the new `kotlin { compilerOptions }` DSL. This is correct for Kotlin 2.x but is uncommitted.

---

## 5. Dependencies & Deployment

**Runtime dependencies** (all in `package.json` at repo root):
- `express` ^5.2.1 — Express 5 (RC, not fully stable; some middleware compatibility issues exist)
- `jsonwebtoken` ^9.0.3, `bcryptjs` ^3.0.3 — standard
- `pg` ^8.16.3 — PostgreSQL driver
- `multer` ^2.0.2 — file uploads
- `googleapis` ^160.0.0 — Google Drive backup
- `xlsx` ^0.18.5 — bulk import (**note: `xlsx`/SheetJS has a known [ReDoS vulnerability](https://github.com/advisories/GHSA-4r6h-8v6p-xvh6) in older versions; check for advisories**)
- `ws` ^8.18.3 — WebSocket
- `node-cron` ^4.2.1 — scheduled jobs
- `pdfkit` ^0.17.2 — PDF generation

**No `package-lock.json` in `backend/`** — dependencies are resolved from the root `package-lock.json`. This is workable but non-standard.

**Deployment pipeline:**
- PM2 via `ecosystem.config.cjs`, single instance, `max_memory_restart: 512M`
- Deploy script: `unesential/scripts/restart-backend-production.sh` — runs `npm install --omit=dev`, preflight DB ping, SQL migrations, `pm2 startOrRestart`, health check
- CI: `unesential/scripts/ci.sh` — `npm ci`, tests, ESLint, `node --check` on key files, optional `flutter analyze`
- No GitHub Actions workflow file found in the repo (CI script exists but is not wired to any CI platform automatically)
- SQL migrations at `backend/migrations/` (54 files), tracked in a `sql_migrations` DB table, run inside transactions with rollback on failure

---

## Summary Table

| Area | Rating | Key Issue |
|---|---|---|
| SQL injection risk | **Low** | Parameterized queries everywhere; column name injection protected by allowlist/regex |
| Auth / JWT | **Good** | bcrypt, role-check middleware, rate limiting, token-based upload auth |
| Secrets handling | **Critical gap** | Real JWT secret committed in `.env.example` |
| DB encryption (SSL) | **Risk** | `DB_SSL=false` in `.env`, allowing unencrypted Postgres connections |
| Security headers | **Partial** | Missing CSP, no HSTS |
| Backend test coverage | **Moderate** | 15 smoke/unit tests but mock-only, several major routes untested |
| Flutter test coverage | **Very low** | 1 test file for the entire app |
| Deployment automation | **Good** | PM2 + migration script + health check; CI script exists |
| Commit hygiene | **Poor** | Timestamp-only messages, no conventional commit format |
| Code structure | **Improving** | Recent refactor of workshop monolith; still some very large files (1000+ lines) |

---

## TODO List (dari review fungsi, alur, repo)

Prioritas: **P0** segera · **P1** minggu ini · **P2** sprint berikutnya · **P3** backlog

### P0 — Keamanan & produksi

- [ ] **Rotate JWT secret** di production — jalankan di server: `node backend/scripts/generate-jwt-secret.js` → update `.env` → `pm2 restart vanessa --update-env`
- [x] **Bersihkan `backend/.env.example`**: secret nyata dihapus, satu blok template
- [ ] **Rotate password DB** production jika secret pernah ter-commit / ter-share (manual di Postgres)
- [x] **Preflight production**: cek JWT kuat, `DB_SSL`, blok `ALLOW_LEGACY_PLAINTEXT_PASSWORD` — `backend/scripts/preflight.js`
- [ ] **Deploy backend** — di server: ikuti `unesential/scripts/P0_DEPLOY_SERVER.md`
- [x] **Migrasi Android built-in Kotlin** — `android/app/build.gradle.kts`, `gradle.properties`

### P1 — Paritas web & alur operasional

- [x] **Upload bukti keuangan toko di web**: `keuangan_toko_page.dart` → `CsOrderPhotoPicker` + `CsOrderPhotoUpload`
- [x] **Seragamkan foto upload** di `store_operational_entry_sheet.dart`, `store_operational_entry_form.dart` (`service_page` sudah pakai CsOrderPhotoPicker)
- [ ] **Deploy web build** terbaru (kamera kasir + kompresi 800×800 JPEG 90%)
- [ ] **Uji end-to-end web**: login → kasir bayar QRIS/transfer → upload bukti → sukses
- [ ] **UX saat fitur web tidak tersedia**: pesan jelas (bukan silent fail), mis. cetak TSPL Bluetooth

### P1 — Observabilitas & error handling

- [ ] **Aktifkan Sentry** di build production (`--dart-define=SENTRY_DSN=...`)
- [ ] **Satukan HTTP client Flutter**: deprecate jalur ganda `ApiService` vs `ApiClient`; satu hierarki exception
- [x] **Tambah retry** di `ApiClient` untuk timeout/transient error (selaras `ApiService`)

### P2 — Arsitektur & maintainability

- [x] **Pecah `app_routes.dart`**: `LoginPage` → `features/auth/presentation/`; hapus prototype mati (~680 baris); `role_home_route.dart`
- [ ] **Migrasi Riverpod**: `StateNotifierProvider` + manual `AsyncValue` → `AsyncNotifierProvider` / `FutureProvider` + `ref.invalidate()`
- [ ] **Pecah route backend besar**: `orders_create.js`, `items.js`, `payments_core.js` (ikuti pola refactor workshop)
- [x] **Hapus stub comment** di `server.js` baris 1–4
- [ ] **Rename migrasi SQL** tanpa date-prefix (`add_kode_produk_...`, dll.) atau dokumentasikan urutan eksplisit
- [ ] **Satu sumber deploy PM2**: pilih `ecosystem.config.cjs` atau `ecosystem.flat.config.cjs`, dokumentasikan di README deploy

### P2 — Testing

- [x] **Flutter**: test `homeRouteForRole` (redirect per role)
- [ ] **Flutter**: test `CsOrderPhotoPicker` kompresi web/Android
- [ ] **Flutter**: test offline queue enqueue + sync drop 4xx / retry 5xx
- [ ] **Backend**: smoke test `import_data.js`, `users.js`, `reports.js`
- [ ] **Backend**: integration test Postgres (minimal login + create order) di CI
- [ ] **WebSocket**: unit/smoke test presence + `force_logout`
- [x] **Wire CI**: `.github/workflows/ci.yml` → `unesential/scripts/ci.sh` + flutter test

### P2 — Keamanan lanjutan

- [x] **Tambah CSP + HSTS** di `app.js` (HSTS production only)
- [ ] **Audit dependency** `xlsx` (ReDoS advisory) — upgrade atau batasi ukuran/tipe file import
- [ ] **Review Express 5** compatibility middleware yang dipakai

### P3 — Produk & platform

- [ ] **Abstraksi cetak label**: interface `LabelPrinter` — TSPL (Android) vs browser print (web)
- [ ] **Kalibrasi gap label Yupo** (`kYupoLabelGapMm`) setelah uji fisik XP-TT426B
- [ ] **Uji Bluetooth TSPL** di Xiaomi (izin + pairing + cetak batch)
- [ ] **Offline queue UX**: handling antrian penuh (100 item), notifikasi item gagal permanen (4xx)
- [ ] **Konvensi commit message** semantik (`fix:`, `feat:`, `chore:`) — dokumentasikan di CONTRIBUTING
- [ ] **Plugin Flutter**: pantau update built-in Kotlin untuk `mobile_scanner`, `sentry_flutter`, `share_plus`, dll.
- [ ] **Clean architecture bertahap**: pola `features/auth/` ke modul prioritas (orders, payments)

### Sudah selesai (referensi)

- [x] Kompresi foto web = Android (800×800, JPEG 90%) — `cs_order_photo_picker.dart`
- [x] Kamera bukti pembayaran kasir web — `payment_page.dart`, `web/index.html`
- [x] Warning KGP level app — migrasi built-in Kotlin di `android/app/build.gradle.kts`
- [x] Backend rate limit login 429 — `server.js`, `app.js` (perlu deploy)
- [x] Bersihkan log debug AGENT_NDJSON
- [x] Backend npm test 37/37 lulus
- [x] Fix WebSocket disconnect web (close code 1000)
- [x] Deploy script layout flat nodeapp + migrasi payments idempotent
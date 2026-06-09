# P0 Deploy & Rotasi Secret — Server Production

**Target server:** `mobile.vanessa.id`  
**Path:** `/home/vanessa/web/mobile.vanessa.id/private/nodeapp`

## Layout deploy — pilih yang cocok

Cek di server:

```bash
cd /home/vanessa/web/mobile.vanessa.id/private/nodeapp
ls -la ecosystem.config.cjs scripts/preflight.js backend/ecosystem.config.cjs 2>/dev/null
```

| Yang ada | Layout | Perintah deploy |
|----------|--------|-----------------|
| `ecosystem.config.cjs` + `scripts/preflight.js` di **nodeapp/** | **FLAT** (umum di production) | `bash scripts/restart-production.sh` |
| `backend/ecosystem.config.cjs` | **REPO** (git clone penuh) | `bash unesential/scripts/p0-production-security.sh` |

### Error umum (layout flat)

```
npm error Missing script: "migrate:sql"
[PM2][ERROR] File backend/ecosystem.config.cjs not found
```

**Penyebab:** Skrip repo memakai `backend/` dan `npm run migrate:sql`, tapi server flat tidak punya subfolder `backend/`.

**Perbaikan cepat (flat):**

```bash
cd /home/vanessa/web/mobile.vanessa.id/private/nodeapp
export NODE_ENV=production
node scripts/preflight.js --ping-db
node scripts/migrate-sql.js          # bukan npm run migrate:sql
pm2 startOrRestart ecosystem.config.cjs --update-env
pm2 save
```

Jika `scripts/migrate-sql.js` belum ada — salin dari repo setelah `git pull`, atau:

```bash
# setelah pull repo ke folder lain, copy file baru:
cp /path/to/repo/backend/scripts/migrate-sql.js scripts/
```

Jika `ecosystem.config.cjs` belum ada:

```bash
cp ecosystem.flat.config.cjs ecosystem.config.cjs   # dari repo backend/
```

---

## 0. SSH ke server

```bash
ssh vanessa@vanessa.id
# atau host yang biasa Anda pakai
```

---

## 1. Pull / sync kode terbaru

**Repo penuh:**

```bash
cd /home/vanessa/web/mobile.vanessa.id/private/nodeapp
git pull origin main
```

**Flat (tanpa git):** upload/rsync isi `backend/` dari laptop ke `nodeapp/`, termasuk `scripts/migrate-sql.js` dan `scripts/restart-production.sh`.

---

## 2. Rotasi JWT secret (wajib jika secret lama pernah di git)

**Flat:**

```bash
cd /home/vanessa/web/mobile.vanessa.id/private/nodeapp
node scripts/generate-jwt-secret.js
nano .env
```

**Repo:**

```bash
node backend/scripts/generate-jwt-secret.js
nano backend/.env
```

Salin output `JWT_SECRET=...` (jangan commit, jangan paste di chat publik).

Pastikan baris-baris ini benar:

```env
NODE_ENV=production
STRICT_DB_ENV=true
DB_SSL=true
TRUST_PROXY=true
JWT_SECRET=<paste secret baru dari generate-jwt-secret.js>
JWT_EXPIRES_IN=8h

# JANGAN aktifkan di production:
# ALLOW_LEGACY_PLAINTEXT_PASSWORD=false
```

Simpan (`Ctrl+O`, `Enter`, `Ctrl+X`).

> **Efek:** Semua user harus **login ulang** setelah PM2 restart.

---

## 3. (Opsional) Rotasi password database

Jika `DB_PASSWORD` pernah bocor:

1. Ubah password user Postgres di server DB (`vanessa.id` / host di `.env`).
2. Update `DB_PASSWORD=...` di `backend/.env`.
3. Tes koneksi (langkah 4) sebelum restart PM2.

---

## 4. Preflight production (cek env + DB)

```bash
cd /home/vanessa/web/mobile.vanessa.id/private/nodeapp
export NODE_ENV=production
node scripts/preflight.js --ping-db
# repo: node backend/scripts/preflight.js --ping-db
```

Harus muncul `[preflight] Siap start backend.`

**Jika gagal:**

| Error | Tindakan |
|-------|----------|
| `JWT_SECRET masih placeholder` | Langkah 2 belum selesai |
| `vanessa_jwt_super_secret` | Secret lama masih dipakai — ganti dengan yang baru |
| `DB_SSL=true` | Set `DB_SSL=true` di `backend/.env` |
| `ALLOW_LEGACY_PLAINTEXT_PASSWORD` | Hapus baris atau set `false` |
| Database tidak bisa dihubungi | Cek `DB_HOST`, `DB_PASSWORD`, firewall Postgres |

---

## 5. Deploy backend (install + migrate + PM2)

**Flat (production — gunakan ini jika error `backend/ecosystem.config.cjs not found`):**

```bash
cd /home/vanessa/web/mobile.vanessa.id/private/nodeapp
bash scripts/restart-production.sh
```

**Repo penuh:**

```bash
bash unesential/scripts/p0-production-security.sh
```

**Manual flat:**

```bash
cd /home/vanessa/web/mobile.vanessa.id/private/nodeapp
export NODE_ENV=production
node scripts/preflight.js --ping-db
node scripts/migrate-sql.js
pm2 startOrRestart ecosystem.config.cjs --update-env
pm2 save
```

---

## 6. Verifikasi dari server

```bash
# Lokal (port dari backend/.env, biasanya 3000)
curl -sf http://127.0.0.1:3000/health/live

# Publik
curl -sf https://mobile.vanessa.id/health/live

# Login smoke (ganti user/password asli)
curl -s -X POST https://mobile.vanessa.id/login \
  -H 'Content-Type: application/json' \
  -d '{"username":"super","password":"YOUR_PASSWORD"}' | head -c 200
echo
```

Cek log jika gagal:

```bash
pm2 logs vanessa --lines 50
pm2 status
```

---

## 7. Dari laptop (setelah deploy)

```bash
# Push commit ke remote dulu (jika belum), lalu di server git pull
git push origin main   # jalankan di laptop
```

Uji app Flutter/web: login → pastikan tidak 429 berlebihan saat banyak user.

---

## Troubleshooting cepat

| Gejala | Perintah |
|--------|----------|
| 502 Bad Gateway | `pm2 logs vanessa` — biasanya preflight gagal atau crash startup |
| Login Failed to fetch | `bash backend/scripts/fix_production_login.sh` (hati-hati: reset password super default) |
| 429 Too Many Requests | Pastikan `TRUST_PROXY=true` + nginx forward `X-Forwarded-For` |
| Semua user logout tiba-tiba | Normal setelah rotasi `JWT_SECRET` |

---

## Layout repo (subfolder backend/)

Jika `backend/ecosystem.config.cjs` ada:

```bash
npm run migrate:sql
pm2 startOrRestart backend/ecosystem.config.cjs --update-env
```

`.env` di `backend/.env`.

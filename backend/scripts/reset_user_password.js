#!/usr/bin/env node
'use strict';

/**
 * Reset password user (bcrypt $2b$) — lokal atau produksi.
 *
 * Usage (dari folder backend):
 *   RESET_USERNAME=super RESET_PASSWORD='123456' node scripts/reset_user_password.js
 *
 * (Jangan pakai USERNAME= di macOS — bentrok dengan env sistem.)
 *
 * Produksi: pastikan backend/.env mengarah ke DB vanessa_store, lalu jalankan perintah yang sama.
 */

const path = require('path');
require('dotenv').config({ path: path.join(__dirname, '..', '.env') });

const bcrypt = require('bcryptjs');
const db = require('../db');

async function main() {
  const username = (process.env.RESET_USERNAME ?? process.env.LOGIN_USERNAME ?? '')
    .toString()
    .trim();
  const password = (process.env.RESET_PASSWORD ?? process.env.LOGIN_PASSWORD ?? '')
    .toString();

  if (!username || !password) {
    console.error('Set RESET_USERNAME dan RESET_PASSWORD, contoh:');
    console.error(
      "  RESET_USERNAME=super RESET_PASSWORD='123456' node scripts/reset_user_password.js"
    );
    process.exitCode = 1;
    return;
  }

  const hash = await bcrypt.hash(password, 10);
  const r = await db.query(
    `
      UPDATE users
      SET password_hash = $1, updated_at = NOW(), status = 'active'
      WHERE lower(trim(username)) = lower(trim($2))
      RETURNING user_id, username
    `,
    [hash, username]
  );

  if (r.rows.length === 0) {
    console.error(`User "${username}" tidak ditemukan di DB ${process.env.DB_NAME || '?'}.`);
    process.exitCode = 1;
    return;
  }

  console.log('Password di-reset.');
  console.log(`  DB     : ${process.env.DB_HOST}:${process.env.DB_PORT}/${process.env.DB_NAME}`);
  console.log(`  User   : ${r.rows[0].username} (id ${r.rows[0].user_id})`);
  console.log(`  Login  : username="${username}" password=(yang Anda set di PASSWORD)`);
}

main()
  .catch((e) => {
    console.error('Gagal:', e.message);
    process.exitCode = 1;
  })
  .finally(() => process.exit());

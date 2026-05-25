'use strict';

const { execFile } = require('child_process');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { promisify } = require('util');

const execFileAsync = promisify(execFile);

/**
 * Buat dump PostgreSQL ke file sementara (plain SQL).
 * @returns {Promise<{ filePath: string, fileName: string, cleanup: () => void }>}
 */
async function createPgDumpTempFile() {
  const host = process.env.DB_HOST || 'localhost';
  const port = String(process.env.DB_PORT || '5432');
  const name = process.env.DB_NAME || 'vanessa_store';
  const user = process.env.DB_USER || 'postgres';
  const password = process.env.DB_PASSWORD || '';

  const stamp = new Date().toISOString().replace(/[-:]/g, '').slice(0, 15).replace('T', '_');
  const fileName = `vanessa_store_${stamp}.sql`;
  const filePath = path.join(os.tmpdir(), fileName);

  const env = { ...process.env, PGPASSWORD: password };
  await execFileAsync(
    'pg_dump',
    [
      `--host=${host}`,
      `--port=${port}`,
      `--username=${user}`,
      `--dbname=${name}`,
      '--format=plain',
      '--encoding=UTF8',
      '--no-owner',
      '--no-acl',
      '--clean',
      '--if-exists',
      `--file=${filePath}`,
    ],
    { env, maxBuffer: 64 * 1024 * 1024 },
  );

  if (!fs.existsSync(filePath)) {
    throw new Error('pg_dump tidak menghasilkan file');
  }

  return {
    filePath,
    fileName,
    cleanup: () => {
      try {
        fs.unlinkSync(filePath);
      } catch (_) {
        /* ignore */
      }
    },
  };
}

module.exports = { createPgDumpTempFile };

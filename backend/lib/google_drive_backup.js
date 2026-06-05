'use strict';

const fs = require('fs');
const { createPgDumpTempFile } = require('./db_pg_dump');

function loadGoogleApis() {
  try {
    return require('googleapis');
  } catch (_) {
    const err = new Error(
      'Paket googleapis belum terpasang di server. Jalankan: npm install (di folder project), lalu restart API.',
    );
    err.code = 'MODULE_NOT_FOUND';
    throw err;
  }
}

function loadServiceAccountCredentials() {
  const inline = (process.env.GOOGLE_DRIVE_SERVICE_ACCOUNT_JSON ?? '').trim();
  if (inline) {
    try {
      return JSON.parse(inline);
    } catch (_) {
      return null;
    }
  }
  const credPath = (process.env.GOOGLE_DRIVE_SERVICE_ACCOUNT_PATH ?? '').trim();
  if (!credPath || !fs.existsSync(credPath)) {
    return null;
  }
  try {
    const stat = fs.statSync(credPath);
    if (stat.isDirectory()) {
      console.warn(
        '[google_drive_backup] GOOGLE_DRIVE_SERVICE_ACCOUNT_PATH menunjuk ke folder, bukan file JSON:',
        credPath,
      );
      return null;
    }
    return JSON.parse(fs.readFileSync(credPath, 'utf8'));
  } catch (err) {
    console.warn('[google_drive_backup] Gagal baca kredensial:', err.message);
    return null;
  }
}

function getGoogleDriveBackupStatus() {
  const folderId = (process.env.GOOGLE_DRIVE_FOLDER_ID ?? '').trim();
  const creds = loadServiceAccountCredentials();
  const clientEmail =
    creds && creds.client_email ? String(creds.client_email) : '';
  let googleapisInstalled = true;
  try {
    require.resolve('googleapis');
  } catch (_) {
    googleapisInstalled = false;
  }
  return {
    configured: Boolean(folderId && creds && googleapisInstalled),
    folder_id_set: Boolean(folderId),
    service_account_set: Boolean(creds),
    googleapis_installed: googleapisInstalled,
    service_account_email: clientEmail || null,
  };
}

async function uploadFileToGoogleDrive(filePath, fileName) {
  const { google } = loadGoogleApis();
  const folderId = (process.env.GOOGLE_DRIVE_FOLDER_ID ?? '').trim();
  const credentials = loadServiceAccountCredentials();
  if (!folderId || !credentials) {
    const err = new Error(
      'Google Drive belum dikonfigurasi. Set GOOGLE_DRIVE_FOLDER_ID dan kredensial service account di .env server.',
    );
    err.code = 'NOT_CONFIGURED';
    throw err;
  }

  const auth = new google.auth.GoogleAuth({
    credentials,
    scopes: ['https://www.googleapis.com/auth/drive.file'],
  });
  const drive = google.drive({ version: 'v3', auth });

  const stat = fs.statSync(filePath);
  const res = await drive.files.create({
    requestBody: {
      name: fileName,
      parents: [folderId],
      description: 'Vanessa3 database backup (pg_dump)',
    },
    media: {
      mimeType: 'application/sql',
      body: fs.createReadStream(filePath),
    },
    fields: 'id, name, webViewLink, size, createdTime',
    supportsAllDrives: true,
  });

  const data = res.data || {};
  return {
    file_id: data.id || '',
    file_name: data.name || fileName,
    web_view_link: data.webViewLink || null,
    size_bytes: Number(data.size || stat.size || 0),
    created_time: data.createdTime || null,
  };
}

async function runDatabaseBackupToGoogleDrive() {
  const status = getGoogleDriveBackupStatus();
  if (!status.googleapis_installed) {
    const err = new Error(
      'Paket googleapis belum terpasang di server. Jalankan npm install lalu restart API.',
    );
    err.code = 'MODULE_NOT_FOUND';
    throw err;
  }
  if (!status.configured) {
    const err = new Error(
      'Google Drive belum dikonfigurasi di server. Hubungi administrator sistem.',
    );
    err.code = 'NOT_CONFIGURED';
    throw err;
  }

  const dump = await createPgDumpTempFile();
  try {
    const uploaded = await uploadFileToGoogleDrive(dump.filePath, dump.fileName);
    return {
      ok: true,
      ...uploaded,
      database: process.env.DB_NAME || 'vanessa_store',
    };
  } finally {
    dump.cleanup();
  }
}

module.exports = {
  getGoogleDriveBackupStatus,
  runDatabaseBackupToGoogleDrive,
};

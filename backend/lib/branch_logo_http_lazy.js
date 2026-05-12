'use strict';

/**
 * Lazy-load `branch_logo_http.js` agar deploy yang lupa menyalin file itu
 * tidak membuat seluruh API (termasuk /login) gagal start.
 *
 * Tanpa file asli: GET /branches/:id/logo & /api/branches/:id/logo → 404.
 */

function stubHandleBranchLogoGet(req, res) {
  if (!res.headersSent) res.status(404).end();
}

let _impl = null;

function handleBranchLogoGet(req, res, db) {
  if (_impl === null) {
    try {
      _impl = require('./branch_logo_http').handleBranchLogoGet;
    } catch (e) {
      const code = e && e.code;
      if (code !== 'MODULE_NOT_FOUND' && code !== 'ENOENT') throw e;
      console.warn(
        '[vanessa] backend/lib/branch_logo_http.js tidak ditemukan — streaming logo cabang dinonaktifkan. ' +
          'Salin file tersebut ke server lalu restart agar faktur bisa pakai proxy logo.',
      );
      _impl = stubHandleBranchLogoGet;
    }
  }
  return _impl(req, res, db);
}

module.exports = { handleBranchLogoGet };

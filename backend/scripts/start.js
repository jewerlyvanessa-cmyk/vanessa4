#!/usr/bin/env node
'use strict';

/**
 * Entry PM2: preflight env + muat server.
 * Hindari backend mati tanpa log jelas (502 nginx).
 */
const { runPreflightSync } = require('./preflight');

try {
  runPreflightSync();
} catch (err) {
  console.error('[start] Backend tidak dijalankan:', err.message || err);
  process.exit(1);
}

require('../server.js');

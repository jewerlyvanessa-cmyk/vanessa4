#!/usr/bin/env node
'use strict';

/**
 * Generate a cryptographically strong JWT_SECRET for .env (never commit the output).
 *
 * Usage:
 *   node backend/scripts/generate-jwt-secret.js
 *   node backend/scripts/generate-jwt-secret.js --write   # append hint to stdout only
 */
const crypto = require('crypto');

const secret = crypto.randomBytes(64).toString('hex');

console.log('# Paste into backend/.env on the server (not into git):');
console.log(`JWT_SECRET=${secret}`);
console.log('');
console.log('# Then restart: pm2 restart vanessa --update-env');
console.log('# All users must log in again after rotation.');

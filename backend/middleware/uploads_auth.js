'use strict';

const jwt = require('jsonwebtoken');

/**
 * JWT gate for static `/uploads` — accepts Authorization header or `?access_token=`.
 */
function createUploadsAuthMiddleware(secretKey) {
  return (req, res, next) => {
    const authHeader = req.headers.authorization || '';
    let token = authHeader.startsWith('Bearer ')
      ? authHeader.slice(7).trim()
      : null;
    if (!token && req.query.access_token) {
      token = String(req.query.access_token).trim();
    }
    if (!token) {
      return res.status(401).json({ error: 'Unauthorized' });
    }
    try {
      jwt.verify(token, secretKey);
      return next();
    } catch (_) {
      return res.status(401).json({ error: 'Invalid or expired token' });
    }
  };
}

module.exports = { createUploadsAuthMiddleware };

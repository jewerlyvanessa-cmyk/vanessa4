'use strict';

/**
 * Validasi awal POST /login — dipakai server dan smoke test agar kontrak tetap sama.
 */
function requireLoginBody(req, res, next) {
  const { username, password } = req.body || {};
  if (!username || !password) {
    return res.status(400).json({ error: 'username and password are required' });
  }
  next();
}

module.exports = { requireLoginBody };

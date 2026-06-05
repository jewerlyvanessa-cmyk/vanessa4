'use strict';

const SENSITIVE_PATHS = ['/login', '/api/auth'];

function shouldLogBody(path) {
  return !SENSITIVE_PATHS.some((p) => path.startsWith(p));
}

/**
 * Structured request logging (JSON line) untuk observability dasar.
 * Aktif bila REQUEST_LOG=true atau NODE_ENV=production.
 */
function createRequestLogger(options = {}) {
  const enabled =
    options.enabled ??
    (process.env.REQUEST_LOG === 'true' ||
      process.env.NODE_ENV === 'production');

  return function requestLogger(req, res, next) {
    if (!enabled) return next();

    const start = process.hrtime.bigint();
    const path = req.originalUrl || req.url || '';

    res.on('finish', () => {
      const durationMs = Number(process.hrtime.bigint() - start) / 1e6;
      const entry = {
        ts: new Date().toISOString(),
        method: req.method,
        path: path.split('?')[0],
        status: res.statusCode,
        durationMs: Math.round(durationMs * 10) / 10,
        userId: req.user?.user_id ?? req.user?.id ?? null,
      };
      if (res.statusCode >= 400) {
        entry.level = 'warn';
      }
      console.log(JSON.stringify(entry));
    });

    if (shouldLogBody(path) && req.method !== 'GET' && req.body) {
      req._loggedBodyKeys = Object.keys(req.body);
    }

    next();
  };
}

module.exports = { createRequestLogger };

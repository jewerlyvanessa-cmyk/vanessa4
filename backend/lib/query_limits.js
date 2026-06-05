'use strict';

/**
 * Parse `limit` query param with default and hard cap.
 * @param {unknown} raw
 * @param {{ defaultLimit?: number, maxLimit?: number }} [opts]
 */
function parseQueryLimit(raw, opts = {}) {
  const defaultLimit = opts.defaultLimit ?? 500;
  const maxLimit = opts.maxLimit ?? 2000;
  if (raw == null || String(raw).trim() === '') {
    return defaultLimit;
  }
  const n = parseInt(String(raw).trim(), 10);
  if (!Number.isFinite(n) || n <= 0) {
    return defaultLimit;
  }
  return Math.min(n, maxLimit);
}

module.exports = { parseQueryLimit };

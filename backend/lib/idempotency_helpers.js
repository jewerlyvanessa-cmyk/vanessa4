/**
 * Simpan / replay respons API berdasarkan X-Idempotency-Key.
 */

let _tableReady = false;

async function ensureIdempotencyTable(db) {
  if (_tableReady) return true;
  try {
    await db.query(`
      CREATE TABLE IF NOT EXISTS api_idempotency (
        idempotency_key TEXT PRIMARY KEY,
        method TEXT NOT NULL DEFAULT 'POST',
        path TEXT NOT NULL,
        status_code INTEGER NOT NULL,
        response_body JSONB NOT NULL,
        created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
      )
    `);
    _tableReady = true;
    return true;
  } catch (e) {
    console.warn('[idempotency] table unavailable:', e.message);
    return false;
  }
}

function readIdempotencyKey(req) {
  return (req.get('X-Idempotency-Key') || req.headers['x-idempotency-key'] || '')
    .toString()
    .trim();
}

/**
 * @returns {Promise<{ status_code: number, response_body: object } | null>}
 */
async function findIdempotentResponse(db, key) {
  if (!key) return null;
  const ok = await ensureIdempotencyTable(db);
  if (!ok) return null;
  const res = await db.query(
    `SELECT status_code, response_body FROM api_idempotency WHERE idempotency_key = $1`,
    [key],
  );
  if (res.rows.length === 0) return null;
  const row = res.rows[0];
  let body = row.response_body;
  if (typeof body === 'string') {
    try {
      body = JSON.parse(body);
    } catch (_) {
      body = { raw: body };
    }
  }
  return {
    status_code: parseInt(row.status_code, 10) || 200,
    response_body: body && typeof body === 'object' ? body : {},
  };
}

async function storeIdempotentResponse(db, req, path, statusCode, responseBody) {
  const key = readIdempotencyKey(req);
  if (!key) return;
  const ok = await ensureIdempotencyTable(db);
  if (!ok) return;
  const method = (req.method || 'POST').toUpperCase();
  const body =
    responseBody != null && typeof responseBody === 'object'
      ? responseBody
      : { value: responseBody };
  try {
    await db.query(
      `
        INSERT INTO api_idempotency (idempotency_key, method, path, status_code, response_body)
        VALUES ($1, $2, $3, $4, $5::jsonb)
        ON CONFLICT (idempotency_key) DO NOTHING
      `,
      [key, method, path, statusCode, JSON.stringify(body)],
    );
  } catch (e) {
    console.warn('[idempotency] store failed:', e.message);
  }
}

/**
 * Jika key sudah ada, kirim respons tersimpan dan return true.
 */
async function replayIdempotentIfExists(db, req, res, path) {
  const key = readIdempotencyKey(req);
  if (!key) return false;
  const existing = await findIdempotentResponse(db, key);
  if (!existing) return false;
  return res.status(existing.status_code).json(existing.response_body);
}

module.exports = {
  readIdempotencyKey,
  findIdempotentResponse,
  storeIdempotentResponse,
  replayIdempotentIfExists,
  ensureIdempotencyTable,
};

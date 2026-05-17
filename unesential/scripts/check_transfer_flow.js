require('dotenv').config({
  path: require('path').join(__dirname, '../../backend/.env'),
  quiet: true,
});
const jwt = require('jsonwebtoken');
const db = require('../../backend/db');

const BASE_URL = process.env.CHECK_API_BASE_URL || 'http://localhost:3000';
const FROM_BRANCH_ID = parseInt(process.env.CHECK_FROM_BRANCH_ID || '1', 10);
const TO_BRANCH_ID = parseInt(process.env.CHECK_TO_BRANCH_ID || '3', 10);
const APPROVER_USER_ID = parseInt(process.env.CHECK_APPROVER_USER_ID || '1', 10);
const DEFAULT_ITEM_NAME = process.env.CHECK_ITEM_NAME || 'Cincin Polos Dewasa';
const SERVICE_ITEM_NAME =
  process.env.CHECK_SERVICE_ITEM_NAME || DEFAULT_ITEM_NAME;
const BUYBACK_ITEM_NAME =
  process.env.CHECK_BUYBACK_ITEM_NAME || DEFAULT_ITEM_NAME;
const CODES = (process.env.CHECK_CODES || 'C0002,BGES17359047')
  .split(',')
  .map((x) => x.trim())
  .filter(Boolean);

if (!process.env.JWT_SECRET) {
  throw new Error('JWT_SECRET is required in backend/.env');
}

const token = jwt.sign(
  {
    user_id: APPROVER_USER_ID,
    role: process.env.CHECK_ROLE || 'admin_toko',
    branch_id: FROM_BRANCH_ID,
  },
  process.env.JWT_SECRET,
  { expiresIn: '1h' }
);

const headers = {
  'Content-Type': 'application/json',
  Authorization: `Bearer ${token}`,
};

async function api(path, options = {}) {
  const response = await fetch(`${BASE_URL}${path}`, {
    headers,
    ...options,
  });
  const raw = await response.text();
  let parsed = raw;
  try {
    parsed = JSON.parse(raw);
  } catch (_) {}
  return { status: response.status, body: parsed };
}

async function queryItemsSnapshot() {
  const result = await db.query(
    `
      SELECT
        item_id,
        kode_produk,
        name,
        status,
        quantity,
        branch_id,
        source,
        stock_type,
        ownership,
        updated_at
      FROM items
      WHERE (
        (branch_id = $1 AND kode_produk = ANY($3::text[]))
        OR (branch_id = $2 AND kode_produk = ANY($3::text[]))
      )
      ORDER BY kode_produk, branch_id, updated_at DESC
    `,
    [FROM_BRANCH_ID, TO_BRANCH_ID, CODES]
  );
  return result.rows;
}

async function runScenario(sourceType, itemName, notesPrefix) {
  const createPayload = {
    from_branch_id: FROM_BRANCH_ID,
    to_branch_id: TO_BRANCH_ID,
    item_name: itemName,
    quantity: 1,
    source_type: sourceType,
    notes: `${notesPrefix} ${new Date().toISOString()}`,
  };
  const created = await api('/transfers', {
    method: 'POST',
    body: JSON.stringify(createPayload),
  });
  const transferId = created.body?.transfer_id;
  let completed = null;
  if (transferId) {
    completed = await api(`/transfers/${transferId}`, {
      method: 'PUT',
      body: JSON.stringify({
        status: 'completed',
        approved_by: APPROVER_USER_ID,
      }),
    });
  }
  return { createPayload, created, completed, transferId };
}

async function queryTransferRows(transferIds) {
  if (!transferIds.length) return [];
  const result = await db.query(
    `
      SELECT
        transfer_id,
        source_type,
        status,
        from_branch_id,
        to_branch_id,
        item_name,
        quantity,
        notes,
        created_at,
        updated_at
      FROM transfers
      WHERE transfer_id = ANY($1::bigint[])
      ORDER BY transfer_id
    `,
    [transferIds]
  );
  return result.rows;
}

async function queryMutationRows(transferIds) {
  if (!transferIds.length) return [];
  const result = await db.query(
    `
      SELECT
        mutation_id,
        branch_id,
        item_id,
        quantity,
        previous_stock,
        current_stock,
        notes,
        reference_id,
        reference_type,
        created_at
      FROM stock_mutations
      WHERE reference_type = 'transfer'
        AND reference_id = ANY($1::bigint[])
      ORDER BY mutation_id
    `,
    [transferIds]
  );
  return result.rows;
}

async function main() {
  const before = await queryItemsSnapshot();

  const service = await runScenario(
    'service',
    SERVICE_ITEM_NAME,
    'qa service transfer'
  );
  const buyback = await runScenario(
    'buyback',
    BUYBACK_ITEM_NAME,
    'qa buyback transfer'
  );

  const transferIds = [service.transferId, buyback.transferId]
    .filter(Boolean)
    .map((x) => Number(x));

  const [transfers, mutations, after] = await Promise.all([
    queryTransferRows(transferIds),
    queryMutationRows(transferIds),
    queryItemsSnapshot(),
  ]);

  console.log(
    JSON.stringify(
      {
        baseUrl: BASE_URL,
        fromBranchId: FROM_BRANCH_ID,
        toBranchId: TO_BRANCH_ID,
        serviceItemName: SERVICE_ITEM_NAME,
        buybackItemName: BUYBACK_ITEM_NAME,
        codes: CODES,
        service,
        buyback,
        transfers,
        mutations,
        before,
        after,
      },
      null,
      2
    )
  );
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });

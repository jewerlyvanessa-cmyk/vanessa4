'use strict';

const multer = require('multer');
const bcrypt = require('bcryptjs');

function loadXlsx() {
  try {
    return require('xlsx');
  } catch (_) {
    const err = new Error(
      'Paket xlsx belum terpasang. Jalankan: cd nodeapp && npm install xlsx --save',
    );
    err.code = 'MODULE_NOT_FOUND';
    throw err;
  }
}

const upload = multer({
  storage: multer.memoryStorage(),
  limits: { fileSize: 15 * 1024 * 1024 },
});

const IMPORT_TYPES = new Set(['customers', 'branches', 'items', 'users', 'orders']);

const ORDER_TYPES = new Set(['jual', 'buyback', 'service', 'custom']);
const ORDER_STATUSES = new Set([
  'draft', 'pending', 'confirmed', 'ready_for_payment', 'completed',
  'picked_up', 'cancelled', 'buyback', 'delivered', 'sold',
  'awaiting_warehouse', 'sent-to-workshop', 'in_workshop', 'repairing',
  'polishing', 'custom_work', 'done_workshop', 'ready_for_pickup',
]);

function normalizeRow(row) {
  const out = {};
  for (const [k, v] of Object.entries(row)) {
    const key = String(k).trim().toLowerCase();
    if (!key) continue;
    out[key] = typeof v === 'string' ? v.trim() : v;
  }
  return out;
}

function parseUploadedFile(file) {
  const XLSX = loadXlsx();
  if (!file || !file.buffer?.length) {
    throw new Error('File tidak ditemukan');
  }
  const name = (file.originalname || '').toLowerCase();
  if (name.endsWith('.csv')) {
    const text = file.buffer.toString('utf8');
    const wb = XLSX.read(text, { type: 'string' });
    const sheet = wb.Sheets[wb.SheetNames[0]];
    return XLSX.utils.sheet_to_json(sheet, { defval: '' });
  }
  const wb = XLSX.read(file.buffer, { type: 'buffer' });
  const sheet = wb.Sheets[wb.SheetNames[0]];
  return XLSX.utils.sheet_to_json(sheet, { defval: '' });
}

function cellStr(v) {
  if (v == null) return '';
  return String(v).trim();
}

function cellNum(v) {
  const s = cellStr(v);
  if (!s) return null;
  const n = Number(s);
  return Number.isFinite(n) ? n : null;
}

function cellInt(v) {
  const n = cellNum(v);
  return n == null ? null : Math.trunc(n);
}

async function customersHasColumn(db, columnName) {
  const r = await db.query(
    `SELECT 1 FROM information_schema.columns
     WHERE table_schema = 'public' AND table_name = 'customers' AND column_name = $1 LIMIT 1`,
    [columnName],
  );
  return r.rowCount > 0;
}

async function importCustomers(db, rows) {
  const hasEmail = await customersHasColumn(db, 'email');
  let inserted = 0;
  let updated = 0;
  const errors = [];

  for (let i = 0; i < rows.length; i++) {
    const r = normalizeRow(rows[i]);
    const name = cellStr(r.name);
    if (!name) {
      errors.push(`Baris ${i + 2}: name wajib`);
      continue;
    }
    const phone = cellStr(r.phone) || null;
    const email = cellStr(r.email) || null;
    const address = cellStr(r.address) || null;
    const customerId = cellInt(r.customer_id);

    try {
      if (customerId) {
        const exists = await db.query(
          'SELECT customer_id FROM customers WHERE customer_id = $1',
          [customerId],
        );
        if (exists.rowCount) {
          if (hasEmail) {
            await db.query(
              `UPDATE customers SET name = $1, phone = $2, email = $3, address = $4, updated_at = NOW()
               WHERE customer_id = $5`,
              [name, phone, email, address, customerId],
            );
          } else {
            await db.query(
              `UPDATE customers SET name = $1, phone = $2, address = $3, updated_at = NOW()
               WHERE customer_id = $4`,
              [name, phone, address, customerId],
            );
          }
          updated += 1;
          continue;
        }
      }
      if (hasEmail) {
        await db.query(
          `INSERT INTO customers (name, phone, email, address) VALUES ($1, $2, $3, $4)`,
          [name, phone, email, address],
        );
      } else {
        await db.query(
          `INSERT INTO customers (name, phone, address) VALUES ($1, $2, $3)`,
          [name, phone, address],
        );
      }
      inserted += 1;
    } catch (e) {
      errors.push(`Baris ${i + 2}: ${e.message}`);
    }
  }
  return { inserted, updated, errors };
}

async function importBranches(db, rows) {
  let inserted = 0;
  let updated = 0;
  const errors = [];

  for (let i = 0; i < rows.length; i++) {
    const r = normalizeRow(rows[i]);
    const name = cellStr(r.name);
    const code = cellStr(r.code);
    if (!name || !code) {
      errors.push(`Baris ${i + 2}: name dan code wajib`);
      continue;
    }
    const alias = cellStr(r.alias) || null;
    const initials = cellStr(r.initials) || null;
    const address = cellStr(r.address) || null;
    const phoneNumber = cellStr(r.phone_number) || null;
    const branchId = cellInt(r.branch_id);
    const branchType = cellStr(r.branch_type) || 'toko';

    try {
      if (branchId) {
        const exists = await db.query(
          'SELECT branch_id FROM branches WHERE branch_id = $1',
          [branchId],
        );
        if (exists.rowCount) {
          await db.query(
            `UPDATE branches SET name = $1, code = $2, alias = $3, initials = $4,
             address = $5, phone_number = $6, branch_type = $7, updated_at = NOW()
             WHERE branch_id = $8`,
            [name, code, alias, initials, address, phoneNumber, branchType, branchId],
          );
          updated += 1;
          continue;
        }
      }
      const byCode = await db.query(
        'SELECT branch_id FROM branches WHERE code = $1',
        [code],
      );
      if (byCode.rowCount) {
        await db.query(
          `UPDATE branches SET name = $1, alias = $2, initials = $3,
           address = $4, phone_number = $5, branch_type = $6, updated_at = NOW()
           WHERE branch_id = $7`,
          [name, alias, initials, address, phoneNumber, branchType, byCode.rows[0].branch_id],
        );
        updated += 1;
      } else {
        await db.query(
          `INSERT INTO branches (name, code, alias, initials, address, phone_number, branch_type)
           VALUES ($1, $2, $3, $4, $5, $6, $7)`,
          [name, code, alias, initials, address, phoneNumber, branchType],
        );
        inserted += 1;
      }
    } catch (e) {
      errors.push(`Baris ${i + 2}: ${e.message}`);
    }
  }
  return { inserted, updated, errors };
}

async function importItems(db, rows) {
  let inserted = 0;
  let updated = 0;
  const errors = [];

  for (let i = 0; i < rows.length; i++) {
    const r = normalizeRow(rows[i]);
    const name = cellStr(r.name);
    const branchId = cellInt(r.branch_id);
    const status = cellStr(r.status) || 'ready';
    if (!name || !branchId) {
      errors.push(`Baris ${i + 2}: name dan branch_id wajib`);
      continue;
    }
    const kodeProduk =
      cellStr(r.kode_produk) ||
      `IMP-${branchId}-${Date.now()}-${i}`;
    const weight = cellNum(r.weight);
    const material = cellStr(r.material) || null;
    const purity = cellStr(r.purity) || null;
    const itemId = cellInt(r.item_id);

    try {
      if (itemId) {
        const exists = await db.query(
          'SELECT item_id FROM items WHERE item_id = $1',
          [itemId],
        );
        if (exists.rowCount) {
          await db.query(
            `UPDATE items SET name = $1, weight = $2, material = $3, purity = $4,
             status = $5, branch_id = $6, kode_produk = $7, updated_at = NOW()
             WHERE item_id = $8`,
            [name, weight, material, purity, status, branchId, kodeProduk, itemId],
          );
          updated += 1;
          continue;
        }
      }
      await db.query(
        `INSERT INTO items (branch_id, kode_produk, name, material, purity, weight, status)
         VALUES ($1, $2, $3, $4, $5, $6, $7)`,
        [branchId, kodeProduk, name, material, purity, weight, status],
      );
      inserted += 1;
    } catch (e) {
      errors.push(`Baris ${i + 2}: ${e.message}`);
    }
  }
  return { inserted, updated, errors };
}

async function importUsers(db, rows) {
  let inserted = 0;
  let updated = 0;
  const errors = [];

  for (let i = 0; i < rows.length; i++) {
    const r = normalizeRow(rows[i]);
    const username = cellStr(r.username);
    let passwordHash = cellStr(r.password_hash);
    const status = cellStr(r.status) || 'active';
    if (!username || !passwordHash) {
      errors.push(`Baris ${i + 2}: username dan password_hash wajib`);
      continue;
    }
    if (!/^\$2[aby]\$/.test(passwordHash)) {
      passwordHash = await bcrypt.hash(passwordHash, 10);
    }
    const userId = cellInt(r.user_id);

    try {
      if (userId) {
        const exists = await db.query(
          'SELECT user_id FROM users WHERE user_id = $1',
          [userId],
        );
        if (exists.rowCount) {
          await db.query(
            `UPDATE users SET username = $1, password_hash = $2, status = $3, updated_at = NOW()
             WHERE user_id = $4`,
            [username, passwordHash, status, userId],
          );
          updated += 1;
          continue;
        }
      }
      const byName = await db.query(
        'SELECT user_id FROM users WHERE username = $1',
        [username],
      );
      if (byName.rowCount) {
        await db.query(
          `UPDATE users SET password_hash = $1, status = $2, updated_at = NOW()
           WHERE user_id = $3`,
          [passwordHash, status, byName.rows[0].user_id],
        );
        updated += 1;
      } else {
        await db.query(
          `INSERT INTO users (username, password_hash, status) VALUES ($1, $2, $3)`,
          [username, passwordHash, status],
        );
        inserted += 1;
      }
    } catch (e) {
      errors.push(`Baris ${i + 2}: ${e.message}`);
    }
  }
  return { inserted, updated, errors };
}

async function importOrders(db, rows) {
  let inserted = 0;
  let updated = 0;
  const errors = [];

  for (let i = 0; i < rows.length; i++) {
    const r = normalizeRow(rows[i]);
    const orderType = cellStr(r.order_type).toLowerCase();
    const branchId = cellInt(r.branch_id);
    const userId = cellInt(r.user_id);
    if (!orderType || !branchId || !userId) {
      errors.push(`Baris ${i + 2}: order_type, branch_id, user_id wajib`);
      continue;
    }
    if (!ORDER_TYPES.has(orderType)) {
      errors.push(`Baris ${i + 2}: order_type tidak valid (${orderType})`);
      continue;
    }
    const status = cellStr(r.status).toLowerCase() || 'draft';
    if (!ORDER_STATUSES.has(status)) {
      errors.push(`Baris ${i + 2}: status tidak valid (${status})`);
      continue;
    }
    const total = cellNum(r.total) ?? 0;
    const diskon = cellNum(r.diskon) ?? 0;
    const customerId = cellInt(r.customer_id);
    const orderNumber = cellStr(r.order_number) || null;
    const mode = cellStr(r.mode) || null;
    const orderId = cellInt(r.order_id);

    try {
      if (orderId) {
        const exists = await db.query(
          'SELECT order_id FROM orders WHERE order_id = $1',
          [orderId],
        );
        if (exists.rowCount) {
          await db.query(
            `UPDATE orders SET order_type = $1, branch_id = $2, user_id = $3, customer_id = $4,
             total = $5, diskon = $6, status = $7, order_number = $8, mode = $9, updated_at = NOW()
             WHERE order_id = $10`,
            [
              orderType, branchId, userId, customerId, total, diskon, status,
              orderNumber, mode, orderId,
            ],
          );
          updated += 1;
          continue;
        }
      }
      if (orderNumber) {
        const byNum = await db.query(
          'SELECT order_id FROM orders WHERE order_number = $1',
          [orderNumber],
        );
        if (byNum.rowCount) {
          await db.query(
            `UPDATE orders SET order_type = $1, branch_id = $2, user_id = $3, customer_id = $4,
             total = $5, diskon = $6, status = $7, mode = $8, updated_at = NOW()
             WHERE order_id = $9`,
            [
              orderType, branchId, userId, customerId, total, diskon, status,
              mode, byNum.rows[0].order_id,
            ],
          );
          updated += 1;
          continue;
        }
      }
      await db.query(
        `INSERT INTO orders (
          order_type, branch_id, user_id, customer_id, total, diskon, status, order_number, mode
        ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)`,
        [orderType, branchId, userId, customerId, total, diskon, status, orderNumber, mode],
      );
      inserted += 1;
    } catch (e) {
      errors.push(`Baris ${i + 2}: ${e.message}`);
    }
  }
  return { inserted, updated, errors };
}

const IMPORT_HANDLERS = {
  customers: importCustomers,
  branches: importBranches,
  items: importItems,
  users: importUsers,
  orders: importOrders,
};

function registerImportDataRoutes(app, deps) {
  const { db, authRequired, requireRoles } = deps;

  app.post(
    '/api/import/:dataType',
    authRequired,
    requireRoles('superadmin'),
    upload.single('file'),
    async (req, res) => {
      const dataType = String(req.params.dataType || '').toLowerCase();
      if (!IMPORT_TYPES.has(dataType)) {
        return res.status(400).json({
          success: false,
          message: `Jenis data tidak dikenal: ${dataType}`,
        });
      }
      try {
        const rawRows = parseUploadedFile(req.file);
        if (!rawRows.length) {
          return res.status(400).json({
            success: false,
            message: 'File kosong atau tidak ada baris data',
          });
        }
        const handler = IMPORT_HANDLERS[dataType];
        const result = await handler(db, rawRows);
        return res.status(200).json({
          success: true,
          inserted: result.inserted,
          updated: result.updated,
          errors: result.errors,
        });
      } catch (error) {
        console.error(`[import/${dataType}]`, error);
        const status = error.code === 'MODULE_NOT_FOUND' ? 503 : 500;
        return res.status(status).json({
          success: false,
          message: error.message || 'Gagal mengimport data',
        });
      }
    },
  );
}

module.exports = { registerImportDataRoutes };

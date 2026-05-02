// ...existing code...

// ...existing code...

// PATCH endpoints dipindahkan ke bawah setelah app dan middleware

const { app, port, SECRET_KEY, JWT_EXPIRES_IN } = require('./app');
const express = require('express');
const WebSocket = require('ws');
const PDFDocument = require('pdfkit');
const fs = require('fs');
const multer = require('multer');
const path = require('path');
const cron = require('node-cron');
const jwt = require('jsonwebtoken');
const bcrypt = require('bcryptjs');
const rateLimit = require('express-rate-limit');
const db = require('./db');
const { authenticateToken, requireRoles } = require('./middleware/auth');
const { emitNotification } = require('./websocket/emit');
const { local: localStorage } = require('./storage/storage.service');
const customersRoute = require('./routes/customers'); // Import customers route
const apiRoutes = require('./api'); // Import new API routes
const dashboardOrdersRoute = require('./routes/dashboard_orders'); // Import dashboard orders route
const branchesRoute = require('./routes/branches'); // Import branches route
const userInfoRoute = require('./routes/userInfo');

/**
 * Stockist clients send item_name as a display label "KODE - Nama" while
 * `items.name` in DB is usually just "Nama" (kode is in kode_produk). Extract
 * the code so we can match the source row when the label !== items.name.
 */
function parseKodeProdukFromTransferItemLabel(itemLabel) {
  const t = String(itemLabel ?? '').trim();
  if (!t) return null;
  const m = t.match(/^(.+?)\s*[-\u2013\u2014]\s+(.+)$/u);
  if (m) return m[1].trim();
  const idx = t.indexOf(' - ');
  if (idx > 0) return t.slice(0, idx).trim();
  return null;
}

/**
 * If DB has no `transfers.courier` column, POST may prefix notes with
 * "Kurir: …" — expose that as `courier` in GET for clients.
 */
function extractKurirFromTransferNotes(notes) {
  if (notes == null) return null;
  const s = String(notes);
  const m = s.match(/^\s*Kurir:\s*([^\n\r]+)/m);
  return m ? m[1].trim() : null;
}

function roundUpToNearest5000(amount) {
  const n = typeof amount === 'number' ? amount : parseFloat(amount);
  if (!Number.isFinite(n) || n <= 0) return 0;
  return Math.ceil(n / 5000) * 5000;
}

let _cachedItemsPhotoColumn = null; // 'photo_produk' | 'photo_url' | null
async function getItemsPhotoColumn(client) {
  if (_cachedItemsPhotoColumn !== null) return _cachedItemsPhotoColumn;
  try {
    const r = await client.query(
      `
        SELECT column_name
        FROM information_schema.columns
        WHERE table_schema = 'public'
          AND table_name = 'items'
          AND column_name IN ('photo_produk', 'photo_url')
      `,
      []
    );
    const cols = new Set(r.rows.map((x) => x.column_name));
    if (cols.has('photo_produk')) {
      _cachedItemsPhotoColumn = 'photo_produk';
    } else if (cols.has('photo_url')) {
      _cachedItemsPhotoColumn = 'photo_url';
    } else {
      _cachedItemsPhotoColumn = null;
    }
  } catch (_) {
    _cachedItemsPhotoColumn = null;
  }
  return _cachedItemsPhotoColumn;
}

let _cachedPaymentsProofColumnExists = null; // boolean | null (unknown)
async function paymentsHasProofUrlColumn(client) {
  if (_cachedPaymentsProofColumnExists !== null) return _cachedPaymentsProofColumnExists;
  try {
    const r = await client.query(
      `
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = 'public'
          AND table_name = 'payments'
          AND column_name = 'proof_url'
        LIMIT 1
      `,
      []
    );
    _cachedPaymentsProofColumnExists = r.rows.length > 0;
  } catch (_) {
    _cachedPaymentsProofColumnExists = false;
  }
  return _cachedPaymentsProofColumnExists;
}

let _cachedPaymentsValidatedByColumnExists = null; // boolean | null (unknown)
async function paymentsHasValidatedByColumn(client) {
  if (_cachedPaymentsValidatedByColumnExists !== null) {
    return _cachedPaymentsValidatedByColumnExists;
  }
  try {
    const r = await client.query(
      `
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = 'public'
          AND table_name = 'payments'
          AND column_name = 'validated_by'
        LIMIT 1
      `,
      []
    );
    _cachedPaymentsValidatedByColumnExists = r.rows.length > 0;
  } catch (_) {
    _cachedPaymentsValidatedByColumnExists = false;
  }
  return _cachedPaymentsValidatedByColumnExists;
}

let _cachedUsersRoleColumnExists = null; // boolean | null (unknown)
let _cachedUsersBranchIdColumnExists = null; // boolean | null (unknown)
async function usersHasRoleAndBranchColumns(client) {
  if (
    _cachedUsersRoleColumnExists !== null &&
    _cachedUsersBranchIdColumnExists !== null
  ) {
    return {
      hasRole: _cachedUsersRoleColumnExists,
      hasBranchId: _cachedUsersBranchIdColumnExists,
    };
  }
  try {
    const r = await client.query(
      `
        SELECT column_name
        FROM information_schema.columns
        WHERE table_schema = 'public'
          AND table_name = 'users'
          AND column_name IN ('role', 'branch_id')
      `,
      []
    );
    const cols = new Set(r.rows.map((x) => x.column_name));
    _cachedUsersRoleColumnExists = cols.has('role');
    _cachedUsersBranchIdColumnExists = cols.has('branch_id');
  } catch (_) {
    _cachedUsersRoleColumnExists = false;
    _cachedUsersBranchIdColumnExists = false;
  }
  return {
    hasRole: _cachedUsersRoleColumnExists,
    hasBranchId: _cachedUsersBranchIdColumnExists,
  };
}

async function getOrdersJumlahColumnMode(client) {
  // Returns: 'generated' | 'plain' | 'missing'
  try {
    const r = await client.query(
      `
        SELECT is_generated
        FROM information_schema.columns
        WHERE table_schema = 'public'
          AND table_name = 'orders'
          AND column_name = 'jumlah'
        LIMIT 1
      `,
      []
    );
    if (r.rows.length === 0) return 'missing';
    return r.rows[0].is_generated === 'ALWAYS' ? 'generated' : 'plain';
  } catch (_) {
    // If introspection fails, assume plain so we keep values consistent.
    return 'plain';
  }
}

const authRequired = authenticateToken(SECRET_KEY);

/** Koneksi WebSocket yang mengirim ?token=JWT — dipakai superadmin untuk melihat user aktif. */
const wsPresenceBySocket = new Map();

function tryRegisterWsPresenceFromToken(ws, token) {
  if (!token || typeof token !== 'string') return false;
  try {
    const payload = jwt.verify(token, SECRET_KEY);
    const userIdRaw = payload.user_id ?? payload.id;
    const user_id =
      userIdRaw != null ? parseInt(String(userIdRaw), 10) : NaN;
    if (Number.isNaN(user_id)) return false;
    wsPresenceBySocket.set(ws, {
      user_id,
      username: (payload.username || '').toString(),
      role: (payload.role || '').toString(),
      branch_id: (payload.branch_id ?? '').toString(),
      connected_at: new Date().toISOString(),
    });
    return true;
  } catch (_) {
    return false;
  }
}

function getActivePresenceSnapshot() {
  const byUser = new Map();
  for (const meta of wsPresenceBySocket.values()) {
    const uid = meta.user_id;
    if (!byUser.has(uid)) {
      byUser.set(uid, {
        user_id: uid,
        username: meta.username,
        role_active: meta.role,
        branch_id: meta.branch_id,
        sessions: 0,
        connected_since: meta.connected_at,
      });
    }
    const row = byUser.get(uid);
    row.sessions += 1;
    if (meta.connected_at < row.connected_since) {
      row.connected_since = meta.connected_at;
    }
  }
  const users = Array.from(byUser.values()).sort((a, b) =>
    String(a.username).localeCompare(String(b.username)),
  );
  return { users, total_connections: wsPresenceBySocket.size };
}

const loginLimiter = rateLimit({
  windowMs: 15 * 60 * 1000,
  max: 20,
  standardHeaders: true,
  legacyHeaders: false,
  message: { error: 'Too many login attempts. Please try again later.' },
});

const writeApiLimiter = rateLimit({
  windowMs: 1 * 60 * 1000,
  max: 120,
  standardHeaders: true,
  legacyHeaders: false,
  message: { error: 'Too many requests. Please slow down.' },
});

// Serve static files from uploads directory
app.use('/uploads', express.static(path.join(__dirname, 'uploads')));

// Integrasi file storage untuk foto dan PDF
const storage = multer.diskStorage({
  destination: (req, file, cb) => {
    cb(null, path.join(__dirname, 'uploads')); // Folder penyimpanan
  },
  filename: (req, file, cb) => {
    cb(null, localStorage.createSafeUploadFilename(file));
  },
});

const upload = multer({
  storage,
  limits: { fileSize: 5 * 1024 * 1024 },
  fileFilter: (req, file, cb) => {
    const allowedByMime = localStorage.isAllowedUploadMimeType(file.mimetype);
    const allowedByName = localStorage.isAllowedUploadFilename(file.originalname);
    if (!allowedByMime && !allowedByName) {
      cb(new Error('Only JPEG, PNG, and WEBP uploads are allowed'));
      return;
    }
    cb(null, true);
  },
});

// Users:
// - superadmin: full access
// - admin_toko/manajer: read-only (GET) for oversight
app.use('/users', authRequired, (req, res, next) => {
  if (req.method === 'GET') {
    return requireRoles('superadmin', 'admin_toko', 'manajer')(req, res, next);
  }
  // Allow password reset and status updates for superadmin + manajer only.
  // NOTE: Intentionally separated from full user edit (PUT) which stays superadmin-only.
  if (req.method === 'PATCH' && /^\/\d+\/(password|status)$/.test(req.path)) {
    return requireRoles('superadmin', 'manajer')(req, res, next);
  }
  return requireRoles('superadmin')(req, res, next);
});
// Employees:
// - superadmin/admin_toko/admin_workshop: full access
// - manajer: read-only (GET) for oversight
app.use('/employees', authRequired, (req, res, next) => {
  if (req.method === 'GET') {
    return requireRoles(
      'superadmin',
      'admin_toko',
      'admin_workshop',
      'manajer',
    )(req, res, next);
  }
  return requireRoles('superadmin', 'admin_toko', 'admin_workshop')(
    req,
    res,
    next,
  );
});
app.use('/user-branch-roles', authRequired, requireRoles('superadmin'));
// Branch list needs to be readable by non-superadmin modules (e.g. transfers).
// Keep writes restricted at the route-handler level.
app.use('/branches', authRequired);
// Branch list needs to be readable by non-superadmin modules (e.g. transfers/printing).
// Keep writes restricted to superadmin.
app.use('/api/branches', authRequired, (req, res, next) => {
  if (req.method === 'GET') return next();
  return requireRoles('superadmin')(req, res, next);
});
app.use('/orders', authRequired);
app.use('/payments', authRequired);
app.use('/transfers', authRequired);
app.use('/items', authRequired);
app.use('/item-conditions', authRequired);
app.use('/order-items', authRequired);
app.use('/stock-mutations', authRequired);
app.use('/stock-history', authRequired, requireRoles('superadmin', 'admin_toko', 'admin_workshop'));
app.use('/reports', authRequired, requireRoles('superadmin', 'manajer'));
app.use('/api', authRequired);
app.use('/api/workshop', authRequired, requireRoles('superadmin', 'admin_workshop', 'tukang', 'manajer'));

// Debug helper: inspect JWT payload (for troubleshooting role/branch issues)
app.get('/api/whoami', authRequired, (req, res) => {
  res.json({ user: req.user ?? null });
});

app.get('/api/admin/active-sessions', requireRoles('superadmin'), (req, res) => {
  res.json(getActivePresenceSnapshot());
});

app.use('/workshop-orders', authRequired, requireRoles('superadmin', 'admin_workshop', 'tukang'));
app.use('/technicians', authRequired, requireRoles('superadmin', 'admin_workshop'));
app.use('/test-db', authRequired, requireRoles('superadmin'));
app.use(['/orders', '/payments', '/transfers', '/items', '/stock-history', '/stock-mutations', '/employees', '/branches', '/users'], writeApiLimiter);

// Sample data
let orders = [];
let items = [];
let users = [];
let stockHistory = [];
let payments = []; // Tambahkan array untuk menyimpan data pembayaran

// CRUD for Orders
// app.get('/orders', (req, res) => {
//   res.json(orders);
// });

// app.post('/orders', (req, res) => {
//   const order = req.body;
//   orders.push(order);
//   res.status(201).json(order);
//
//   // Kirim notifikasi ke semua klien
//   sendNotificationToClients(`Order baru telah dibuat: ${order.name}`);
// });

app.put('/orders/:id', (req, res) => {
  const id = parseInt(req.params.id);
  const updatedOrder = req.body;
  orders = orders.map(order => (order.id === id ? updatedOrder : order));
  res.json(updatedOrder);
});

app.delete('/orders/:id', (req, res) => {
  const id = parseInt(req.params.id);
  orders = orders.filter(order => order.id !== id);
  res.status(204).send();
});

// Health check endpoint
app.get('/health', async (req, res) => {
  try {
    // Test database connection
    await db.query('SELECT 1');
    res.status(200).json({
      status: 'healthy',
      timestamp: new Date().toISOString(),
      services: {
        database: 'connected',
        websocket: wss ? 'running' : 'not initialized'
      }
    });
  } catch (error) {
    res.status(500).json({
      status: 'unhealthy',
      timestamp: new Date().toISOString(),
      error: error.message
    });
  }
});

// CRUD untuk tabel orders
app.get('/orders', async (req, res) => {
  try {
    const { branch_id, status, order_number } = req.query;
    console.log('GET /orders called with query:', req.query);
    const itemsPhotoCol = await getItemsPhotoColumn(db);
    const itemsPhotoSelect = itemsPhotoCol
      ? `i.${itemsPhotoCol} as item_photo_produk`
      : `NULL as item_photo_produk`;
    let query = `
      SELECT
        o.*,
        c.name as customer_name,
        c.phone as customer_phone,
        c.address as customer_address,
        oi.nama_item,
        oi.kode_produk,
        oi.weight,
        oi.qty,
        oi.harga_per_gram,
        oi.total,
        oi.photo_produk,
        oi.material,
        oi.purity,
        oi.kategori,
        oi.jenis,
        oi.tipe,
        i.item_id,
        i.name as item_name,
        i.kode_produk as item_kode,
        i.material as item_material,
        i.purity as item_purity,
        i.weight as item_weight,
        i.kategori as item_kategori,
        i.jenis as item_jenis,
        i.tipe as item_tipe,
        ${itemsPhotoSelect}
      FROM orders o
      LEFT JOIN customers c ON o.customer_id = c.customer_id
      LEFT JOIN order_items oi ON o.order_id = oi.order_id
      LEFT JOIN items i ON oi.item_id = i.item_id
    `;
    const params = [];
    const conditions = [];

    if (branch_id && !order_number) {
      conditions.push(`o.branch_id = $${params.length + 1}`);
      params.push(branch_id);
    }

    if (status) {
      conditions.push(`o.status = $${params.length + 1}`);
      params.push(status);
    }

    if (order_number) {
      conditions.push(`LOWER(TRIM(o.order_number)) = $${params.length + 1}`);
      params.push(order_number.trim().toLowerCase());
    }

    if (conditions.length > 0) {
      query += ' WHERE ' + conditions.join(' AND ');
    }

    query += ' ORDER BY o.created_at DESC';

    console.log('Executing query:', query);
    console.log('With params:', params);

    let result;
    try {
      result = await db.query(query, params);
    } catch (dbError) {
      console.error('Database query error:', dbError);
      return res.status(500).json({ error: 'Database query failed', details: dbError.message });
    }

    console.log('Query result rows count:', result.rows.length);

    if (order_number) {
      // When order_number is provided, return a single order object with items array
      console.log('Processing order_number:', order_number);
      if (result.rows.length === 0) {
        console.log('No rows found for order_number:', order_number);
        return res.status(200).json(null);
      }

      const order = result.rows[0];
      const items = result.rows.map(row => ({
        item_id: row.item_id ? row.item_id.toString() : null,
        nama_item: row.nama_item || row.item_name,
        kode_produk: row.kode_produk || row.item_kode,
        weight: parseFloat(row.weight || row.item_weight || 0),
        qty: row.qty,
        harga_per_gram: parseFloat(row.harga_per_gram || 0),
        total: parseFloat(row.total || 0),
        photo_produk: row.photo_produk || row.item_photo_produk,
        material: row.material || row.item_material,
        purity: row.purity || row.item_purity,
        kategori: row.kategori || row.item_kategori,
        jenis: row.jenis || row.item_jenis,
        tipe: row.tipe || row.item_tipe,
      })).filter(item => item.nama_item || item.item_id); // Filter out null items

      const orderData = {
        order_id: order.order_id.toString(),
        order_number: order.order_number,
        order_type: order.order_type,
        status: order.status,
        customer_id: order.customer_id.toString(),
        customer_name: order.customer_name,
        customer_phone: order.customer_phone,
        customer_address: order.customer_address,
        branch_id: order.branch_id.toString(),
        user_id: order.user_id.toString(),
        total: parseFloat(order.total || 0),
        jumlah: parseFloat(order.jumlah || roundUpToNearest5000(order.total || 0) || 0),
        diskon: parseFloat(order.diskon || 0),
        mode: order.mode,
        created_at: order.created_at,
        updated_at: order.updated_at,
        items: items,
      };

      try {
        res.status(200).json(orderData);
      } catch (jsonError) {
        console.error('JSON serialization error:', jsonError);
        res.status(500).json({ error: 'JSON serialization failed', details: jsonError.message });
      }
    } else {
      // Return array of orders for general queries
      try {
        res.status(200).json(result.rows);
      } catch (jsonError) {
        console.error('JSON serialization error for general query:', jsonError);
        res.status(500).json({ error: 'JSON serialization failed for general query', details: jsonError.message });
      }
    }
  } catch (error) {
    console.error('Error fetching orders:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

app.post('/orders', upload.single('photo'), async (req, res) => {
  const client = await db.getClient();

  try {
    // Parse order_data from multipart field
    let orderData;
    if (req.body.order_data) {
      orderData = JSON.parse(req.body.order_data);
    } else {
      orderData = req.body; // fallback for non-multipart
    }

    // Handle uploaded photo
    let uploadedPhotoPath = null;
    if (req.file) {
      // Store a URL path (so clients can render it directly)
      uploadedPhotoPath = `/uploads/${req.file.filename}`;
    }

    await client.query('BEGIN');

    // Backward-compatible: DB may have items.photo_url (old) or items.photo_produk (new)
    const itemsPhotoCol = await getItemsPhotoColumn(client);
    const itemsPhotoColName = itemsPhotoCol || 'photo_url';

  // Persist upload metadata (safe: filename is server-generated)
  let uploadId = null;
  if (req.file) {
    const uploaderUserId = req.user?.user_id ? parseInt(req.user.user_id, 10) : null;
    const urlPath = `/uploads/${req.file.filename}`;

    // Best-effort: some environments may not have `uploads` table.
    // IMPORTANT: a failed query inside a transaction aborts the whole transaction
    // in PostgreSQL, so we must use a SAVEPOINT.
    await client.query('SAVEPOINT uploads_insert');
    try {
      const upRes = await client.query(
        `INSERT INTO uploads (storage_key, original_name, mime_type, size_bytes, url_path, uploaded_by_user_id)
         VALUES ($1, $2, $3, $4, $5, $6)
         RETURNING upload_id`,
        [
          req.file.filename,
          req.file.originalname || null,
          req.file.mimetype || null,
          typeof req.file.size === 'number' ? req.file.size : null,
          urlPath,
          Number.isFinite(uploaderUserId) ? uploaderUserId : null,
        ]
      );
      uploadId = upRes.rows[0]?.upload_id ?? null;
      await client.query('RELEASE SAVEPOINT uploads_insert');
    } catch (_) {
      uploadId = null;
      await client.query('ROLLBACK TO SAVEPOINT uploads_insert');
      await client.query('RELEASE SAVEPOINT uploads_insert');
    }
  }

    const {
      order_type,
      order_number,
      branch_id,
      user_id,
      mode,
      customer_id,
      diskon = 0,
      order_items,
      // For backward compatibility
      item_id,
      item_data,
    } = orderData;

    // Validate order_type
    const validOrderTypes = ['jual', 'buyback', 'service', 'custom'];
    if (!validOrderTypes.includes(order_type)) {
      return res.status(400).json({ error: 'Invalid order_type' });
    }

    // Validate required fields
    if (!customer_id || !branch_id || !user_id) {
      return res.status(400).json({ error: 'Missing required fields: customer_id, branch_id, user_id' });
    }

    if (!order_items || !Array.isArray(order_items) || order_items.length === 0) {
      return res.status(400).json({ error: 'Order must have at least one item' });
    }

    // Generate nota_order if not provided
    let nota_order = order_number;
    if (!nota_order) {
      const notaResult = await client.query(
        'SELECT generate_nota_order($1, $2) as nota_order',
        [branch_id, order_type]
      );
      nota_order = notaResult.rows[0].nota_order;
    }

    // Create order
    const orderResult = await client.query(
      `INSERT INTO orders (
        order_type, customer_id, status, order_number, branch_id, user_id, diskon, mode, total
      ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)
      RETURNING *`,
      [order_type, customer_id, 'pending', nota_order, branch_id, user_id, diskon, mode, 0] // total will be calculated later
    );

    const order = orderResult.rows[0];

    // Process order items
    let computedOrderItemsTotal = 0;
    for (const itemData of order_items) {
      // Assign uploaded photo to item if available
      if (uploadedPhotoPath && !itemData.photo_produk) {
        itemData.photo_produk = uploadedPhotoPath;
      }

      let final_item_id = itemData.item_id;
      let itemDetails = itemData; // Default to data from request

      // If item_id exists, this is from stock - get item details from database
      if (final_item_id) {
        const existingItem = await client.query(
          `SELECT
             name, kode_produk, weight, material, purity, kategori, jenis, tipe, ${itemsPhotoColName} as photo_produk,
             quantity, status, ownership, stock_type
           FROM items WHERE item_id = $1`,
          [final_item_id]
        );
        if (existingItem.rows.length > 0) {
          const dbItem = existingItem.rows[0];
          itemDetails = {
            ...itemData, // Keep request data for price, qty, etc.
            nama_item: dbItem.name,
            kode_produk: dbItem.kode_produk,
            weight: dbItem.weight,
            material: dbItem.material,
            purity: dbItem.purity,
            kategori: dbItem.kategori,
            jenis: dbItem.jenis,
            tipe: dbItem.tipe,
            photo_produk: itemData.photo_produk || dbItem.photo_produk,
            // Stock fields (used for quantity decrement / status decisions)
            item_quantity: dbItem.quantity,
            item_status: dbItem.status,
            item_ownership: dbItem.ownership,
            item_stock_type: dbItem.stock_type,
          };
        }
      }

      // Update item photo if new photo is provided for existing stock items
      if (final_item_id && itemData.photo_produk && itemData.photo_produk !== itemDetails.photo_produk) {
        await client.query(
          `UPDATE items SET ${itemsPhotoColName} = $1, updated_at = NOW() WHERE item_id = $2`,
          [itemData.photo_produk, final_item_id]
        );
      }

      // Handle item creation if item_data is provided (for unregistered items)
      if (!final_item_id && itemData.nama_item) {
        // Create new item
        // Try inserting item; if kode_produk already exists, reuse existing item
        try {
          const itemResult = await client.query(
            `INSERT INTO items (
              name, kode_produk, weight, material, purity, kategori, jenis, tipe,
              ownership, stock_type, status, is_quick_registered, branch_id, source, ${itemsPhotoColName}
            ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15)
            RETURNING item_id`,
            [
              itemData.nama_item,
              itemData.kode_produk,
              itemData.weight,
              itemData.material,
              itemData.purity,
              itemData.kategori,
              itemData.jenis,
              itemData.tipe,
              itemData.ownership || 'unknown',
              itemData.stock_type || 'non_inventory',
              itemData.status || 'unregistered',
              itemData.is_quick_registered || false,
              branch_id,
              'manual',
              itemData.photo_produk,
            ]
          );
          final_item_id = itemResult.rows[0].item_id;
        } catch (e) {
          // Handle unique constraint on kode_produk: find existing item
          if (e && e.code === '23505') {
            const existing = await client.query(`SELECT item_id FROM items WHERE kode_produk = $1 LIMIT 1`, [itemData.kode_produk]);
            if (existing.rows.length > 0) {
              final_item_id = existing.rows[0].item_id;
            } else {
              throw e; // rethrow if unexpected
            }
          } else {
            throw e;
          }
        }

        // Update item status based on order type
        let newItemStatus;
        let newOwnership;
        let newStockType;

        switch (order_type) {
          case 'jual':
            if (itemData.is_quick_registered) {
              // QSR flow: reserved -> sold
              newItemStatus = 'sold';
              newOwnership = 'toko';
              newStockType = 'inventory';
            } else {
              // Normal sale: ready -> sold
              newItemStatus = 'sold';
              newOwnership = 'pelanggan';
              newStockType = 'non_inventory';
            }
            break;
          case 'buyback':
            newItemStatus = 'buyback';
            newOwnership = 'toko';
            newStockType = 'inventory';
            break;
          case 'service':
            newItemStatus = 'on-service';
            newOwnership = 'toko';
            newStockType = 'non_inventory';
            break;
          case 'custom':
            newItemStatus = 'on-custom';
            newOwnership = 'toko';
            newStockType = 'non_inventory';
            break;
        }

        await client.query(
          `UPDATE items SET
            status = $1, ownership = $2, stock_type = $3, updated_at = NOW()
           WHERE item_id = $4`,
          [newItemStatus, newOwnership, newStockType, final_item_id]
        );

        // Record in stock_history (use 'unknown' as fallback for old_status to satisfy schema constraints)
        await client.query(
          `INSERT INTO stock_history (item_id, old_status, new_status, changed_by, notes)
           VALUES ($1, $2, $3, $4, $5)`,
          [final_item_id, 'unknown', newItemStatus, user_id, `Order ${order_type} created`]
        );

        // Save item condition for buyback orders
        if (order_type === 'buyback' && itemData.kondisi_barang) {
          await client.query(
            `INSERT INTO item_conditions (
              item_id, order_id, kondisi_fisik, kerusakan, berat_awal, berat_akhir,
              penyesuaian_berat, harga_per_gram, potongan_kondisi, nilai_resale,
              harga_beli, untung_rugi, catatan_kondisi, foto_kondisi, dinilai_oleh
            ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15)`,
            [
              final_item_id,
              order.order_id,
              itemData.kondisi_barang.kondisi_fisik || 'BAIK',
              itemData.kondisi_barang.kerusakan || [],
              parseFloat(itemData.kondisi_barang.berat_awal) || parseFloat(itemData.weight) || 0,
              parseFloat(itemData.kondisi_barang.berat_akhir) || parseFloat(itemData.weight) || 0,
              parseFloat(itemData.kondisi_barang.penyesuaian_berat) || 0,
              parseFloat(itemData.kondisi_barang.harga_per_gram) || parseFloat(itemData.harga_per_gram) || 0,
              parseFloat(itemData.kondisi_barang.potongan_kondisi) || 0,
              parseFloat(itemData.kondisi_barang.nilai_resale) || 0,
              parseFloat(itemData.kondisi_barang.harga_beli) || parseFloat(itemData.subtotal) || 0,
              itemData.kondisi_barang.untung_rugi || 'UNTUNG',
              itemData.kondisi_barang.catatan_kondisi || '',
              itemData.kondisi_barang.foto_kondisi || (itemData.photo_produk ? [itemData.photo_produk] : []),
              user_id
            ]
          );
        }
      }

      // Create order item
      // Catatan: diskon hanya level orders (bukan per item).
      // order_items.subtotal = qty * weight * harga_per_gram
      // order_items.total = pembulatan dari subtotal (naik ke kelipatan 5.000)
      const qtyVal = parseInt(itemDetails.qty) || 1;
      const weightVal = parseFloat(itemDetails.weight) || 0;
      const hargaVal = parseFloat(itemDetails.harga_per_gram) || 0;
      const subtotalVal = qtyVal * weightVal * hargaVal;
      const totalRoundedVal = Math.ceil(subtotalVal / 5000) * 5000;

      await client.query(
        `INSERT INTO order_items (
          order_id, item_id, nama_item, kode_produk, qty, weight, harga_per_gram,
          subtotal, diskon, total, photo_produk, kategori, jenis, tipe, material, purity
        ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15, $16)`,
        [
          order.order_id,
          final_item_id,
          itemDetails.nama_item,
          itemDetails.kode_produk,
          qtyVal,
          weightVal,
          hargaVal,
          Number.isFinite(parseFloat(itemDetails.subtotal))
            ? parseFloat(itemDetails.subtotal)
            : subtotalVal,
          0, // diskon tidak disimpan per-item
          totalRoundedVal, // total item = pembulatan subtotal
          itemDetails.photo_produk,
          itemDetails.kategori,
          itemDetails.jenis,
          itemDetails.tipe,
          itemDetails.material,
          itemDetails.purity,
        ]
      );

      // Keep a running total from the authoritative per-item rounded value
      computedOrderItemsTotal += totalRoundedVal;

      // Update existing item status if it's from stock
      if (final_item_id && itemData.item_id) {
        // Decrease quantity for stock items. If stock remains, keep item as stock.
        const prevQtyRaw = itemDetails.item_quantity;
        const prevQty = Number.isFinite(parseInt(prevQtyRaw, 10))
          ? parseInt(prevQtyRaw, 10)
          : 0;

        const decRes = await client.query(
          `
            UPDATE items
            SET quantity = COALESCE(quantity, 0) - $1,
                updated_at = NOW()
            WHERE item_id = $2
              AND COALESCE(quantity, 0) >= $1
            RETURNING quantity, status
          `,
          [qtyVal, final_item_id]
        );

        if (decRes.rows.length === 0) {
          return res.status(400).json({
            error: 'Insufficient stock quantity',
            detail: `Stock ${prevQty} < order quantity ${qtyVal}`,
          });
        }

        const nextQty = parseInt(decRes.rows[0].quantity, 10);
        const prevStatus = (itemDetails.item_status ?? decRes.rows[0].status ?? 'ready').toString();

        // If stock is depleted, mark as sold; otherwise keep as available for stock.
        if (nextQty <= 0) {
          const newItemStatus = 'sold';
          const newOwnership = 'pelanggan';
          const newStockType = 'non_inventory';

          await client.query(
            `UPDATE items SET
              status = $1, ownership = $2, stock_type = $3, updated_at = NOW()
             WHERE item_id = $4`,
            [newItemStatus, newOwnership, newStockType, final_item_id]
          );

          await client.query(
            `INSERT INTO stock_history (item_id, old_status, new_status, changed_by, notes)
             VALUES ($1, $2, $3, $4, $5)`,
            [final_item_id, prevStatus, newItemStatus, user_id, `Order ${order_type} created (stock depleted)`]
          );
        }

        // Always record stock mutation for this sale
        await client.query(
          `
            INSERT INTO stock_mutations (
              item_id, branch_id, type, quantity, previous_stock, current_stock,
              notes, reference_id, reference_type, created_by
            )
            VALUES ($1, $2, 'sale', $3, $4, $5, $6, $7, 'order', $8)
          `,
          [
            final_item_id,
            branch_id,
            -qtyVal,
            prevQty,
            nextQty,
            `Order ${order_type} (${nota_order})`,
            order.order_id,
            user_id,
          ]
        );
      }
    }

    // Calculate total order amount
    // Source-of-truth: order_items.total (already rounded per item)
    // Order total formula: sum(order_items.total) - (sum(order_items.total) * diskon%)
    const orderItemsTotal = Number.isFinite(computedOrderItemsTotal)
      ? computedOrderItemsTotal
      : 0;
    const diskonOrder = parseFloat(diskon) || 0;
    const orderTotal = orderItemsTotal * (1 - diskonOrder / 100);

    // Update orders.total and keep orders.jumlah consistent.
    // We always *try* to set jumlah; if the column is GENERATED ALWAYS (or missing),
    // the DB will reject the update — then we fallback to updating total only.
    const jumlahRounded = roundUpToNearest5000(orderTotal);
    try {
      await client.query(
        `UPDATE orders
         SET total = $1,
             jumlah = $2,
             updated_at = NOW()
         WHERE order_id = $3`,
        [orderTotal, jumlahRounded, order.order_id]
      );
    } catch (_) {
      await client.query(
        `UPDATE orders SET total = $1, updated_at = NOW() WHERE order_id = $2`,
        [orderTotal, order.order_id]
      );
    }

    // Commit the transaction before sending response
    await client.query('COMMIT');

    // Get order items for response (using new client since transaction committed)
    const itemsClient = await db.getClient();
    try {
      // Fetch the latest order row (including generated `jumlah`)
      const orderFreshResult = await itemsClient.query(
        `SELECT o.*, c.name as customer_name, c.phone as customer_phone, c.address as customer_address
         FROM orders o
         LEFT JOIN customers c ON o.customer_id = c.customer_id
         WHERE o.order_id = $1
         LIMIT 1`,
        [order.order_id]
      );
      const orderFresh = orderFreshResult.rows[0] || order;

      // Fetch customer details for invoice/receipt display
      const orderItemsResult = await itemsClient.query(
        `SELECT oi.*, i.name as item_name, i.kode_produk as item_kode, i.material as item_material, i.purity as item_purity, i.weight as item_weight, i.kategori as item_kategori, i.jenis as item_jenis, i.tipe as item_tipe
         FROM order_items oi
         LEFT JOIN items i ON oi.item_id = i.item_id
         WHERE oi.order_id = $1`,
        [order.order_id]
      );

      const orderItems = orderItemsResult.rows.map(item => ({
        ...item,
        nama_item: item.nama_item || item.item_name,
        kode_produk: item.kode_produk || item.item_kode,
        material: item.material || item.item_material,
        purity: item.purity || item.item_purity,
        weight: item.weight || item.item_weight,
        kategori: item.kategori || item.item_kategori,
        jenis: item.jenis || item.item_jenis,
        tipe: item.tipe || item.item_tipe,
      }));

      res.status(201).json({
        ...orderFresh,
        total: orderTotal,
        items: orderItems,
        message: 'Order created successfully'
      });
    } finally {
      itemsClient.release();
    }

    // Update order total after response is sent
    process.nextTick(async () => {
      try {
        console.log('Starting async total update for order', order.order_id);
        const updateClient = await db.getClient();
        console.log('Got client for update');
        const updateResult = await updateClient.query(
          `UPDATE orders SET total = $1 WHERE order_id = $2`,
          [orderTotal, order.order_id]
        );
        console.log('UPDATE result:', updateResult.rowCount, 'rows affected');
        updateClient.release();
      } catch (err) {
        console.error('Failed to update order total:', err);
      }
    });

  } catch (error) {
    console.error('Error creating order:', error);
    if (error && error.stack) {
      console.error(error.stack);
    }

    // Rollback transaction on error
    try {
      await client.query('ROLLBACK');
    } catch (rollbackError) {
      console.error('Error rolling back transaction:', rollbackError);
    }

    res.status(500).json({
      error: 'Internal server error',
      detail: error.message
    });
  } finally {
    client.release();
  }
});

// Get pending payment orders for kasir
app.get('/orders/pending-payment', async (req, res) => {
  try {
    const { branch_id } = req.query;

    if (!branch_id) {
      return res.status(400).json({ error: 'branch_id is required' });
    }

    const result = await db.query(`
      SELECT
        o.order_id,
        o.order_number,
        o.order_type,
        o.total,
        o.diskon,
        o.created_at,
        o.updated_at,
        c.name as customer_name,
        c.phone,
        c.address,
        COALESCE(oi.nama_item, i.name) as item_name,
        COALESCE(oi.qty, 1) as quantity,
        COALESCE(oi.weight, i.weight, 0) as weight,
        COALESCE(oi.jenis, i.material) as material
      FROM orders o
      JOIN customers c ON o.customer_id = c.customer_id
      LEFT JOIN order_items oi ON o.order_id = oi.order_id
      LEFT JOIN items i ON oi.item_id = i.item_id
      WHERE o.branch_id = $1
        AND o.status IN ('pending', 'ready_for_payment', 'confirmed', 'completed')
        AND NOT EXISTS (
          SELECT 1 FROM payments p
          WHERE p.order_id = o.order_id
          AND p.status = 'completed'
        )
      ORDER BY o.created_at DESC
    `, [branch_id]);

    // Convert BigInt and other data types for JSON serialization
    const processedRows = result.rows.map(row => ({
      order_id: row.order_id.toString(),
      order_number: row.order_number,
      order_type: row.order_type,
      total: parseFloat(row.total || 0),
      diskon: parseFloat(row.diskon || 0),
      created_at: row.created_at,
      updated_at: row.updated_at,
      customer_name: row.customer_name,
      phone: row.phone,
      address: row.address,
      item_name: row.item_name,
      quantity: parseInt(row.quantity || 1),
      weight: parseFloat(row.weight || 0),
      material: row.material
    }));

    res.status(200).json(processedRows);
  } catch (error) {
    console.error('Error fetching pending payment orders:', error);
    res.status(500).json({ error: 'Internal server error', details: error.message });
  }
});

// Get daily payments for kasir and admin toko
app.get('/payments/daily-summary', async (req, res) => {
  try {
    const { branch_id, date, user_id } = req.query;

    if (!branch_id) {
      return res.status(400).json({ error: 'branch_id is required' });
    }

    const targetDate = date || new Date().toISOString().split('T')[0];
    const hasProofCol = await paymentsHasProofUrlColumn(db);
    const hasValidatedByCol = await paymentsHasValidatedByColumn(db);

    const validatedOnlyRaw = (req.query.validated_by_only ?? '').toString().trim().toLowerCase();
    const validatedOnly =
      validatedOnlyRaw === '1' || validatedOnlyRaw === 'true' || validatedOnlyRaw === 'yes';

    const userIdFilterRaw = (user_id ?? '').toString().trim();
    let userIdFromQuery =
      userIdFilterRaw.length > 0 ? parseInt(userIdFilterRaw, 10) : null;
    if (userIdFilterRaw.length > 0 && (userIdFromQuery == null || Number.isNaN(userIdFromQuery))) {
      return res.status(400).json({ error: 'user_id must be a number' });
    }

    let userIdFilter = null;
    if (validatedOnly) {
      if (!hasValidatedByCol) {
        return res.status(400).json({
          error: 'Kolom payments.validated_by belum tersedia',
          details:
            'Jalankan migration backend/migrations/20260502_000006_add_payments_validated_by.sql agar filter pembayaran per kasir bisa dipakai.',
        });
      }
      const tokenUserId = req.user?.user_id ?? req.user?.id;
      const parsedTokenUserId =
        tokenUserId != null ? parseInt(String(tokenUserId), 10) : NaN;
      if (tokenUserId == null || Number.isNaN(parsedTokenUserId)) {
        return res.status(401).json({
          error: 'Unauthorized',
          details: 'Token tidak berisi user_id; silakan login ulang.',
        });
      }
      userIdFilter = parsedTokenUserId;
    } else if (userIdFromQuery != null) {
      if (!hasValidatedByCol) {
        console.warn(
          '[payments/daily-summary] Ignoring user_id query filter: payments.validated_by column missing.',
        );
      } else {
        userIdFilter = userIdFromQuery;
      }
    }

    // Get payments for the day
    const paymentsResult = await db.query(`
      SELECT
        p.payment_id,
        p.order_id,
        p.amount,
        p.method as payment_method,
        p.status,
        ${hasProofCol ? 'p.proof_url' : 'NULL'} as proof_url,
        ${hasValidatedByCol ? 'p.validated_by' : 'NULL'} as validated_by,
        p.notes,
        p.created_at,
        p.updated_at,
        o.order_number,
        o.order_type,
        c.name as customer_name,
        c.phone
      FROM payments p
      JOIN orders o ON p.order_id = o.order_id
      JOIN customers c ON o.customer_id = c.customer_id
      WHERE o.branch_id = $1
        AND DATE(p.created_at) = $2
        ${userIdFilter != null ? 'AND p.validated_by = $3' : ''}
      ORDER BY p.created_at DESC
    `, userIdFilter != null ? [branch_id, targetDate, userIdFilter] : [branch_id, targetDate]);

    // Get summary
    const summaryResult = await db.query(`
      SELECT
        COUNT(*) as total_payments,
        SUM(amount) as total_amount,
        COUNT(CASE WHEN method = 'cash' THEN 1 END) as cash_payments,
        COUNT(CASE WHEN method = 'transfer' THEN 1 END) as transfer_payments,
        COUNT(CASE WHEN method = 'qris' THEN 1 END) as qris_payments
      FROM payments p
      JOIN orders o ON p.order_id = o.order_id
      WHERE o.branch_id = $1
        AND DATE(p.created_at) = $2
        AND p.status = 'completed'
        ${userIdFilter != null ? 'AND p.validated_by = $3' : ''}
    `, userIdFilter != null ? [branch_id, targetDate, userIdFilter] : [branch_id, targetDate]);

    const summary = summaryResult.rows[0] || {
      total_payments: 0,
      total_amount: 0,
      cash_payments: 0,
      transfer_payments: 0,
      qris_payments: 0
    };

    // Convert BigInt and other data types for JSON serialization
    const processedPayments = paymentsResult.rows.map(row => ({
      payment_id: row.payment_id.toString(),
      order_id: row.order_id.toString(),
      amount: parseFloat(row.amount || 0),
      payment_method: row.payment_method,
      status: row.status,
      proof_url: row.proof_url,
      validated_by: row.validated_by,
      notes: row.notes,
      created_at: row.created_at,
      updated_at: row.updated_at,
      order_number: row.order_number,
      order_type: row.order_type,
      customer_name: row.customer_name,
      phone: row.phone
    }));

    const processedSummary = {
      total_payments: parseInt(summary.total_payments || 0),
      total_amount: parseFloat(summary.total_amount || 0),
      cash_payments: parseInt(summary.cash_payments || 0),
      transfer_payments: parseInt(summary.transfer_payments || 0),
      qris_payments: parseInt(summary.qris_payments || 0)
    };

    res.status(200).json({
      transactions: processedPayments,
      summary: processedSummary
    });
  } catch (error) {
    console.error('Error fetching daily payments:', error);
    res.status(500).json({ error: 'Internal server error', details: error.message });
  }
});

// Get orders with date filter for admin toko
app.get('/orders/by-date', async (req, res) => {
  try {
    const { branch_id, date } = req.query;

    let query = `
      SELECT
        o.order_id,
        o.order_number,
        o.order_type,
        o.status,
        o.total,
        o.diskon,
        o.created_at,
        o.updated_at,
        c.name as customer_name,
        c.phone,
        COALESCE(oi.nama_item, i.name) as item_name,
        COALESCE(oi.qty, 1) as quantity
      FROM orders o
      JOIN customers c ON o.customer_id = c.customer_id
      LEFT JOIN order_items oi ON o.order_id = oi.order_id
      LEFT JOIN items i ON oi.item_id = i.item_id
    `;

    let params = [];
    let conditions = [];

    if (branch_id) {
      conditions.push(`o.branch_id = $${params.length + 1}`);
      params.push(branch_id);
    }

    if (date) {
      conditions.push(`DATE(o.created_at) = $${params.length + 1}`);
      params.push(date);
    }

    if (conditions.length > 0) {
      query += ' WHERE ' + conditions.join(' AND ');
    }

    query += ' ORDER BY o.created_at DESC';

    const result = await db.query(query, params);

    // Convert BigInt and other data types for JSON serialization
    const processedRows = result.rows.map(row => ({
      order_id: row.order_id.toString(),
      order_number: row.order_number,
      order_type: row.order_type,
      status: row.status,
      total: parseFloat(row.total || 0),
      diskon: parseFloat(row.diskon || 0),
      created_at: row.created_at,
      updated_at: row.updated_at,
      customer_name: row.customer_name,
      phone: row.phone,
      item_name: row.item_name,
      quantity: parseInt(row.quantity || 1)
    }));

    res.status(200).json(processedRows);
  } catch (error) {
    console.error('Error fetching orders:', error);
    res.status(500).json({ error: 'Internal server error', details: error.message });
  }
});

// Get transfers for goods transfer page
app.get('/transfers/legacy', async (req, res) => {
  try {
    const { branch_id, status } = req.query;

    let query = `
      SELECT
        t.transfer_id,
        t.from_branch_id,
        t.to_branch_id,
        t.status,
        t.created_at,
        t.updated_at,
        t.notes,
        fb.name as from_branch_name,
        tb.name as to_branch_name
      FROM transfers t
      JOIN branches fb ON t.from_branch_id = fb.branch_id
      JOIN branches tb ON t.to_branch_id = tb.branch_id
    `;

    let params = [];
    let conditions = [];

    if (branch_id) {
      conditions.push(`(t.from_branch_id = $${params.length + 1} OR t.to_branch_id = $${params.length + 1})`);
      params.push(branch_id);
    }

    if (status) {
      conditions.push(`t.status = $${params.length + 1}`);
      params.push(status);
    }

    if (conditions.length > 0) {
      query += ' WHERE ' + conditions.join(' AND ');
    }

    query += ' ORDER BY t.created_at DESC';

    const result = await db.query(query, params);

    // Convert BigInt for JSON serialization
    const processedRows = result.rows.map(row => ({
      transfer_id: row.transfer_id.toString(),
      from_branch_id: row.from_branch_id.toString(),
      to_branch_id: row.to_branch_id.toString(),
      status: row.status,
      created_at: row.created_at,
      updated_at: row.updated_at,
      notes: row.notes,
      from_branch_name: row.from_branch_name,
      to_branch_name: row.to_branch_name
    }));

    res.status(200).json(processedRows);
  } catch (error) {
    console.error('Error fetching transfers:', error);
    res.status(500).json({ error: 'Internal server error', details: error.message });
  }
});

// Get item conditions with optional filters
app.get('/item-conditions', async (req, res) => {
  try {
    const { item_id, order_id, branch_id } = req.query;

    let query = `
      SELECT
        ic.condition_id,
        ic.item_id,
        ic.order_id,
        ic.kondisi_fisik,
        ic.kerusakan,
        ic.berat_awal,
        ic.berat_akhir,
        ic.penyesuaian_berat,
        ic.keaslian,
        ic.sertifikat,
        ic.nilai_resale,
        ic.harga_beli,
        ic.catatan_kondisi,
        ic.foto_kondisi,
        ic.dinilai_oleh,
        ic.tanggal_penilaian,
        ic.created_at,
        ic.updated_at,
        i.name as item_name,
        i.kode_produk,
        i.weight as item_weight,
        i.material,
        i.purity,
        o.order_number,
        o.order_type,
        c.name as customer_name,
        u.username as dinilai_oleh_username
      FROM item_conditions ic
      JOIN items i ON ic.item_id = i.item_id
      JOIN orders o ON ic.order_id = o.order_id
      JOIN customers c ON o.customer_id = c.customer_id
      LEFT JOIN users u ON ic.dinilai_oleh = u.user_id
    `;

    let params = [];
    let conditions = [];

    if (item_id) {
      conditions.push(`ic.item_id = $${params.length + 1}`);
      params.push(item_id);
    }

    if (order_id) {
      conditions.push(`ic.order_id = $${params.length + 1}`);
      params.push(order_id);
    }

    if (branch_id) {
      conditions.push(`o.branch_id = $${params.length + 1}`);
      params.push(branch_id);
    }

    if (conditions.length > 0) {
      query += ' WHERE ' + conditions.join(' AND ');
    }

    query += ' ORDER BY ic.created_at DESC';

    const result = await db.query(query, params);

    // Convert BigInt and other data types for JSON serialization
    const processedRows = result.rows.map(row => ({
      condition_id: row.condition_id.toString(),
      item_id: row.item_id.toString(),
      order_id: row.order_id.toString(),
      kondisi_fisik: row.kondisi_fisik,
      kerusakan: row.kerusakan || [],
      berat_awal: parseFloat(row.berat_awal || 0),
      berat_akhir: parseFloat(row.berat_akhir || 0),
      penyesuaian_berat: row.penyesuaian_berat,
      keaslian: row.keaslian,
      sertifikat: row.sertifikat,
      nilai_resale: parseInt(row.nilai_resale || 0),
      harga_beli: parseInt(row.harga_beli || 0),
      catatan_kondisi: row.catatan_kondisi,
      foto_kondisi: row.foto_kondisi || [],
      dinilai_oleh: row.dinilai_oleh ? row.dinilai_oleh.toString() : null,
      tanggal_penilaian: row.tanggal_penilaian,
      created_at: row.created_at,
      updated_at: row.updated_at,
      item_name: row.item_name,
      kode_produk: row.kode_produk,
      item_weight: parseFloat(row.item_weight || 0),
      material: row.material,
      purity: row.purity,
      order_number: row.order_number,
      order_type: row.order_type,
      customer_name: row.customer_name,
      dinilai_oleh_username: row.dinilai_oleh_username
    }));

    res.status(200).json(processedRows);
  } catch (error) {
    console.error('Error fetching item conditions:', error);
    res.status(500).json({ error: 'Internal server error', details: error.message });
  }
});

// Get all branches
app.get('/branches', async (req, res) => {
  try {
    const result = await db.query(`
      SELECT
        branch_id,
        name,
        code,
        alias,
        initials,
        address,
        phone_number,
        status
      FROM branches
      ORDER BY name
    `);

    // Convert BigInt for JSON serialization
    const processedRows = result.rows.map(row => ({
      branch_id: row.branch_id.toString(),
      name: row.name,
      code: row.code,
      alias: row.alias,
      initials: row.initials,
      address: row.address,
      phone_number: row.phone_number,
      status: row.status
    }));

    res.status(200).json(processedRows);
  } catch (error) {
    console.error('Error fetching branches:', error);
    res.status(500).json({ error: 'Internal server error', details: error.message });
  }
});

app.post('/branches', requireRoles('superadmin'), async (req, res) => {
  try {
    const { name, code, alias, initials, address, phone_number } = req.body;

    if (!name || !code) {
      return res.status(400).json({ error: 'name and code are required' });
    }

    const insertQuery = `
      INSERT INTO branches (name, code, alias, initials, address, phone_number, status, created_at, updated_at)
      VALUES ($1, $2, $3, $4, $5, $6, 'active', NOW(), NOW())
      RETURNING branch_id, name, code, alias, initials, address, phone_number, status, created_at, updated_at
    `;
    const result = await db.query(insertQuery, [name, code, alias, initials, address, phone_number]);

    res.status(201).json(result.rows[0]);
  } catch (error) {
    console.error('Error creating branch:', error);
    if (error.code === '23505') {
      res.status(400).json({ error: 'Branch code already exists' });
    } else {
      res.status(500).json({ error: 'Internal server error' });
    }
  }
});

// CRUD for Items
app.get('/items', async (req, res) => {
  try {
    const { branch_id, item_code, stock_type, status, is_quick_registered, search, limit } = req.query;
    let query = 'SELECT * FROM items';
    let params = [];
    let conditions = [];

    if (branch_id) {
      conditions.push(`branch_id = $${params.length + 1}`);
      params.push(branch_id);
    }

    if (item_code) {
      // Backward compatible: DB schema uses kode_produk
      conditions.push(`(kode_produk = $${params.length + 1})`);
      params.push(item_code);
    }

    // stock_type is not available in older schema; ignore when present

    if (status) {
      conditions.push(`status = $${params.length + 1}`);
      params.push(status);
    }

    if (is_quick_registered !== undefined) {
      conditions.push(`is_quick_registered = $${params.length + 1}`);
      params.push(is_quick_registered === 'true');
    }

    if (search) {
      conditions.push(`(CAST(item_id AS TEXT) ILIKE $${params.length + 1} OR kode_produk ILIKE $${params.length + 1} OR name ILIKE $${params.length + 1})`);
      params.push(`%${search}%`);
    }

    if (conditions.length > 0) {
      query += ' WHERE ' + conditions.join(' AND ');
    }

    query += ' ORDER BY created_at DESC';

    if (limit) {
      query += ` LIMIT $${params.length + 1}`;
      params.push(parseInt(limit));
    }

    const result = await db.query(query, params);
    res.status(200).json(result.rows);
  } catch (error) {
    console.error('Error fetching items:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// Get item conditions
app.get('/item-conditions', async (req, res) => {
  try {
    const { item_id, order_id } = req.query;
    let query = 'SELECT * FROM item_conditions WHERE 1=1';
    const params = [];

    if (item_id) {
      query += ' AND item_id = $' + (params.length + 1);
      params.push(item_id);
    }

    if (order_id) {
      query += ' AND order_id = $' + (params.length + 1);
      params.push(order_id);
    }

    query += ' ORDER BY created_at DESC';

    const result = await db.query(query, params);
    res.status(200).json(result.rows);
  } catch (error) {
    console.error('Error fetching item conditions:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

app.post('/items', async (req, res) => {
  try {
    const {
      name,
      quantity = 1,
      weight,
      material,
      purity,
      kategori,
      jenis,
      tipe,
      status,
      branch_id,
      source = 'manual',
      metadata,
      // Legacy support
      kode_produk,
      // Accept newer clients sending item_code
      item_code,
    } = req.body;

    // Handle legacy kode_produk field
    const final_item_code = item_code || kode_produk;

    if (!branch_id || !name || !final_item_code || !status || weight == null) {
      return res.status(400).json({
        error:
          'branch_id, name, item_code/kode_produk, status, dan weight wajib diisi',
      });
    }
    if (!material || !purity) {
      return res.status(400).json({
        error: 'material dan purity wajib diisi',
      });
    }

    const result = await db.query(
      `INSERT INTO items (
        branch_id, kode_produk, kategori, jenis, tipe, name, material, purity, weight, quantity,
        status, source, metadata, created_at, updated_at
      ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, NOW(), NOW())
      RETURNING *`,
      [
        branch_id,
        final_item_code,
        kategori,
        jenis,
        tipe,
        name,
        material,
        purity,
        weight,
        quantity,
        status,
        source,
        metadata,
      ]
    );

    res.status(201).json(result.rows[0]);
  } catch (error) {
    console.error('Error creating item:', error);
    // Provide safer, actionable errors to the client
    // Common PG codes:
    // - 23505 unique_violation
    // - 23502 not_null_violation
    // - 23503 foreign_key_violation
    // - 22P02 invalid_text_representation
    const pgCode = error?.code;
    const detail = error?.detail || null;
    const message = error?.message || 'Unknown error';

    if (pgCode === '23505') {
      return res.status(400).json({
        error: 'Duplicate item_code/kode_produk',
        detail,
        code: pgCode,
      });
    }

    if (pgCode === '23502' || pgCode === '23503' || pgCode === '22P02') {
      return res.status(400).json({
        error: 'Invalid item payload',
        detail,
        code: pgCode,
      });
    }

    return res.status(500).json({
      error: 'Internal server error',
      detail,
      code: pgCode || null,
      message: process.env.NODE_ENV === 'production' ? undefined : message,
    });
  }
});

app.put('/items/:id', async (req, res) => {
  try {
    const id = parseInt(req.params.id);
    const {
      name,
      weight,
      material,
      purity,
      kategori,
      jenis,
      tipe,
      status,
      branch_id,
      source,
      metadata,
      // Legacy support
      kode_produk,
      // Accept newer clients sending item_code
      item_code,
    } = req.body;

    // Handle legacy kode_produk field
    const final_item_code = item_code || kode_produk;

    if (!branch_id || !name || !final_item_code || !status || weight == null) {
      return res.status(400).json({
        error:
          'branch_id, name, item_code/kode_produk, status, dan weight wajib diisi',
      });
    }
    if (!material || !purity) {
      return res.status(400).json({
        error: 'material dan purity wajib diisi',
      });
    }

    const result = await db.query(
      `UPDATE items SET
        branch_id = $1,
        kode_produk = $2,
        kategori = $3,
        jenis = $4,
        tipe = $5,
        name = $6,
        material = $7,
        purity = $8,
        weight = $9,
        status = $10,
        source = $11,
        metadata = $12,
        updated_at = NOW()
      WHERE item_id = $13
      RETURNING *`,
      [
        branch_id,
        final_item_code,
        kategori,
        jenis,
        tipe,
        name,
        material,
        purity,
        weight,
        status,
        source,
        metadata,
        id,
      ]
    );

    if (result.rows.length === 0) {
      return res.status(404).json({ error: 'Item not found' });
    }

    res.json(result.rows[0]);
  } catch (error) {
    console.error('Error updating item:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// Restock: increment item quantity safely
app.post('/items/:id/restock', async (req, res) => {
  try {
    const id = parseInt(req.params.id);
    const { delta_quantity, branch_id } = req.body || {};

    const delta = parseInt(delta_quantity);
    if (!Number.isFinite(delta) || delta <= 0) {
      return res
        .status(400)
        .json({ error: 'delta_quantity wajib diisi dan harus > 0' });
    }

    const params = [delta, id];
    let sql = `
      UPDATE items
      SET quantity = COALESCE(quantity, 0) + $1,
          updated_at = NOW()
      WHERE item_id = $2
    `;

    if (branch_id) {
      sql += ` AND branch_id = $3`;
      params.push(branch_id);
    }

    sql += ` RETURNING *`;

    const result = await db.query(sql, params);
    if (result.rows.length === 0) {
      return res.status(404).json({ error: 'Item not found' });
    }

    return res.status(200).json(result.rows[0]);
  } catch (error) {
    console.error('Error restocking item:', error);
    return res.status(500).json({ error: 'Internal server error' });
  }
});

app.delete('/items/:id', (req, res) => {
  const id = parseInt(req.params.id);
  items = items.filter(item => item.id !== id);
  res.status(204).send();
});

// CRUD for Order Items (untuk buyback) - diubah untuk referensi order_id
app.get('/order-items', async (req, res) => {
  try {
    const query = `
      SELECT
        o.order_id,
        o.order_type,
        o.status as order_status,
        o.created_at as order_date,
        o.mode,
        oi.order_item_id as order_item_id,
        oi.nama_item,
        oi.weight,
        oi.harga_per_gram,
        oi.diskon,
        oi.total,
        oi.photo_produk,
        oi.kode_produk,
        oi.qty,
        oi.kategori,
        oi.jenis,
        oi.tipe,
        COALESCE(c.name, 'Customer Tidak Ditemukan') as customer_name,
        c.phone as customer_phone,
        c.address as customer_address,
        CASE
          WHEN i.material IS NOT NULL THEN i.material
          ELSE 'Emas'
        END as material,
        CASE
          WHEN i.purity IS NOT NULL THEN i.purity
          ELSE '24K'
        END as kadar
      FROM order_items oi
      LEFT JOIN orders o ON oi.order_id = o.order_id
      LEFT JOIN customers c ON o.customer_id = c.customer_id
      LEFT JOIN items i ON oi.item_id = i.item_id
      WHERE o.order_type = 'jual'
      ORDER BY o.created_at DESC
    `;
    const result = await db.query(query);
    res.json(result.rows);
  } catch (error) {
    console.error('Error fetching order items:', error);
    res.status(500).json({ error: 'Failed to fetch order items' });
  }
});// CRUD for Users
app.get('/users', async (req, res) => {
  try {
    const query = `
      SELECT
        u.user_id,
        u.username,
        u.status,
        u.created_at,
        u.updated_at,
        ubr.role,
        b.name as branch_name,
        b.branch_id
      FROM users u
      LEFT JOIN user_branch_roles ubr ON u.user_id = ubr.user_id
      LEFT JOIN branches b ON ubr.branch_id = b.branch_id
      ORDER BY u.username ASC
    `;

    const result = await db.query(query);

    // Group users by user_id and format the response
    const usersMap = new Map();
    result.rows.forEach(row => {
      const userId = row.user_id;
      if (!usersMap.has(userId)) {
        usersMap.set(userId, {
          user_id: row.user_id,
          username: row.username,
          status: row.status,
          created_at: row.created_at,
          updated_at: row.updated_at,
          branches: []
        });
      }

      if (row.role && row.branch_id) {
        usersMap.get(userId).branches.push({
          branch_id: row.branch_id,
          branch_name: row.branch_name,
          role: row.role,
          is_primary: row.is_primary || false
        });
      }
    });

    const users = Array.from(usersMap.values());
    res.json(users);
  } catch (error) {
    console.error('Error fetching users:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

app.post('/users', async (req, res) => {
  try {
    const { username, password, role, branch_id, is_primary = false } = req.body;

    if (!username || !password) {
      return res.status(400).json({ error: 'username and password are required' });
    }

    // Hash password
    const saltRounds = 10;
    const hashedPassword = await bcrypt.hash(password, saltRounds);

    // Insert user
    const userQuery = `
      INSERT INTO users (username, password_hash, status)
      VALUES ($1, $2, 'active')
      RETURNING user_id
    `;

    const userResult = await db.query(userQuery, [username, hashedPassword]);
    const userId = userResult.rows[0].user_id;

    // Insert user_branch_role if role and branch_id are provided
    if (role && branch_id) {
      const roleQuery = `
        INSERT INTO user_branch_roles (user_id, branch_id, role, is_primary)
        VALUES ($1, $2, $3, $4)
      `;
      await db.query(roleQuery, [userId, branch_id, role, is_primary]);
    }

    res.status(201).json({ message: 'User created successfully', user_id: userId });
  } catch (error) {
    console.error('Error creating user:', error);
    if (error.code === '23505') { // Unique constraint violation
      res.status(400).json({ error: 'Username already exists' });
    } else {
      res.status(500).json({ error: 'Internal server error' });
    }
  }
});

app.put('/users/:id', async (req, res) => {
  try {
    const id = parseInt(req.params.id);
    const { username, role, branch_id, is_primary, status } = req.body;

    if (!username) {
      return res.status(400).json({ error: 'username is required' });
    }

    // Update user basic info
    let userQuery = 'UPDATE users SET username = $1';
    const params = [username];
    let paramIndex = 2;

    if (status) {
      userQuery += `, status = $${paramIndex}`;
      params.push(status);
      paramIndex++;
    }

    userQuery += `, updated_at = now() WHERE user_id = $${paramIndex}`;
    params.push(id);

    await db.query(userQuery, params);

    // Update or insert user_branch_role if role and branch_id are provided
    if (role && branch_id) {
      // First, check if role already exists for this user and branch
      const existingRole = await db.query(
        'SELECT id FROM user_branch_roles WHERE user_id = $1 AND branch_id = $2 AND role = $3',
        [id, branch_id, role]
      );

      if (existingRole.rows.length > 0) {
        // Update existing role
        await db.query(
          'UPDATE user_branch_roles SET is_primary = $1 WHERE id = $2',
          [is_primary || false, existingRole.rows[0].id]
        );
      } else {
        // Insert new role
        await db.query(
          'INSERT INTO user_branch_roles (user_id, branch_id, role, is_primary) VALUES ($1, $2, $3, $4)',
          [id, branch_id, role, is_primary || false]
        );
      }
    }

    res.json({ message: 'User updated successfully' });
  } catch (error) {
    console.error('Error updating user:', error);
    if (error.code === '23505') {
      res.status(400).json({ error: 'Username already exists' });
    } else {
      res.status(500).json({ error: 'Internal server error' });
    }
  }
});

app.patch('/users/:id/password', async (req, res) => {
  try {
    const id = parseInt(req.params.id);
    const { password } = req.body ?? {};
    const newPassword = (password ?? '').toString();
    if (!newPassword.trim()) {
      return res.status(400).json({ error: 'password is required' });
    }
    if (newPassword.trim().length < 4) {
      return res.status(400).json({ error: 'password must be at least 4 characters' });
    }

    const hashedPassword = await bcrypt.hash(newPassword, 10);
    const result = await db.query(
      'UPDATE users SET password_hash = $1, updated_at = CURRENT_TIMESTAMP WHERE user_id = $2',
      [hashedPassword, id]
    );
    if (result.rowCount === 0) {
      return res.status(404).json({ error: 'User not found' });
    }
    res.json({ message: 'Password updated successfully' });
  } catch (error) {
    console.error('Error updating user password:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

app.patch('/users/:id/status', async (req, res) => {
  try {
    const id = parseInt(req.params.id);
    const { status } = req.body ?? {};
    const nextStatus = (status ?? '').toString().trim().toLowerCase();
    if (nextStatus !== 'active' && nextStatus !== 'inactive') {
      return res.status(400).json({ error: 'status must be active or inactive' });
    }

    const result = await db.query(
      'UPDATE users SET status = $1, updated_at = CURRENT_TIMESTAMP WHERE user_id = $2',
      [nextStatus, id]
    );
    if (result.rowCount === 0) {
      return res.status(404).json({ error: 'User not found' });
    }
    res.json({ message: 'User status updated successfully', status: nextStatus });
  } catch (error) {
    console.error('Error updating user status:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

app.delete('/users/:id', async (req, res) => {
  try {
    const id = parseInt(req.params.id);

    // Delete user_branch_roles first (due to foreign key constraint)
    await db.query('DELETE FROM user_branch_roles WHERE user_id = $1', [id]);

    // Then delete the user
    const result = await db.query('DELETE FROM users WHERE user_id = $1', [id]);

    if (result.rowCount === 0) {
      return res.status(404).json({ error: 'User not found' });
    }

    res.json({ message: 'User deleted successfully' });
  } catch (error) {
    console.error('Error deleting user:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// CRUD for User Branch Roles
app.get('/user-branch-roles/:userId', async (req, res) => {
  try {
    const userId = parseInt(req.params.userId);
    const query = `
      SELECT
        ubr.id,
        ubr.user_id,
        ubr.branch_id,
        ubr.role,
        ubr.is_primary,
        b.name as branch_name
      FROM user_branch_roles ubr
      LEFT JOIN branches b ON ubr.branch_id = b.branch_id
      WHERE ubr.user_id = $1
      ORDER BY ubr.is_primary DESC, b.name ASC
    `;

    const result = await db.query(query, [userId]);
    res.json(result.rows);
  } catch (error) {
    console.error('Error fetching user branch roles:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

app.post('/user-branch-roles', async (req, res) => {
  try {
    const { user_id, branch_id, role, is_primary = false } = req.body;

    if (!user_id || !branch_id || !role) {
      return res.status(400).json({ error: 'user_id, branch_id, and role are required' });
    }

    // Check if role already exists for this user and branch
    const existingRole = await db.query(
      'SELECT id FROM user_branch_roles WHERE user_id = $1 AND branch_id = $2 AND role = $3',
      [user_id, branch_id, role]
    );

    if (existingRole.rows.length > 0) {
      return res.status(400).json({ error: 'Role already exists for this user and branch' });
    }

    // If setting as primary, unset other primary roles for this user
    if (is_primary) {
      await db.query(
        'UPDATE user_branch_roles SET is_primary = false WHERE user_id = $1',
        [user_id]
      );
    }

    const query = `
      INSERT INTO user_branch_roles (user_id, branch_id, role, is_primary)
      VALUES ($1, $2, $3, $4)
      RETURNING id
    `;

    const result = await db.query(query, [user_id, branch_id, role, is_primary]);
    res.status(201).json({
      message: 'User branch role created successfully',
      id: result.rows[0].id
    });
  } catch (error) {
    console.error('Error creating user branch role:', error);
    if (error.code === '23505') {
      res.status(400).json({ error: 'Role already exists for this user and branch' });
    } else {
      res.status(500).json({ error: 'Internal server error' });
    }
  }
});

app.put('/user-branch-roles/:id', async (req, res) => {
  try {
    const id = parseInt(req.params.id);
    const { role, is_primary } = req.body;

    let query = 'UPDATE user_branch_roles SET';
    const params = [];
    let paramIndex = 1;

    if (role !== undefined) {
      query += ` role = $${paramIndex}`;
      params.push(role);
      paramIndex++;
    }

    if (is_primary !== undefined) {
      if (params.length > 0) query += ',';
      query += ` is_primary = $${paramIndex}`;
      params.push(is_primary);

      // If setting as primary, unset other primary roles for this user
      if (is_primary) {
        const userResult = await db.query('SELECT user_id FROM user_branch_roles WHERE id = $1', [id]);
        if (userResult.rows.length > 0) {
          await db.query(
            'UPDATE user_branch_roles SET is_primary = false WHERE user_id = $1 AND id != $2',
            [userResult.rows[0].user_id, id]
          );
        }
      }
    }

    if (params.length === 0) {
      return res.status(400).json({ error: 'No fields to update' });
    }

    query += ` WHERE id = $${paramIndex}`;
    params.push(id);

    const result = await db.query(query, params);

    if (result.rowCount === 0) {
      return res.status(404).json({ error: 'User branch role not found' });
    }

    res.json({ message: 'User branch role updated successfully' });
  } catch (error) {
    console.error('Error updating user branch role:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

app.delete('/user-branch-roles/:userId/:branchId/:role', async (req, res) => {
  try {
    const userId = parseInt(req.params.userId);
    const branchId = parseInt(req.params.branchId);
    const role = req.params.role;

    const result = await db.query(
      'DELETE FROM user_branch_roles WHERE user_id = $1 AND branch_id = $2 AND role = $3',
      [userId, branchId, role]
    );

    if (result.rowCount === 0) {
      return res.status(404).json({ error: 'User branch role not found' });
    }

    res.json({ message: 'User branch role deleted successfully' });
  } catch (error) {
    console.error('Error deleting user branch role:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// CRUD for Branches
app.get('/branches', async (req, res) => {
  try {
    const query = `
      SELECT
        branch_id,
        name,
        code,
        alias,
        initials,
        address,
        phone_number,
        status,
        created_at,
        updated_at
      FROM branches
      ORDER BY name ASC
    `;

    const result = await db.query(query);
    res.json(result.rows);
  } catch (error) {
    console.error('Error fetching branches:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

app.get('/branches/:id/basic', async (req, res) => {
  try {
    const id = parseInt(req.params.id);
    const query = `
      SELECT
        branch_id,
        name,
        code,
        alias,
        initials,
        address,
        phone_number,
        status,
        created_at,
        updated_at
      FROM branches
      WHERE branch_id = $1
    `;

    const result = await db.query(query, [id]);

    if (result.rows.length === 0) {
      return res.status(404).json({ error: 'Branch not found' });
    }

    res.json(result.rows[0]);
  } catch (error) {
    console.error('Error fetching branch:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

app.get('/branches/:id/users', async (req, res) => {
  try {
    const branchId = parseInt(req.params.id);
    const query = `
      SELECT
        u.user_id,
        u.username,
        u.status as user_status,
        ubr.role,
        ubr.is_primary
      FROM users u
      JOIN user_branch_roles ubr ON u.user_id = ubr.user_id
      WHERE ubr.branch_id = $1
      ORDER BY ubr.is_primary DESC, u.username ASC
    `;

    const result = await db.query(query, [branchId]);
    res.json(result.rows);
  } catch (error) {
    console.error('Error fetching branch users:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

app.get('/branches/:id/statistics', async (req, res) => {
  try {
    const branchId = parseInt(req.params.id);

    // Get user count
    const userQuery = 'SELECT COUNT(*) as count FROM user_branch_roles WHERE branch_id = $1';
    const userResult = await db.query(userQuery, [branchId]);
    const totalUsers = parseInt(userResult.rows[0].count);

    // Get transaction count (this month)
    const transactionQuery = `
      SELECT COUNT(*) as count
      FROM orders
      WHERE branch_id = $1
      AND created_at >= DATE_TRUNC('month', CURRENT_DATE)
    `;
    const transactionResult = await db.query(transactionQuery, [branchId]);
    const totalTransactions = parseInt(transactionResult.rows[0].count);

    // Get items count in this branch
    const itemsQuery = 'SELECT COUNT(*) as count FROM items WHERE branch_id = $1';
    const itemsResult = await db.query(itemsQuery, [branchId]);
    const totalItems = parseInt(itemsResult.rows[0].count);

    // Get completed orders this month
    const completedOrdersQuery = `
      SELECT COUNT(*) as count
      FROM orders
      WHERE branch_id = $1
      AND status = 'completed'
      AND created_at >= DATE_TRUNC('month', CURRENT_DATE)
    `;
    const completedResult = await db.query(completedOrdersQuery, [branchId]);
    const completedOrders = parseInt(completedResult.rows[0].count);

    res.json({
      total_users: totalUsers,
      total_transactions: totalTransactions,
      total_items: totalItems,
      completed_orders_this_month: completedOrders
    });
  } catch (error) {
    console.error('Error fetching branch statistics:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

app.get('/branches/:id', async (req, res) => {
  try {
    const id = parseInt(req.params.id);
    const query = `
      SELECT
        branch_id,
        name,
        code,
        alias,
        initials,
        address,
        phone_number,
        status,
        created_at,
        updated_at
      FROM branches
      WHERE branch_id = $1
    `;

    const result = await db.query(query, [id]);

    if (result.rows.length === 0) {
      return res.status(404).json({ error: 'Branch not found' });
    }

    res.json(result.rows[0]);
  } catch (error) {
    console.error('Error fetching branch:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

app.put('/branches/:id', requireRoles('superadmin'), async (req, res) => {
  try {
    const id = parseInt(req.params.id);
    const { name, code, alias, initials, address, phone_number } = req.body;

    if (!name || !code) {
      return res.status(400).json({ error: 'name and code are required' });
    }

    const query = `
      UPDATE branches
      SET name = $1, code = $2, alias = $3, initials = $4, address = $5, phone_number = $6, updated_at = now()
      WHERE branch_id = $7
    `;

    const result = await db.query(query, [name, code, alias, initials, address, phone_number, id]);

    if (result.rowCount === 0) {
      return res.status(404).json({ error: 'Branch not found' });
    }

    res.json({ message: 'Branch updated successfully' });
  } catch (error) {
    console.error('Error updating branch:', error);
    if (error.code === '23505') {
      res.status(400).json({ error: 'Branch code already exists' });
    } else {
      res.status(500).json({ error: 'Internal server error' });
    }
  }
});

app.patch('/branches/:id/status', requireRoles('superadmin'), async (req, res) => {
  try {
    const id = parseInt(req.params.id);
    const { status } = req.body;

    if (!status || !['active', 'inactive'].includes(status)) {
      return res.status(400).json({ error: 'Valid status (active/inactive) is required' });
    }

    const query = 'UPDATE branches SET status = $1, updated_at = now() WHERE branch_id = $2';

    const result = await db.query(query, [status, id]);

    if (result.rowCount === 0) {
      return res.status(404).json({ error: 'Branch not found' });
    }

    res.json({ message: 'Branch status updated successfully' });
  } catch (error) {
    console.error('Error updating branch status:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

app.delete('/branches/:id', requireRoles('superadmin'), async (req, res) => {
  try {
    const id = parseInt(req.params.id);

    // Check if branch has users assigned
    const userCheck = await db.query('SELECT COUNT(*) as count FROM user_branch_roles WHERE branch_id = $1', [id]);
    if (parseInt(userCheck.rows[0].count) > 0) {
      return res.status(400).json({ error: 'Cannot delete branch with assigned users' });
    }

    const result = await db.query('DELETE FROM branches WHERE branch_id = $1', [id]);

    if (result.rowCount === 0) {
      return res.status(404).json({ error: 'Branch not found' });
    }

    res.json({ message: 'Branch deleted successfully' });
  } catch (error) {
    console.error('Error deleting branch:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// Validate branch code uniqueness
// Use a non-ambiguous path so it won't collide with /branches/:id
app.get('/branches/validation/code', async (req, res) => {
  try {
    const { code, exclude } = req.query;

    if (!code) {
      return res.status(400).json({ error: 'Code parameter is required' });
    }

    let query = 'SELECT COUNT(*) as count FROM branches WHERE code = $1';
    const params = [code];

    if (exclude) {
      query += ' AND branch_id != $2';
      params.push(exclude);
    }

    const result = await db.query(query, params);
    const exists = parseInt(result.rows[0].count) > 0;

    res.json({ valid: !exists });
  } catch (error) {
    console.error('Error validating branch code:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// Export branches
app.get('/branches/export', async (req, res) => {
  try {
    const { format = 'csv' } = req.query;

    const query = 'SELECT * FROM branches ORDER BY name ASC';
    const result = await db.query(query);

    if (format === 'csv') {
      let csv = 'Branch ID,Name,Code,Alias,Initials,Address,Phone Number,Status,Created At,Updated At\n';

      result.rows.forEach(row => {
        csv += `${row.branch_id},"${row.name}","${row.code}","${row.alias || ''}","${row.initials || ''}","${row.address || ''}","${row.phone_number || ''}","${row.status}","${row.created_at}","${row.updated_at}"\n`;
      });

      res.setHeader('Content-Type', 'text/csv');
      res.setHeader('Content-Disposition', 'attachment; filename="branches.csv"');
      res.send(csv);
    } else {
      res.json(result.rows);
    }
  } catch (error) {
    console.error('Error exporting branches:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// Endpoint untuk generate PDF nota
app.post('/generate-pdf', (req, res) => {
  try {
    const { orderId, customerName, items } = req.body;

    const doc = new PDFDocument();
    const filePath = `./uploads/invoice-${orderId}.pdf`;
    const writeStream = fs.createWriteStream(filePath);

    doc.pipe(writeStream);

    doc.fontSize(20).text('Invoice', { align: 'center' });
    doc.moveDown();
    doc.fontSize(12).text(`Order ID: ${orderId}`);
    doc.text(`Customer Name: ${customerName}`);
    doc.moveDown();

    items.forEach((item, index) => {
      doc.text(`${index + 1}. ${item.name} - ${item.quantity} x ${item.price}`);
    });

    doc.end();

    writeStream.on('finish', () => {
      res.status(200).json({
        message: 'PDF generated successfully',
        filePath,
      });
    });
  } catch (error) {
    console.error('Error generating PDF:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// Endpoint untuk upload file - DEPRECATED: sekarang menggunakan storage service di port 4000
// app.post('/upload', upload.single('file'), (req, res) => {
//   try {
//     if (!req.file) {
//       return res.status(400).json({ error: 'No file uploaded' });
//     }

//     // Buat URL yang bisa diakses dari frontend (storage service di port 4000)
//     const fileUrl = `http://10.0.2.2:4000/uploads/${req.file.filename}`;

//     res.status(200).json({
//       message: 'File uploaded successfully',
//       url: fileUrl,
//       fileUrl: fileUrl,
//       path: req.file.path,
//       filename: req.file.filename
//     });
//   } catch (error) {
//     console.error('Error uploading file:', error);
//     res.status(500).json({ error: 'Internal server error' });
//   }
// });

// Endpoint GET /upload untuk info
app.get('/upload', (req, res) => {
  res.send('Gunakan POST untuk upload file ke endpoint ini.');
});

// Endpoint POST /upload
// Dipakai oleh Flutter app untuk upload foto (field: "file").
// Mengembalikan url path relatif: "/uploads/<filename>".
app.post('/upload', upload.any(), async (req, res) => {
  try {
    const file = (Array.isArray(req.files) && req.files.length > 0)
      ? req.files[0]
      : req.file;

    if (!file) {
      return res.status(400).json({ error: 'No file uploaded' });
    }

    const urlPath = `/uploads/${file.filename}`;

    // Best-effort: persist upload metadata if table exists.
    try {
      await db.query(
        `INSERT INTO uploads (storage_key, original_name, mime_type, size_bytes, url_path, uploaded_by_user_id)
         VALUES ($1, $2, $3, $4, $5, $6)`,
        [
          file.filename,
          file.originalname || null,
          file.mimetype || null,
          typeof file.size === 'number' ? file.size : null,
          urlPath,
          null,
        ]
      );
    } catch (_) {
      // ignore if uploads table doesn't exist or insert fails
    }

    res.status(200).json({
      success: true,
      url: urlPath,
      fileUrl: urlPath,
      path: urlPath,
      filename: file.filename,
    });
  } catch (error) {
    console.error('Error uploading file:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// Tambahkan endpoint untuk root path
app.get('/', (req, res) => {
  res.send('Server is running!');
});

// Start server
const server = app.listen(port, '0.0.0.0', () => {
  console.log(`Server running at http://0.0.0.0:${port}`);
  console.log(`Accessible at http://localhost:${port} and http://10.0.2.2:${port} (Android emulator)`);
});

// Tambahkan WebSocket untuk notifikasi realtime
const wss = new WebSocket.Server({ server }); // Use the same server for WebSocket

wss.on('connection', (ws, req) => {
  console.log('New client connected'); // Log tambahan untuk koneksi baru

  try {
    const host = req.headers.host || 'localhost';
    const url = new URL(req.url || '/', `http://${host}`);
    const token = url.searchParams.get('token');
    if (token) tryRegisterWsPresenceFromToken(ws, token);
  } catch (err) {
    console.warn('WebSocket presence (query):', err.message);
  }

  ws.on('message', (raw) => {
    const text = Buffer.isBuffer(raw) ? raw.toString('utf8') : String(raw);
    try {
      const msg = JSON.parse(text);
      if (msg && msg.type === 'presence' && typeof msg.token === 'string') {
        const ok = tryRegisterWsPresenceFromToken(ws, msg.token);
        ws.send(
          JSON.stringify(
            ok
              ? { type: 'presence_ack' }
              : { type: 'presence_error', error: 'invalid_token' },
          ),
        );
        return;
      }
    } catch (_) {
      // bukan JSON presence — lanjut broadcast
    }

    console.log(`Received message: ${text}`); // Log tambahan untuk pesan yang diterima
    wss.clients.forEach((client) => {
      if (client.readyState === WebSocket.OPEN) {
        client.send(text);
      }
    });
  });

  ws.on('close', () => {
    wsPresenceBySocket.delete(ws);
    console.log('Client disconnected'); // Log tambahan untuk koneksi yang ditutup
  });
});



// Tambahkan log untuk debugging endpoint HTTP
app.use((req, res, next) => {
  console.log(`HTTP ${req.method} request to ${req.url}`);
  next();
});

// Tambahkan cron job untuk pengingat otomatis
cron.schedule('0 9 * * *', () => {
  console.log('Mengirim pengingat harian ke semua pengguna pada pukul 09:00');

  // Contoh logika pengingat otomatis
  const reminderMessage = 'Jangan lupa untuk memeriksa stok dan pesanan hari ini!';
  sendNotificationToClients(reminderMessage);
});

console.log('Cron job untuk pengingat otomatis telah diaktifkan.');

// Tambahkan fungsi untuk mengirim notifikasi realtime
function sendNotificationToClients(message) {
  console.log(`Broadcasting message: ${message}`);
  emitNotification(wss, message);
}

// Endpoint untuk mencatat perubahan stok
app.post('/stock-history', (req, res) => {
  const { item_id, user_id, branch_id, change_type, quantity } = req.body;

  if (!item_id || !user_id || !branch_id || !change_type || !quantity) {
    return res.status(400).json({ error: 'Semua field wajib diisi' });
  }

  const stockChange = {
    id: Date.now(), // ID sementara sebelum menggunakan database
    item_id,
    user_id,
    branch_id,
    change_type,
    quantity,
    timestamp: new Date().toISOString(),
  };

  // Simpan perubahan stok ke array sementara
  stockHistory.push(stockChange);

  console.log('Perubahan stok dicatat:', stockChange);
  res.status(201).json({ message: 'Perubahan stok berhasil dicatat', stockChange });
});

// Endpoint untuk mencatat transaksi pembayaran
app.post('/payments', async (req, res) => {
  try {
    const { order_id, amount, method, status, notes, proof_url } = req.body;

    if (!order_id || !amount || !method) {
      return res.status(400).json({ error: 'order_id, amount, dan method wajib diisi' });
    }

    const parsedOrderId = parseInt(order_id, 10);
    if (isNaN(parsedOrderId)) {
      return res.status(400).json({ error: 'order_id harus berupa angka' });
    }

    // Validasi method pembayaran
    const validMethods = ['cash', 'transfer', 'qris', 'e-wallet'];
    if (!validMethods.includes(method)) {
      return res.status(400).json({ error: 'Method pembayaran tidak valid' });
    }

    // For non-cash methods, payment proof photo is required
    const requiresProof = method === 'transfer' || method === 'qris' || method === 'e-wallet';
    if (requiresProof) {
      const proof = (proof_url ?? '').toString().trim();
      if (!proof) {
        return res.status(400).json({
          error: 'Bukti pembayaran (proof_url) wajib untuk metode transfer/qris/e-wallet',
        });
      }
    }

    // Validasi status
    const validStatuses = ['pending', 'completed', 'failed', 'cancelled'];
    const paymentStatus = status || 'completed';
    if (!validStatuses.includes(paymentStatus)) {
      return res.status(400).json({ error: 'Status pembayaran tidak valid' });
    }

    // Cek apakah order ada dan ambil order_type
    const orderCheck = await db.query('SELECT order_id, order_type FROM orders WHERE order_id = $1', [parsedOrderId]);
    if (orderCheck.rows.length === 0) {
      return res.status(404).json({ error: 'Order tidak ditemukan' });
    }

    const orderType = orderCheck.rows[0].order_type;

    // Cek apakah order sudah pernah dibayar (completed payment)
    const existingPayment = await db.query(
      'SELECT payment_id FROM payments WHERE order_id = $1 AND status = $2',
      [parsedOrderId, 'completed']
    );
    if (existingPayment.rows.length > 0) {
      return res.status(400).json({ error: 'Order ini sudah dibayar. Tidak dapat melakukan pembayaran ganda.' });
    }

    const hasProofCol = await paymentsHasProofUrlColumn(db);
    const hasValidatedByCol = await paymentsHasValidatedByColumn(db);
    let finalNotes = notes;
    const proofTrimmed = (proof_url ?? '').toString().trim();
    if (!hasProofCol && proofTrimmed) {
      const n = (finalNotes ?? '').toString().trim();
      finalNotes = n ? `${n}\nBukti: ${proofTrimmed}` : `Bukti: ${proofTrimmed}`;
    }

    // Insert pembayaran ke database (backward-compatible with older DBs)
    const validatedBy = req.user?.user_id ?? req.user?.id ?? null;
    const cols = ['order_id', 'amount', 'method', 'status', 'notes'];
    const values = ['$1', '$2', '$3', '$4', '$5'];
    const params = [parsedOrderId, amount, method, paymentStatus, finalNotes];
    let idx = params.length;

    if (hasProofCol) {
      cols.push('proof_url');
      values.push(`$${++idx}`);
      params.push(proof_url || null);
    }

    if (hasValidatedByCol) {
      cols.push('validated_by');
      values.push(`$${++idx}`);
      params.push(validatedBy);
    }

    cols.push('payment_date');
    values.push('CURRENT_TIMESTAMP');

    const insertQuery = `
      INSERT INTO payments (${cols.join(', ')})
      VALUES (${values.join(', ')})
      RETURNING *
    `;

    const result = await db.query(insertQuery, params);

    // Update status order jika pembayaran completed
    if (paymentStatus === 'completed') {
      await db.query('UPDATE orders SET status = $1, updated_at = CURRENT_TIMESTAMP WHERE order_id = $2', ['completed', parsedOrderId]);
      // Kirim notifikasi realtime
      sendNotificationToClients(`Order ${parsedOrderId} (${orderType}) telah dibayar dan status berubah ke completed`);
    }

    const payment = result.rows[0];
    console.log('Pembayaran dicatat:', payment);
    res.status(201).json({ message: 'Pembayaran berhasil dicatat', payment });
  } catch (error) {
    console.error('Error creating payment:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// Endpoint untuk login dan pengaturan session
app.post('/login', loginLimiter, async (req, res) => {
  try {
    const { username, password } = req.body;
    if (!username || !password) {
      return res.status(400).json({ error: 'username and password are required' });
    }

    // Ambil user + role/branch dari user_branch_roles (primary dulu).
    // Beberapa deployment legacy mungkin punya users.role/users.branch_id — include hanya jika kolomnya ada.
    const usersCols = await usersHasRoleAndBranchColumns(db);
    const userRoleSelect = usersCols.hasRole ? 'u.role as user_role,' : '';
    const userBranchSelect = usersCols.hasBranchId
      ? 'u.branch_id as user_branch_id,'
      : '';
    const query = `
      SELECT
        u.*,
        ${userRoleSelect}
        ${userBranchSelect}
        ubr.role as branch_role,
        ubr.branch_id as branch_role_branch_id
      FROM users u
      LEFT JOIN user_branch_roles ubr ON u.user_id = ubr.user_id
      WHERE u.username = $1
      ORDER BY ubr.is_primary DESC NULLS LAST
      LIMIT 1
    `;
    const result = await db.query(query, [username]);

    if (result.rows.length === 0) {
      return res.status(401).json({ error: 'Invalid username or password' });
    }

    const user = result.rows[0];
    const resolvedRole =
      (user.branch_role ?? user.user_role ?? user.role ?? '').toString().trim().toLowerCase();
    const resolvedBranchId =
      (user.branch_role_branch_id ?? user.user_branch_id ?? user.branch_id ?? '').toString().trim();

    if (!resolvedRole || !resolvedBranchId) {
      return res.status(403).json({
        error: 'Forbidden',
        details:
          'User belum memiliki role/branch. Tambahkan assignment di tabel user_branch_roles (atau jalankan setup_superadmin.js untuk akun superadmin).',
      });
    }
    let isPasswordValid = false;
    const passwordHash = user.password_hash || '';
    if (passwordHash.startsWith('$2')) {
      isPasswordValid = await bcrypt.compare(password, passwordHash);
    } else {
      // Legacy compatibility path for older rows; migrate hash on successful login.
      isPasswordValid = password === passwordHash;
      if (isPasswordValid) {
        const migratedHash = await bcrypt.hash(password, 10);
        await db.query(
          'UPDATE users SET password_hash = $1, updated_at = CURRENT_TIMESTAMP WHERE user_id = $2',
          [migratedHash, user.user_id]
        );
      }
    }

    if (!isPasswordValid) {
      return res.status(401).json({ error: 'Invalid username or password' });
    }

    // Tentukan mainModule sesuai role
    let mainModule = null;
    switch (resolvedRole) {
      case 'cs':
        mainModule = 'cs';
        break;
      case 'kasir':
        mainModule = 'kasir'; // Ubah dari 'payment' ke 'kasir'
        break;
      case 'superadmin':
        mainModule = 'superadmin';
        break;
      case 'admin_toko':
        mainModule = 'order';
        break;
      case 'admin_workshop':
      case 'tukang':
        mainModule = 'workshop';
        break;
      case 'manajer':
        mainModule = 'reporting';
        break;
      default:
        mainModule = 'dashboard';
    }

    // Ambil semua role dan branch user
    const rolesResult = await db.query(
      'SELECT DISTINCT role FROM user_branch_roles WHERE user_id = $1',
      [user.user_id]
    );
    // Ambil branch beserta role per branch
    const branchesWithRolesResult = await db.query(
      `SELECT ubr.branch_id, b.name, b.initials, array_agg(ubr.role) as roles
        FROM user_branch_roles ubr
        JOIN branches b ON ubr.branch_id = b.branch_id
        WHERE ubr.user_id = $1
        GROUP BY ubr.branch_id, b.name, b.initials`,
      [user.user_id]
    );
    const roles = rolesResult.rows.map(r => r.role);
    // branches: array of objects {branch_id, name, initials, roles}
    const branches = branchesWithRolesResult.rows.map(b => ({ branch_id: b.branch_id, name: b.name, initials: b.initials, roles: b.roles }));

    // Tambahkan log response login
    const token = jwt.sign(
      {
        user_id: user.user_id,
        username: user.username,
        role: resolvedRole,
        branch_id: resolvedBranchId,
      },
      SECRET_KEY,
      { expiresIn: JWT_EXPIRES_IN }
    );

    const loginResponse = {
      success: true,
      user_id: user.user_id, // tambahkan user_id
      username: user.username,
      role: resolvedRole,
      branch: resolvedBranchId,
      mainModule,
      roles,
      branches,
      token,
    };
    res.status(200).json(loginResponse);
  } catch (error) {
    console.error('Error during login:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// Endpoint untuk laporan dan analitik
app.get('/reports', async (req, res) => {
  try {
    const { branchId, area, startDate, endDate } = req.query;

    // Query laporan berdasarkan parameter
    const query = `
      SELECT * FROM reports
      WHERE branch_id = $1 AND area = $2 AND date BETWEEN $3 AND $4
    `;
    const values = [branchId, area, startDate, endDate];

    const result = await db.query(query, values);
    res.status(200).json(result.rows);
  } catch (error) {
    console.error('Error fetching reports:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// Manajer: daftar order completed hari ini dari semua branch
app.get('/reports/orders-completed-today', async (req, res) => {
  try {
    const { limit } = req.query;

    let query = `
      SELECT
        o.order_id,
        o.order_number,
        o.order_type,
        o.status,
        o.total,
        o.total_akhir,
        o.diskon,
        o.mode,
        o.created_at,
        o.updated_at,
        o.branch_id,
        b.name as branch_name,
        o.user_id,
        u.username as created_by_username,
        o.customer_id,
        c.name as customer_name,
        c.phone as customer_phone
      FROM orders o
      LEFT JOIN branches b ON o.branch_id = b.branch_id
      LEFT JOIN users u ON o.user_id = u.user_id
      LEFT JOIN customers c ON o.customer_id = c.customer_id
      WHERE DATE(o.created_at) = CURRENT_DATE
        AND o.status = 'completed'
      ORDER BY o.created_at DESC
    `;

    const params = [];
    if (limit) {
      query += ` LIMIT $1`;
      params.push(parseInt(limit, 10));
    }

    const result = await db.query(query, params);
    const processed = result.rows.map(r => ({
      ...r,
      order_id: r.order_id?.toString?.() ?? r.order_id,
      branch_id: r.branch_id?.toString?.() ?? r.branch_id,
      user_id: r.user_id?.toString?.() ?? r.user_id,
      customer_id: r.customer_id?.toString?.() ?? r.customer_id,
      total: r.total == null ? null : parseFloat(r.total),
      total_akhir: r.total_akhir == null ? null : parseFloat(r.total_akhir),
      diskon: r.diskon == null ? null : parseFloat(r.diskon),
    }));

    res.status(200).json(processed);
  } catch (error) {
    console.error('Error fetching completed orders today:', error);
    res.status(500).json({ error: 'Internal server error', detail: error.message });
  }
});

// Validasi tabel database
// const validateDatabase = async () => {
//   try {
//     const tables = ['users', 'branches', 'user_branch_roles', 'items', 'orders', 'customers', 'payments', 'transfers', 'stock_mutations'];
//     for (const table of tables) {
//       const result = await db.query(`SELECT to_regclass('${table}')`);
//       if (!result.rows[0].to_regclass) {
//         console.error(`Table ${table} is missing in the database.`);
//       } else {
//         console.log(`Table ${table} exists.`);
//       }
//     }
//   } catch (error) {
//     console.error('Error validating database tables:', error);
//   }
// };

// validateDatabase();

// Endpoint untuk alur order
app.post('/order', async (req, res) => {
  try {
    const { orderType, itemId, customerName, weight, material, purity, status } = req.body;

    // Validasi data order
    if (!orderType || !customerName || !status) {
      return res.status(400).json({ error: 'Missing required fields' });
    }

    // Simpan order ke database
    const query = `
      INSERT INTO orders (order_type, item_id, name, weight, material, purity, status)
      VALUES ($1, $2, $3, $4, $5, $6, $7) RETURNING *
    `;
    const values = [orderType, itemId, customerName, weight, material, purity, status];
    const result = await db.query(query, values);

    // Push notifikasi real-time
    wss.clients.forEach((client) => {
      if (client.readyState === WebSocket.OPEN) {
        client.send(`New order created: ${result.rows[0].order_id}`);
      }
    });

    res.status(201).json(result.rows[0]);
  } catch (error) {
    console.error('Error creating order:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// Endpoint untuk mendapatkan daftar pembayaran
app.get('/payments', async (req, res) => {
  try {
    const { branch_id, order_id, status, method, limit = 50, offset = 0 } = req.query;

    let query = `
      SELECT
        p.*,
        COALESCE(STRING_AGG(oi.nama_item, ', '), 'Unknown Item') as nama_item,
        o.total_akhir as order_total,
        c.name as customer_name,
        b.name as branch_name
      FROM payments p
      JOIN orders o ON p.order_id = o.order_id
      LEFT JOIN customers c ON o.customer_id = c.customer_id
      LEFT JOIN branches b ON o.branch_id = b.branch_id
      LEFT JOIN order_items oi ON o.order_id = oi.order_id
      WHERE 1=1
    `;

    const params = [];
    let paramIndex = 1;

    if (branch_id) {
      query += ` AND o.branch_id = $${paramIndex}`;
      params.push(branch_id);
      paramIndex++;
    }

    if (order_id) {
      query += ` AND p.order_id = $${paramIndex}`;
      params.push(order_id);
      paramIndex++;
    }

    if (status) {
      query += ` AND p.status = $${paramIndex}`;
      params.push(status);
      paramIndex++;
    }

    if (method) {
      query += ` AND p.method = $${paramIndex}`;
      params.push(method);
      paramIndex++;
    }

    query += ` GROUP BY p.payment_id, p.order_id, p.amount, p.method, p.status, p.created_at, p.updated_at, o.total_akhir, c.name, b.name ORDER BY p.created_at DESC LIMIT $${paramIndex} OFFSET $${paramIndex + 1}`;
    params.push(limit, offset);

    const result = await db.query(query, params);
    res.status(200).json(result.rows);
  } catch (error) {
    console.error('Error fetching payments:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// Endpoint untuk mendapatkan data order harian (admin_toko)
app.get('/orders/daily', async (req, res) => {
  try {
    const { branch_id, user_id, date } = req.query;

    if (!branch_id) {
      return res.status(400).json({ error: 'branch_id is required' });
    }

    // Use provided date (YYYY-MM-DD) or fallback to CURRENT_DATE.
    const targetDate = (date && String(date).trim().length > 0)
      ? String(date).trim()
      : null;

    // Params: branch_id, (optional) user_id, (optional) date
    const params = [parseInt(branch_id)];

    // For admin_toko and CS (no user_id filter), return orders with item details
    // For other roles (with user_id filter), return orders with item details
    let query;
    if (user_id) {
      // Filtered view - include item details
      query = `
        SELECT
          o.*,
          c.name as customer_name,
          c.phone as customer_phone,
          c.address as customer_address,
          oi.nama_item,
          oi.kode_produk,
          oi.weight,
          oi.qty,
          oi.harga_per_gram,
          oi.total as item_total,
          i.material,
          i.purity,
          oi.kategori,
          oi.jenis,
          oi.tipe,
          i.item_id,
          i.name as item_name,
          i.kode_produk as item_kode,
          i.material as item_material,
          i.purity as item_purity,
          i.weight as item_weight,
          i.kategori as item_kategori,
          i.jenis as item_jenis,
          i.tipe as item_tipe
        FROM orders o
        LEFT JOIN customers c ON o.customer_id = c.customer_id
        LEFT JOIN order_items oi ON o.order_id = oi.order_id
        LEFT JOIN items i ON oi.item_id = i.item_id
        WHERE o.branch_id = $1
          AND o.user_id = $2
      `;
      params.push(parseInt(user_id));
    } else {
      // Admin toko / CS view - orders with item details, no user filter
      query = `
        SELECT
          o.*,
          c.name as customer_name,
          c.phone as customer_phone,
          c.address as customer_address,
          oi.nama_item,
          oi.kode_produk,
          oi.weight,
          oi.qty,
          oi.harga_per_gram,
          oi.total as item_total,
          i.material,
          i.purity,
          oi.kategori,
          oi.jenis,
          oi.tipe,
          i.item_id,
          i.name as item_name,
          i.kode_produk as item_kode,
          i.material as item_material,
          i.purity as item_purity,
          i.weight as item_weight,
          i.kategori as item_kategori,
          i.jenis as item_jenis,
          i.tipe as item_tipe
        FROM orders o
        LEFT JOIN customers c ON o.customer_id = c.customer_id
        LEFT JOIN order_items oi ON o.order_id = oi.order_id
        LEFT JOIN items i ON oi.item_id = i.item_id
        WHERE o.branch_id = $1
      `;
    }

    // Date filter:
    // - include orders created on target date
    // - PLUS orders that have a completed payment on target date (paid today)
    if (targetDate) {
      query += `
        AND (
          DATE(o.created_at) = $${params.length + 1}
          OR EXISTS (
            SELECT 1
            FROM payments p
            WHERE p.order_id = o.order_id
              AND p.status = 'completed'
              AND DATE(p.created_at) = $${params.length + 1}
          )
        )
      `;
      params.push(targetDate);
    } else {
      query += `
        AND (
          DATE(o.created_at) = CURRENT_DATE
          OR EXISTS (
            SELECT 1
            FROM payments p
            WHERE p.order_id = o.order_id
              AND p.status = 'completed'
              AND DATE(p.created_at) = CURRENT_DATE
          )
        )
      `;
    }

    query += ' ORDER BY o.created_at DESC';

    const result = await db.query(query, params);
    res.status(200).json(result.rows);
  } catch (error) {
    console.error('Error fetching daily orders:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// Endpoint untuk mendapatkan data transfer barang (admin_toko)
app.get('/transfers', async (req, res) => {
  try {
    const { branch_id, status, type } = req.query;

    // Backward-compatible: columns may not exist yet.
    async function hasTransfersColumn(columnName) {
      try {
        const r = await db.query(
          `
            SELECT 1
            FROM information_schema.columns
            WHERE table_schema = 'public'
              AND table_name = 'transfers'
              AND column_name = $1
            LIMIT 1
          `,
          [columnName]
        );
        return r.rows.length > 0;
      } catch (_) {
        return false;
      }
    }

    const [hasSourceTypeCol, hasCourierCol] = await Promise.all([
      hasTransfersColumn('source_type'),
      hasTransfersColumn('courier'),
    ]);

    let query = `
      SELECT
        t.transfer_id,
        t.from_branch_id,
        t.to_branch_id,
        t.item_name,
        t.quantity,
        ${hasSourceTypeCol ? 't.source_type' : "'stok'"} as source_type,
        ${hasCourierCol ? 't.courier' : 'NULL'} as courier,
        t.notes,
        t.order_id,
        t.created_by,
        t.approved_by,
        t.status,
        t.created_at,
        t.updated_at,
        fb.name as from_branch_name,
        tb.name as to_branch_name,
        u.username as created_by_name,
        uap.username as approved_by_name
      FROM transfers t
      LEFT JOIN branches fb ON t.from_branch_id = fb.branch_id
      LEFT JOIN branches tb ON t.to_branch_id = tb.branch_id
      LEFT JOIN users u ON t.created_by = u.user_id
      LEFT JOIN users uap ON t.approved_by = uap.user_id
      WHERE 1=1
    `;

    const params = [];
    let paramIndex = 1;

    if (branch_id) {
      query += ` AND (t.from_branch_id = $${paramIndex} OR t.to_branch_id = $${paramIndex})`;
      params.push(branch_id);
      paramIndex++;
    }

    if (status) {
      query += ` AND t.status = $${paramIndex}`;
      params.push(status);
      paramIndex++;
    }

    if (type) {
      if (type === 'incoming') {
        query += ` AND t.to_branch_id = $${paramIndex}`;
        params.push(branch_id);
        paramIndex++;
      } else if (type === 'outgoing') {
        query += ` AND t.from_branch_id = $${paramIndex}`;
        params.push(branch_id);
        paramIndex++;
      }
    }

    query += ` ORDER BY t.created_at DESC`;

    const result = await db.query(query, params);
    // Prevent "Do not know how to serialize a BigInt" when sending JSON
    const processedRows = result.rows.map(row => {
      const rawC = row.courier;
      let displayCourier = rawC;
      if (displayCourier == null || (typeof displayCourier === 'string' && displayCourier.trim() === '')) {
        const fromNotes = extractKurirFromTransferNotes(row.notes);
        if (fromNotes) displayCourier = fromNotes;
      }
      return {
        ...row,
        courier: displayCourier,
        transfer_id: row.transfer_id?.toString?.() ?? row.transfer_id,
        from_branch_id: row.from_branch_id?.toString?.() ?? row.from_branch_id,
        to_branch_id: row.to_branch_id?.toString?.() ?? row.to_branch_id,
        order_id: row.order_id?.toString?.() ?? row.order_id,
        created_by: row.created_by?.toString?.() ?? row.created_by,
        approved_by: row.approved_by?.toString?.() ?? row.approved_by,
        quantity: row.quantity == null ? null : parseInt(row.quantity, 10),
      };
    });

    res.status(200).json(processedRows);
  } catch (error) {
    console.error('Error fetching transfers:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// Endpoint untuk membuat transfer barang baru
app.post('/transfers', async (req, res) => {
  try {
    const {
      from_branch_id,
      to_branch_id,
      item_name,
      quantity,
      notes: bodyNotes,
      order_id,
      created_by,
      source_type,
      courier: bodyCourier,
    } = req.body;

    if (!from_branch_id || !to_branch_id || !item_name || !quantity) {
      return res.status(400).json({ error: 'from_branch_id, to_branch_id, item_name, and quantity are required' });
    }

    const normalizedSourceType = source_type === 'buyback' ? 'buyback' : 'stok';

    async function hasTransfersColumn(columnName) {
      try {
        const r = await db.query(
          `
            SELECT 1
            FROM information_schema.columns
            WHERE table_schema = 'public'
              AND table_name = 'transfers'
              AND column_name = $1
            LIMIT 1
          `,
          [columnName]
        );
        return r.rows.length > 0;
      } catch (_) {
        return false;
      }
    }

    const [hasSourceTypeCol, hasCourierCol] = await Promise.all([
      hasTransfersColumn('source_type'),
      hasTransfersColumn('courier'),
    ]);

    const trimmedCourier =
      bodyCourier == null || String(bodyCourier).trim() === ''
        ? ''
        : String(bodyCourier).trim();
    // No `courier` column yet: persist kurir in notes (common when source_type migration ran but courier did not)
    let notes = bodyNotes;
    if (!hasCourierCol && trimmedCourier) {
      const n = bodyNotes == null || String(bodyNotes).trim() === '' ? '' : String(bodyNotes);
      notes = n ? `Kurir: ${trimmedCourier}\n${n}` : `Kurir: ${trimmedCourier}`;
    }

    let insertQuery;
    let params;

    if (hasSourceTypeCol && hasCourierCol) {
      insertQuery = `
        INSERT INTO transfers (
          from_branch_id, to_branch_id, item_name, quantity,
          source_type, courier, notes, order_id, created_by, status
        )
        VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, 'pending')
        RETURNING *
      `;
      params = [
        from_branch_id,
        to_branch_id,
        item_name,
        quantity,
        normalizedSourceType,
        trimmedCourier || null,
        notes,
        order_id,
        created_by,
      ];
    } else if (hasSourceTypeCol && !hasCourierCol) {
      insertQuery = `
        INSERT INTO transfers (
          from_branch_id, to_branch_id, item_name, quantity,
          source_type, notes, order_id, created_by, status
        )
        VALUES ($1, $2, $3, $4, $5, $6, $7, $8, 'pending')
        RETURNING *
      `;
      params = [
        from_branch_id,
        to_branch_id,
        item_name,
        quantity,
        normalizedSourceType,
        notes,
        order_id,
        created_by,
      ];
    } else if (!hasSourceTypeCol && hasCourierCol) {
      insertQuery = `
        INSERT INTO transfers (
          from_branch_id, to_branch_id, item_name, quantity,
          courier, notes, order_id, created_by, status
        )
        VALUES ($1, $2, $3, $4, $5, $6, $7, $8, 'pending')
        RETURNING *
      `;
      params = [
        from_branch_id,
        to_branch_id,
        item_name,
        quantity,
        trimmedCourier || null,
        notes,
        order_id,
        created_by,
      ];
    } else {
      insertQuery = `
        INSERT INTO transfers (
          from_branch_id, to_branch_id, item_name, quantity,
          notes, order_id, created_by, status
        )
        VALUES ($1, $2, $3, $4, $5, $6, $7, 'pending')
        RETURNING *
      `;
      params = [
        from_branch_id,
        to_branch_id,
        item_name,
        quantity,
        notes,
        order_id,
        created_by,
      ];
    }

    const result = await db.query(insertQuery, params);
    res.status(201).json(result.rows[0]);
  } catch (error) {
    console.error('Error creating transfer:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// Endpoint untuk update status transfer
app.put('/transfers/:id', async (req, res) => {
  try {
    const { id } = req.params;
    const { status, approved_by } = req.body;

    if (!status) {
      return res.status(400).json({ error: 'status is required' });
    }

    const approverUserId =
      approved_by ??
      (req.user?.user_id ? parseInt(req.user.user_id, 10) : null);

    const client = await db.getClient();
    try {
      await client.query('BEGIN');

      const transferRes = await client.query(
        `
          SELECT *
          FROM transfers
          WHERE transfer_id = $1
          FOR UPDATE
        `,
        [id]
      );

      if (transferRes.rows.length === 0) {
        await client.query('ROLLBACK');
        return res.status(404).json({ error: 'Transfer not found' });
      }

      const transfer = transferRes.rows[0];
      const prevStatus = transfer.status;

      // Update transfer status first (idempotent friendly)
      const updateRes = await client.query(
        `
          UPDATE transfers
          SET status = $1, approved_by = $2, updated_at = CURRENT_TIMESTAMP
          WHERE transfer_id = $3
          RETURNING *
        `,
        [status, approverUserId, id]
      );

      // Apply stock movement only once when transitioning into "completed"
      if (status === 'completed' && prevStatus !== 'completed') {
        const fromBranchId = transfer.from_branch_id;
        const toBranchId = transfer.to_branch_id;
        const qty = parseInt(transfer.quantity, 10);
        const itemName = String(transfer.item_name ?? '').trim();

        // Find source item: exact `name` first, then "KODE - label" by kode_produk (see parseKodeProdukFromTransferItemLabel).
        let sourceItemRes = await client.query(
          `
            SELECT *
            FROM items
            WHERE branch_id = $1 AND name = $2
            ORDER BY updated_at DESC
            LIMIT 1
            FOR UPDATE
          `,
          [fromBranchId, itemName]
        );

        if (sourceItemRes.rows.length === 0) {
          const kode = parseKodeProdukFromTransferItemLabel(itemName);
          if (kode) {
            sourceItemRes = await client.query(
              `
                SELECT *
                FROM items
                WHERE branch_id = $1 AND kode_produk = $2
                ORDER BY updated_at DESC
                LIMIT 1
                FOR UPDATE
              `,
              [fromBranchId, kode]
            );
          }
        }

        if (sourceItemRes.rows.length === 0) {
          throw new Error(
            `Source item not found in branch ${fromBranchId} for name "${itemName}"`
          );
        }

        const sourceItem = sourceItemRes.rows[0];
        const sourcePrevStock = parseInt(sourceItem.quantity, 10);
        const sourceNextStock = sourcePrevStock - qty;

        if (sourceNextStock < 0) {
          return res.status(400).json({
            error: 'Insufficient stock in source branch',
            detail: `Stock ${sourcePrevStock} < transfer quantity ${qty}`,
          });
        }

        // Decrease stock in source branch
        await client.query(
          `
            UPDATE items
            SET quantity = $1, updated_at = CURRENT_TIMESTAMP
            WHERE item_id = $2
          `,
          [sourceNextStock, sourceItem.item_id]
        );

        // Upsert destination WITHOUT relying on a unique constraint.
        // Update by (branch_id, kode_produk) to handle potential duplicates.
        let destItemId;
        let destPrevStock;
        let destCurrentStock;

        const destUpdateRes = await client.query(
          `
            UPDATE items
            SET quantity = quantity + $1,
                status = 'ready',
                updated_at = CURRENT_TIMESTAMP
            WHERE branch_id = $2 AND kode_produk = $3
            RETURNING item_id, quantity
          `,
          [qty, toBranchId, sourceItem.kode_produk]
        );

        if (destUpdateRes.rows.length > 0) {
          // If duplicates exist, we just pick the first returned row for mutation logging.
          // All matching rows already had status forced to 'ready'.
          destItemId = destUpdateRes.rows[0].item_id;
          destCurrentStock = parseInt(destUpdateRes.rows[0].quantity, 10);
          destPrevStock = destCurrentStock - qty;
        } else {
          destPrevStock = 0;
          destCurrentStock = qty;

          const destInsertRes = await client.query(
            `
              INSERT INTO items (
                branch_id,
                kode_produk,
                kategori,
                jenis,
                tipe,
                name,
                material,
                purity,
                weight,
                quantity,
                status,
                source,
                metadata,
                created_at,
                updated_at
              )
              VALUES (
                $1, $2, $3, $4, $5,
                $6, $7, $8, $9,
                $10, $11, $12, $13,
                CURRENT_TIMESTAMP, CURRENT_TIMESTAMP
              )
              RETURNING item_id
            `,
            [
              toBranchId,
              sourceItem.kode_produk,
              sourceItem.kategori,
              sourceItem.jenis,
              sourceItem.tipe,
              sourceItem.name,
              sourceItem.material,
              sourceItem.purity,
              sourceItem.weight,
              qty,
              'ready',
              'transfer',
              sourceItem.metadata,
            ]
          );

          destItemId = destInsertRes.rows[0].item_id;
        }

        // Record stock mutation for source (out)
        await client.query(
          `
            INSERT INTO stock_mutations (
              item_id, branch_id, type, quantity, previous_stock, current_stock,
              notes, reference_id, reference_type, created_by
            )
            VALUES ($1, $2, 'transfer', $3, $4, $5, $6, $7, 'transfer', $8)
          `,
          [
            sourceItem.item_id,
            fromBranchId,
            -qty,
            sourcePrevStock,
            sourceNextStock,
            `Transfer keluar ke branch ${toBranchId}`,
            transfer.transfer_id,
            approverUserId,
          ]
        );

        // Record stock mutation for destination (in)
        await client.query(
          `
            INSERT INTO stock_mutations (
              item_id, branch_id, type, quantity, previous_stock, current_stock,
              notes, reference_id, reference_type, created_by
            )
            VALUES ($1, $2, 'transfer', $3, $4, $5, $6, $7, 'transfer', $8)
          `,
          [
            destItemId,
            toBranchId,
            qty,
            destPrevStock,
            destCurrentStock,
            `Transfer masuk dari branch ${fromBranchId}`,
            transfer.transfer_id,
            approverUserId,
          ]
        );
      }

      await client.query('COMMIT');
      res.status(200).json(updateRes.rows[0]);
    } catch (txError) {
      await client.query('ROLLBACK');
      console.error('Error updating transfer (tx):', txError);
      res.status(500).json({ error: 'Internal server error', detail: txError.message });
    } finally {
      client.release();
    }
  } catch (error) {
    console.error('Error updating transfer:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// Endpoint untuk mendapatkan data mutasi stok (admin_toko)
app.get('/stock-mutations', async (req, res) => {
  try {
    const { branch_id, type, limit = 50, offset = 0 } = req.query;

    let query = `
      SELECT
        sm.*,
        i.name as item_name,
        i.material,
        i.purity,
        b.name as branch_name,
        u.username as created_by_name
      FROM stock_mutations sm
      LEFT JOIN items i ON sm.item_id = i.item_id
      LEFT JOIN branches b ON sm.branch_id = b.branch_id
      LEFT JOIN users u ON sm.created_by = u.user_id
      WHERE 1=1
    `;

    const params = [];
    let paramIndex = 1;

    if (branch_id) {
      query += ` AND sm.branch_id = $${paramIndex}`;
      params.push(branch_id);
      paramIndex++;
    }

    if (type) {
      query += ` AND sm.type = $${paramIndex}`;
      params.push(type);
      paramIndex++;
    }

    query += ` ORDER BY sm.created_at DESC LIMIT $${paramIndex} OFFSET $${paramIndex + 1}`;
    params.push(limit, offset);

    const result = await db.query(query, params);
    res.status(200).json(result.rows);
  } catch (error) {
    console.error('Error fetching stock mutations:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// Endpoint untuk mendapatkan data karyawan (admin_toko)
app.get('/employees', async (req, res) => {
  try {
    const { branch_id, role, status } = req.query;

    let query = `
      SELECT
        u.user_id,
        u.username,
        u.status,
        ubr.role,
        ubr.is_primary,
        b.name as branch_name,
        u.created_at
      FROM users u
      JOIN user_branch_roles ubr ON u.user_id = ubr.user_id
      LEFT JOIN branches b ON ubr.branch_id = b.branch_id
      WHERE 1=1
    `;

    const params = [];
    let paramIndex = 1;

    if (branch_id) {
      query += ` AND ubr.branch_id = $${paramIndex}`;
      params.push(branch_id);
      paramIndex++;
    }

    if (role) {
      query += ` AND ubr.role = $${paramIndex}`;
      params.push(role);
      paramIndex++;
    }

    if (status) {
      query += ` AND u.status = $${paramIndex}`;
      params.push(status);
      paramIndex++;
    }

    query += ` ORDER BY u.username ASC`;

    const result = await db.query(query, params);
    res.status(200).json(result.rows);
  } catch (error) {
    console.error('Error fetching employees:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// Endpoint untuk menambah karyawan baru
app.post('/employees', async (req, res) => {
  try {
    const { username, password, role, branch_id, is_primary = false } = req.body;

    if (!username || !password || !role || !branch_id) {
      return res.status(400).json({ error: 'username, password, role, and branch_id are required' });
    }

    // Hash password
    const saltRounds = 10;
    const hashedPassword = await bcrypt.hash(password, saltRounds);

    // Insert user
    const userQuery = `
      INSERT INTO users (username, password_hash, status)
      VALUES ($1, $2, 'active')
      RETURNING user_id
    `;

    const userResult = await db.query(userQuery, [username, hashedPassword]);
    const userId = userResult.rows[0].user_id;

    // Insert user_branch_role
    const roleQuery = `
      INSERT INTO user_branch_roles (user_id, branch_id, role, is_primary)
      VALUES ($1, $2, $3, $4)
    `;

    await db.query(roleQuery, [userId, branch_id, role, is_primary]);

    res.status(201).json({ message: 'Employee created successfully', user_id: userId });
  } catch (error) {
    console.error('Error creating employee:', error);
    if (error.code === '23505') { // Unique constraint violation
      res.status(400).json({ error: 'Username already exists' });
    } else {
      res.status(500).json({ error: 'Internal server error' });
    }
  }
});

// Endpoint untuk update karyawan
app.put('/employees/:id', async (req, res) => {
  try {
    const { id } = req.params;
    const { username, role, status, is_primary } = req.body;

    // Update user
    if (username || status) {
      let userQuery = 'UPDATE users SET';
      const userParams = [];
      let userParamIndex = 1;

      if (username) {
        userQuery += ` username = $${userParamIndex}`;
        userParams.push(username);
        userParamIndex++;
      }

      if (status) {
        if (userParamIndex > 1) userQuery += ',';
        userQuery += ` status = $${userParamIndex}`;
        userParams.push(status);
        userParamIndex++;
      }

      userQuery += `, updated_at = CURRENT_TIMESTAMP WHERE user_id = $${userParamIndex}`;
      userParams.push(id);

      await db.query(userQuery, userParams);
    }

    // Update role
    if (role || is_primary !== undefined) {
      let roleQuery = 'UPDATE user_branch_roles SET';
      const roleParams = [];
      let roleParamIndex = 1;

      if (role) {
        roleQuery += ` role = $${roleParamIndex}`;
        roleParams.push(role);
        roleParamIndex++;
      }

      if (is_primary !== undefined) {
        if (roleParamIndex > 1) roleQuery += ',';
        roleQuery += ` is_primary = $${roleParamIndex}`;
        roleParams.push(is_primary);
        roleParamIndex++;
      }

      roleQuery += ` WHERE user_id = $${roleParamIndex}`;
      roleParams.push(id);

      await db.query(roleQuery, roleParams);
    }

    res.status(200).json({ message: 'Employee updated successfully' });
  } catch (error) {
    console.error('Error updating employee:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// Endpoint untuk menghapus karyawan
app.delete('/employees/:id', async (req, res) => {
  try {
    const { id } = req.params;

    // Delete user_branch_roles first (due to foreign key constraint)
    await db.query('DELETE FROM user_branch_roles WHERE user_id = $1', [id]);

    // Delete user
    const result = await db.query('DELETE FROM users WHERE user_id = $1', [id]);

    if (result.rowCount === 0) {
      return res.status(404).json({ error: 'Employee not found' });
    }

    res.status(200).json({ message: 'Employee deleted successfully' });
  } catch (error) {
    console.error('Error deleting employee:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// Endpoint untuk mendapatkan order yang perlu dibayar (kasir)
// Endpoint untuk mendapatkan summary pembayaran harian
app.get('/payments/daily', async (req, res) => {
  try {
    const { date, branch_id } = req.query;

    if (!date || !branch_id) {
      return res.status(400).json({ error: 'date and branch_id are required' });
    }

    // Parse date untuk mendapatkan range hari ini
    const startDate = new Date(date);
    const endDate = new Date(date);
    endDate.setDate(endDate.getDate() + 1);

    // Query untuk summary pembayaran harian
    const summaryQuery = `
      SELECT
        COUNT(*) as total_transactions,
        SUM(amount) as total_amount,
        method,
        COUNT(*) as method_count
      FROM payments p
      JOIN orders o ON p.order_id = o.order_id
      WHERE o.branch_id = $1
        AND p.payment_date >= $2
        AND p.payment_date < $3
        AND p.status = 'completed'
      GROUP BY method
      ORDER BY total_amount DESC
    `;

    const summaryResult = await db.query(summaryQuery, [branch_id, startDate.toISOString(), endDate.toISOString()]);

    // Query untuk detail transaksi
    const detailQuery = `
      SELECT
        p.payment_id,
        p.order_id,
        p.amount,
        p.method,
        p.payment_date,
        COALESCE(STRING_AGG(oi.nama_item, ', '), 'Unknown Item') as nama_item,
        c.name as customer_name
      FROM payments p
      JOIN orders o ON p.order_id = o.order_id
      LEFT JOIN customers c ON o.customer_id = c.customer_id
      LEFT JOIN order_items oi ON o.order_id = oi.order_id
      WHERE o.branch_id = $1
        AND p.payment_date >= $2
        AND p.payment_date < $3
        AND p.status = 'completed'
      GROUP BY p.payment_id, p.order_id, p.amount, p.method, p.payment_date, c.name
      ORDER BY p.payment_date DESC
    `;

    const detailResult = await db.query(detailQuery, [branch_id, startDate.toISOString(), endDate.toISOString()]);

    // Hitung total keseluruhan
    const totalAmount = summaryResult.rows.reduce((sum, row) => sum + parseFloat(row.total_amount || 0), 0);
    const totalTransactions = summaryResult.rows.reduce((sum, row) => sum + parseInt(row.total_transactions || 0), 0);

    // Format payment methods sebagai object
    const paymentMethods = {};
    summaryResult.rows.forEach(row => {
      paymentMethods[row.method] = parseFloat(row.total_amount || 0);
    });

    res.status(200).json({
      summary: {
        total_amount: totalAmount,
        total_transactions: totalTransactions,
        payment_methods: paymentMethods,
        by_method: summaryResult.rows.map(row => ({
          method: row.method,
          total_amount: parseFloat(row.total_amount || 0),
          method_count: parseInt(row.method_count || 0),
        })),
      },
      transactions: detailResult.rows.map(row => ({
        ...row,
        timestamp: row.payment_date, // backward compatibility for clients expecting `timestamp`
      })),
    });
  } catch (error) {
    console.error('Error fetching daily payments:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// Endpoint untuk menguji koneksi database
app.get('/test-db', async (req, res) => {
  try {
    const result = await db.query('SELECT NOW()');
    res.status(200).json({ message: 'Database connected successfully', time: result.rows[0].now });
  } catch (error) {
    console.error('Database connection error:', error);
    res.status(500).json({ error: 'Database connection failed' });
  }
});

// Gunakan route customers
app.use('/api', customersRoute);
// Integrate new API routes
app.use('/api', apiRoutes); // Integrate new API routes
// Integrate dashboard and orders routes
app.use('/api', dashboardOrdersRoute);
// Integrate branches routes
app.use('/api', branchesRoute);
// User info route
app.use('/api', userInfoRoute);

// Workshop API endpoints
app.get("/api/workshop/work-queue", async (req, res) => {
  try {
    const branchId = req.query.branch_id;

    if (!branchId) {
      return res.status(400).json({ error: "branch_id is required" });
    }

    const result = await db.query("SELECT * FROM orders WHERE branch_id = $1 AND status IN ('in_workshop', 'custom_work') ORDER BY created_at ASC", [branchId]);
    res.status(200).json(result.rows);
  } catch (error) {
    console.error("Error fetching work queue:", error);
    res.status(500).json({ error: "Internal server error" });
  }
});

app.get("/api/workshop/material-stock", async (req, res) => {
  try {
    const { branch_id } = req.query;
    console.log("Material stock request for branch_id:", branch_id, typeof branch_id);

    // Get material stock for workshop
    const result = await db.query(`
      SELECT
        item_id,
        name,
        material,
        purity,
        kategori,
        weight,
        quantity,
        status,
        COALESCE(metadata->>'location', 'Rak Umum') as location,
        COALESCE(metadata->>'min_stock', '0') as min_stock,
        COALESCE(metadata->>'supplier', 'N/A') as supplier,
        COALESCE(metadata->>'price_per_unit', '0') as price_per_unit,
        updated_at
      FROM items
      WHERE branch_id = $1
        AND stock_type = 'non_inventory'
        AND status IN ('ready', 'available', 'sold')
      ORDER BY material, name
    `, [branch_id]);

    console.log("Query result rows:", result.rows.length);
    console.log("First row sample:", result.rows[0]);

    // Convert BigInt and other data types for JSON serialization
    const processedRows = result.rows.map(row => ({
      item_id: row.item_id.toString(),
      name: row.name,
      material: row.material,
      purity: row.purity,
      kategori: row.kategori,
      weight: parseFloat(row.weight || 0),
      quantity: parseInt(row.quantity || 0),
      status: row.status,
      location: row.location,
      min_stock: parseInt(row.min_stock || 0),
      supplier: row.supplier,
      price_per_unit: parseFloat(row.price_per_unit || 0),
      updated_at: row.updated_at
    }));

    const jsonResponse = JSON.stringify(processedRows);
    console.log("JSON length:", jsonResponse.length);

    res.status(200).json(processedRows);
  } catch (error) {
    console.error("Error fetching material stock:", error);
    console.error("Error stack:", error.stack);
    res.status(500).json({ error: "Internal server error", details: error.message });
  }
});

app.get("/api/workshop/dashboard", async (req, res) => {
  try {
    const { branch_id, user_id } = req.query;

    // Get workshop statistics (consistent with other role dashboards)
    const statsResult = await db.query(`
      SELECT
        COUNT(CASE WHEN status IN ('in_workshop', 'repairing', 'polishing', 'custom_work') THEN 1 END) as pending_orders,
        COUNT(CASE WHEN status IN ('repairing', 'polishing') THEN 1 END) as in_progress_orders,
        COUNT(CASE WHEN status IN ('completed', 'delivered') THEN 1 END) as completed_orders
      FROM orders
      WHERE branch_id = $1
        AND order_type IN ('service', 'custom')
        AND DATE(created_at) = CURRENT_DATE
    `, [branch_id]);

    const stats = statsResult.rows[0];

    // Get recent orders
    const recentOrdersResult = await db.query(`
      SELECT
        o.order_id,
        o.order_type,
        o.status,
        o.created_at,
        i.name as item_name,
        c.name as customer_name
      FROM orders o
      LEFT JOIN items i ON o.item_id = i.item_id
      LEFT JOIN customers c ON o.customer_id = c.customer_id
      WHERE o.branch_id = $1
        AND o.order_type IN ('service', 'custom')
      ORDER BY o.created_at DESC
      LIMIT 5
    `, [branch_id]);

    // Get technician count (simplified - count users with technician role in this branch)
    const technicianResult = await db.query(`
      SELECT COUNT(*) as total_technicians
      FROM user_branch_roles ubr
      JOIN users u ON ubr.user_id = u.user_id
      WHERE ubr.branch_id = $1 AND ubr.role = 'tukang'
    `, [branch_id]);

    const technicianCount = technicianResult.rows[0]?.total_technicians || 0;

    const response = {
      pending_orders: parseInt(stats.pending_orders) || 0,
      in_progress_orders: parseInt(stats.in_progress_orders) || 0,
      completed_orders: parseInt(stats.completed_orders) || 0,
      total_technicians: technicianCount,
      active_technicians: technicianCount, // Simplified
      recent_orders: recentOrdersResult.rows,
      last_updated: new Date().toISOString(),
    };

    res.status(200).json(response);
  } catch (error) {
    console.error("Error fetching workshop dashboard:", error);
    res.status(500).json({ error: "Internal server error" });
  }
});

app.get("/api/workshop/reports", async (req, res) => {
  try {
    const { branch_id, period = "month" } = req.query;

    // Calculate date range based on period
    let dateFilter = "";
    if (period === "month") {
      dateFilter = "AND o.created_at >= DATE_TRUNC(\"month\", CURRENT_DATE)";
    } else if (period === "week") {
      dateFilter = "AND o.created_at >= DATE_TRUNC(\"week\", CURRENT_DATE)";
    } else if (period === "year") {
      dateFilter = "AND o.created_at >= DATE_TRUNC(\"year\", CURRENT_DATE)";
    }

    // Get order statistics
    const orderStats = await db.query(`
      SELECT
        COUNT(*) as total_orders,
        COUNT(CASE WHEN status IN ('completed', 'delivered') THEN 1 END) as completed_orders,
        COUNT(CASE WHEN status IN ('in_workshop', 'repairing', 'polishing', 'custom_work') THEN 1 END) as pending_orders,
        AVG(CASE WHEN status IN ('completed', 'delivered') AND updated_at - created_at < interval '7 days'
                 THEN EXTRACT(EPOCH FROM (updated_at - created_at))/3600 END) as avg_completion_hours
      FROM orders o
      WHERE branch_id = $1 ${dateFilter}
    `, [branch_id]);

    // Get technician performance
    const technicianStats = await db.query(`
      SELECT
        COALESCE(o.metadata->>"assigned_technician", "Unassigned") as technician,
        COUNT(*) as orders_assigned,
        COUNT(CASE WHEN o.status IN ('completed', 'delivered') THEN 1 END) as orders_completed,
        AVG(CASE WHEN o.status IN ('completed', 'delivered')
                 THEN EXTRACT(EPOCH FROM (o.updated_at - o.created_at))/3600 END) as avg_time_hours
      FROM orders o
      WHERE branch_id = $1 ${dateFilter}
      GROUP BY COALESCE(o.metadata->>"assigned_technician", "Unassigned")
    `, [branch_id]);

    // Get material usage
    const materialStats = await db.query(`
      SELECT
        i.material,
        COUNT(*) as usage_count,
        SUM(i.weight) as total_weight_used
      FROM orders o
      JOIN items i ON o.item_id = i.item_id
      WHERE o.branch_id = $1 ${dateFilter}
        AND o.status IN ("completed", "delivered")
      GROUP BY i.material
      ORDER BY total_weight_used DESC
    `, [branch_id]);

    // Get financial summary (simplified)
    const financialStats = await db.query(`
      SELECT
        SUM(CASE WHEN order_type = 'jual' THEN COALESCE((o.metadata->>"selling_price")::numeric, 0) ELSE 0 END) as sales_revenue,
        SUM(CASE WHEN order_type = 'buyback' THEN COALESCE((o.metadata->>"buyback_price")::numeric, 0) ELSE 0 END) as buyback_revenue,
        SUM(COALESCE((o.metadata->>"material_cost")::numeric, 0)) as material_cost,
        SUM(COALESCE((o.metadata->>"labor_cost")::numeric, 0)) as labor_cost
      FROM orders o
      WHERE branch_id = $1 ${dateFilter}
    `, [branch_id]);

    const stats = orderStats.rows[0] || {};
    const financial = financialStats.rows[0] || {};

    res.status(200).json({
      period: period,
      order_summary: {
        total_orders: parseInt(stats.total_orders || 0),
        completed_orders: parseInt(stats.completed_orders || 0),
        pending_orders: parseInt(stats.pending_orders || 0),
        avg_completion_time: `${Math.round((stats.avg_completion_hours || 0) * 10) / 10} jam`
      },
      technician_performance: technicianStats.rows,
      material_usage: materialStats.rows,
      financial_summary: {
        total_revenue: parseFloat(financial.sales_revenue || 0) + parseFloat(financial.buyback_revenue || 0),
        total_cost: parseFloat(financial.material_cost || 0) + parseFloat(financial.labor_cost || 0),
        net_profit: (parseFloat(financial.sales_revenue || 0) + parseFloat(financial.buyback_revenue || 0)) -
          (parseFloat(financial.material_cost || 0) + parseFloat(financial.labor_cost || 0))
      }
    });
  } catch (error) {
    console.error("Error fetching workshop reports:", error);
    res.status(500).json({ error: "Internal server error" });
  }
});

app.post("/api/workshop/update-progress", async (req, res) => {
  try {
    const { order_id, status, technician_id, notes } = req.body;

    await db.query(`
      UPDATE orders
      SET status = $1, updated_at = NOW(),
          metadata = metadata || $2
      WHERE order_id = $3
    `, [status, JSON.stringify({
      "last_updated_by": technician_id,
      "last_update_notes": notes,
      "updated_at": new Date().toISOString()
    }), order_id]);

    res.status(200).json({ success: true, message: "Progress updated successfully" });
  } catch (error) {
    console.error("Error updating work progress:", error);
    res.status(500).json({ error: "Internal server error" });
  }
});

app.post("/api/workshop/update-stock", async (req, res) => {
  try {
    const { item_id, quantity, technician_id, notes } = req.body;

    await db.query(`
      UPDATE items
      SET quantity = $1, updated_at = NOW(),
          metadata = metadata || $2
      WHERE item_id = $3
    `, [quantity, JSON.stringify({
      "last_updated_by": technician_id,
      "last_update_notes": notes,
      "updated_at": new Date().toISOString()
    }), item_id]);

    res.status(200).json({ success: true, message: "Stock updated successfully" });
  } catch (error) {
    console.error("Error updating material stock:", error);
    res.status(500).json({ error: "Internal server error" });
  }
});

app.get("/api/workshop/work-history", async (req, res) => {
  try {
    const { technician_id, branch_id, period = 'all' } = req.query;

    let dateFilter = '';
    if (period === 'today') {
      dateFilter = "AND DATE(o.created_at) = CURRENT_DATE";
    } else if (period === 'week') {
      dateFilter = "AND o.created_at >= CURRENT_DATE - INTERVAL '7 days'";
    } else if (period === 'month') {
      dateFilter = "AND o.created_at >= CURRENT_DATE - INTERVAL '30 days'";
    }

    const result = await db.query(`
      SELECT
        o.order_id,
        o.status,
        o.created_at,
        o.updated_at,
        c.name as customer_name,
        c.phone,
        COALESCE(oi.nama_item, i.name) as item_name,
        COALESCE(oi.kategori, i.kategori) as item_type,
        COALESCE(oi.qty, 1) as ordered_quantity,
        COALESCE(oi.weight, i.weight, 0) as weight,
        COALESCE(oi.jenis, i.material) as material,
        CASE
          WHEN o.status = 'completed' THEN
            EXTRACT(EPOCH FROM (o.updated_at - o.created_at))/3600
          ELSE NULL
        END as duration_hours
      FROM orders o
      JOIN customers c ON o.customer_id = c.customer_id
      LEFT JOIN order_items oi ON o.order_id = oi.order_id
      LEFT JOIN items i ON oi.item_id = i.item_id
      WHERE o.branch_id = $1
        AND o.status IN ('completed', 'cancelled')
        ${dateFilter}
      ORDER BY o.updated_at DESC NULLS LAST, o.created_at DESC
      LIMIT 100
    `, [branch_id]);

    // Convert BigInt and other data types for JSON serialization
    const processedRows = result.rows.map(row => ({
      order_id: row.order_id.toString(),
      status: row.status,
      created_at: row.created_at,
      updated_at: row.updated_at,
      customer_name: row.customer_name,
      phone: row.phone,
      item_name: row.item_name,
      item_type: row.item_type,
      ordered_quantity: parseInt(row.ordered_quantity || 0),
      weight: parseFloat(row.weight || 0),
      material: row.material,
      duration_hours: row.duration_hours ? parseFloat(row.duration_hours) : null
    }));

    res.status(200).json(processedRows);
  } catch (error) {
    console.error("Error fetching work history:", error);
    res.status(500).json({ error: "Internal server error", details: error.message });
  }
});

app.get("/api/workshop/technician-reports", async (req, res) => {
  try {
    const { technician_id, branch_id, period = 'month' } = req.query;

    let dateFilter = '';
    if (period === 'week') {
      dateFilter = "AND o.created_at >= CURRENT_DATE - INTERVAL '7 days'";
    } else if (period === 'month') {
      dateFilter = "AND o.created_at >= CURRENT_DATE - INTERVAL '30 days'";
    } else if (period === 'quarter') {
      dateFilter = "AND o.created_at >= CURRENT_DATE - INTERVAL '90 days'";
    }

    // Get work statistics
    const workStats = await db.query(`
      SELECT
        COUNT(*) as total_orders,
        COUNT(CASE WHEN status = 'completed' THEN 1 END) as completed_orders,
        COUNT(CASE WHEN status = 'in_progress' THEN 1 END) as in_progress_orders,
        COUNT(CASE WHEN status = 'pending' THEN 1 END) as pending_orders,
        AVG(CASE
          WHEN status = 'completed' THEN
            EXTRACT(EPOCH FROM (updated_at - created_at))/3600
          ELSE NULL
        END) as avg_duration_hours,
        SUM(CASE
          WHEN status = 'completed' THEN
            EXTRACT(EPOCH FROM (updated_at - created_at))/3600
          ELSE NULL
        END) as total_work_hours
      FROM orders
      WHERE branch_id = $1
        AND order_type IN ('service', 'custom')
        ${dateFilter.replace('o.created_at', 'created_at')}
    `, [branch_id]);

    // Get material usage statistics
    const materialStats = await db.query(`
      SELECT
        i.material as material_type,
        SUM(i.weight) as total_weight_used,
        COUNT(*) as usage_count
      FROM orders o
      JOIN items i ON o.item_id = i.item_id
      WHERE o.branch_id = $1 AND o.status = 'completed'
        AND o.order_type IN ('service', 'custom')
        ${dateFilter}
      GROUP BY i.material
      ORDER BY total_weight_used DESC
    `, [branch_id]);

    // Get daily work distribution
    const dailyStats = await db.query(`
      SELECT
        DATE(o.created_at) as work_date,
        COUNT(*) as orders_count,
        COUNT(CASE WHEN o.status = 'completed' THEN 1 END) as completed_count
      FROM orders o
      WHERE o.branch_id = $1
        AND o.order_type IN ('service', 'custom')
        ${dateFilter}
      GROUP BY DATE(o.created_at)
      ORDER BY work_date DESC
      LIMIT 30
    `, [branch_id]);

    // Get work type distribution
    const workTypeStats = await db.query(`
      SELECT
        i.kategori as item_type,
        COUNT(*) as count,
        AVG(CASE
          WHEN o.status = 'completed' THEN
            EXTRACT(EPOCH FROM (o.updated_at - o.created_at))/3600
          ELSE NULL
        END) as avg_duration
      FROM orders o
      JOIN items i ON o.item_id = i.item_id
      WHERE o.branch_id = $1
        AND o.order_type IN ('service', 'custom')
        ${dateFilter}
      GROUP BY i.kategori
      ORDER BY count DESC
    `, [branch_id]);

    const stats = workStats.rows[0];
    const efficiency = stats.total_orders > 0 ? (stats.completed_orders / stats.total_orders * 100) : 0;
    const onTimeRate = stats.completed_orders > 0 ? (stats.completed_orders / stats.total_orders * 100) : 0;

    res.status(200).json({
      period: period,
      work_stats: {
        total_orders: parseInt(stats.total_orders) || 0,
        completed_orders: parseInt(stats.completed_orders) || 0,
        in_progress_orders: parseInt(stats.in_progress_orders) || 0,
        pending_orders: parseInt(stats.pending_orders) || 0,
        avg_duration_hours: parseFloat(stats.avg_duration_hours) || 0,
        total_work_hours: parseFloat(stats.total_work_hours) || 0,
        efficiency: Math.round(efficiency),
        on_time_rate: Math.round(onTimeRate)
      },
      material_usage: materialStats.rows,
      daily_distribution: dailyStats.rows,
      work_type_distribution: workTypeStats.rows
    });
  } catch (error) {
    console.error("Error fetching technician reports:", error);
    res.status(500).json({ error: "Internal server error" });
  }
});

// Technician Dashboard endpoint
app.get("/api/technician/dashboard", async (req, res) => {
  try {
    const { branch_id, user_id } = req.query;

    // Get technician-specific statistics (consistent with other role dashboards)
    const statsResult = await db.query(`
      SELECT
        COUNT(CASE WHEN status IN ('in_workshop', 'repairing', 'polishing', 'custom_work') THEN 1 END) as pending_work_orders,
        COUNT(CASE WHEN status IN ('repairing', 'polishing') THEN 1 END) as in_progress_work_orders,
        COUNT(CASE WHEN status IN ('completed', 'delivered') THEN 1 END) as completed_work_orders
      FROM orders
      WHERE branch_id = $1
        AND order_type IN ('service', 'custom')
        AND DATE(created_at) = CURRENT_DATE
    `, [branch_id]);

    const stats = statsResult.rows[0];

    // Get recent assignments for this technician
    const recentAssignmentsResult = await db.query(`
      SELECT
        o.order_id,
        o.order_type,
        o.status,
        o.created_at,
        i.name as item_name,
        c.name as customer_name
      FROM orders o
      LEFT JOIN items i ON o.item_id = i.item_id
      LEFT JOIN customers c ON o.customer_id = c.customer_id
      WHERE o.branch_id = $1
        AND o.order_type IN ('service', 'custom')
        AND o.status IN ('in_workshop', 'repairing', 'polishing', 'custom_work')
      ORDER BY o.created_at DESC
      LIMIT 5
    `, [branch_id]);

    const response = {
      pending_work_orders: parseInt(stats.pending_work_orders) || 0,
      in_progress_work_orders: parseInt(stats.in_progress_work_orders) || 0,
      completed_work_orders: parseInt(stats.completed_work_orders) || 0,
      recent_assignments: recentAssignmentsResult.rows,
      last_updated: new Date().toISOString(),
    };

    res.status(200).json(response);
  } catch (error) {
    console.error("Error fetching technician dashboard:", error);
    res.status(500).json({ error: "Internal server error" });
  }
});

// Get workshop orders for admin workshop
app.get('/workshop-orders', async (req, res) => {
  try {
    const { branch_id, status } = req.query;

    if (!branch_id) {
      return res.status(400).json({ error: 'branch_id is required' });
    }

    let query = `
      SELECT
        o.order_id,
        o.order_number,
        o.order_type,
        o.status,
        o.created_at,
        o.updated_at,
        c.name as customer_name,
        c.phone,
        COALESCE(oi.nama_item, i.name) as item_name,
        COALESCE(oi.qty, 1) as quantity,
        COALESCE(oi.weight, i.weight, 0) as weight,
        COALESCE(oi.jenis, i.material) as material
      FROM orders o
      JOIN customers c ON o.customer_id = c.customer_id
      LEFT JOIN order_items oi ON o.order_id = oi.order_id
      LEFT JOIN items i ON oi.item_id = i.item_id
      WHERE o.branch_id = $1
        AND o.order_type IN ('service', 'custom')
        AND o.status IN ('sent-to-workshop', 'in_workshop', 'repairing', 'polishing', 'custom_work', 'done_workshop', 'ready_for_pickup')
    `;

    let params = [branch_id];
    let conditions = [];

    if (status && status !== 'all') {
      if (status === 'pending') {
        conditions.push(`o.status IN ('sent-to-workshop', 'in_workshop')`);
      } else if (status === 'in_progress') {
        conditions.push(`o.status IN ('repairing', 'polishing', 'custom_work')`);
      } else if (status === 'completed') {
        conditions.push(`o.status IN ('done_workshop', 'ready_for_pickup')`);
      } else {
        conditions.push(`o.status = $${params.length + 1}`);
        params.push(status);
      }
    }

    if (conditions.length > 0) {
      query += ' AND ' + conditions.join(' AND ');
    }

    query += ' ORDER BY o.updated_at DESC, o.created_at DESC';

    const result = await db.query(query, params);

    // Convert BigInt and other data types for JSON serialization
    const processedRows = result.rows.map(row => ({
      order_id: row.order_id.toString(),
      order_number: row.order_number,
      order_type: row.order_type,
      status: row.status,
      created_at: row.created_at,
      updated_at: row.updated_at,
      customer_name: row.customer_name,
      phone: row.phone,
      item_name: row.item_name,
      quantity: parseInt(row.quantity || 1),
      weight: parseFloat(row.weight || 0),
      material: row.material
    }));

    res.status(200).json(processedRows);
  } catch (error) {
    console.error('Error fetching workshop orders:', error);
    res.status(500).json({ error: 'Internal server error', details: error.message });
  }
});

// Get technicians for admin workshop
app.get('/technicians', async (req, res) => {
  try {
    const { branch_id } = req.query;

    if (!branch_id) {
      return res.status(400).json({ error: 'branch_id is required' });
    }

    const result = await db.query(`
      SELECT
        u.user_id,
        u.username,
        u.status,
        u.created_at,
        u.updated_at,
        ubr.role,
        COUNT(o.order_id) as active_orders,
        COUNT(CASE WHEN o.status IN ('completed', 'delivered') THEN 1 END) as completed_orders_today
      FROM users u
      JOIN user_branch_roles ubr ON u.user_id = ubr.user_id
      LEFT JOIN orders o ON o.user_id = u.user_id
        AND o.branch_id = ubr.branch_id
        AND DATE(o.updated_at) = CURRENT_DATE
        AND o.status IN ('in_workshop', 'repairing', 'polishing', 'custom_work')
      WHERE ubr.branch_id = $1
        AND ubr.role = 'tukang'
        AND u.status = 'active'
      GROUP BY u.user_id, u.username, u.status, u.created_at, u.updated_at, ubr.role
      ORDER BY u.username
    `, [branch_id]);

    // Convert BigInt and other data types for JSON serialization
    const processedRows = result.rows.map(row => ({
      user_id: row.user_id.toString(),
      username: row.username,
      status: row.status,
      created_at: row.created_at,
      updated_at: row.updated_at,
      role: row.role,
      active_orders: parseInt(row.active_orders || 0),
      completed_orders_today: parseInt(row.completed_orders_today || 0)
    }));

    res.status(200).json(processedRows);
  } catch (error) {
    console.error('Error fetching technicians:', error);
    res.status(500).json({ error: 'Internal server error', details: error.message });
  }
});

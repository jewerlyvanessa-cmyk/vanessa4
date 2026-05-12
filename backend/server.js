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
const { createWsPresenceRegistry } = require('./websocket/presence_registry');
const { attachWebSocketServer } = require('./websocket/attach');
const { local: localStorage } = require('./storage/storage.service');
const customersRoute = require('./routes/customers'); // Import customers route
const apiRoutes = require('./api'); // Import new API routes
const dashboardOrdersRoute = require('./routes/dashboard_orders'); // Import dashboard orders route
const branchesRoute = require('./routes/branches'); // Import branches route
const userInfoRoute = require('./routes/userInfo');
const getOrdersDaily = require('./routes/orders_daily_handler');
const { registerWorkshopRoutes } = require('./routes/workshop');
const { registerTransfersRoutes } = require('./routes/transfers');
const { registerPaymentsCoreRoutes } = require('./routes/payments_core');
const { createHealthRouter } = require('./routes/health');
const {
  ordersHasMetadataColumn,
  ordersEstimateColumns,
  ordersHasPickupBranchColumn,
  orderVisibleAtWorkshopBranchSql,
} = require('./lib/orders_workshop_helpers');
const { handleBranchLogoGet } = require('./lib/branch_logo_http_lazy');
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

let _cachedOrderItemsPhotoColumn = null; // 'photo_produk' | 'photo_url' | null
async function getOrderItemsPhotoColumn(client) {
  if (_cachedOrderItemsPhotoColumn !== null) return _cachedOrderItemsPhotoColumn;
  try {
    const r = await client.query(
      `
        SELECT column_name
        FROM information_schema.columns
        WHERE table_schema = 'public'
          AND table_name = 'order_items'
          AND column_name IN ('photo_produk', 'photo_url')
      `,
      []
    );
    const cols = new Set(r.rows.map((x) => x.column_name));
    if (cols.has('photo_produk')) {
      _cachedOrderItemsPhotoColumn = 'photo_produk';
    } else if (cols.has('photo_url')) {
      _cachedOrderItemsPhotoColumn = 'photo_url';
    } else {
      _cachedOrderItemsPhotoColumn = null;
    }
  } catch (_) {
    _cachedOrderItemsPhotoColumn = null;
  }
  return _cachedOrderItemsPhotoColumn;
}

let _cachedItemConditionsColumns = null; // Set<string> | null
async function getItemConditionsColumns(client) {
  if (_cachedItemConditionsColumns !== null) return _cachedItemConditionsColumns;
  try {
    const r = await client.query(
      `
        SELECT column_name
        FROM information_schema.columns
        WHERE table_schema = 'public'
          AND table_name = 'item_conditions'
      `,
      []
    );
    _cachedItemConditionsColumns = new Set(r.rows.map((x) => x.column_name));
  } catch (_) {
    _cachedItemConditionsColumns = new Set();
  }
  return _cachedItemConditionsColumns;
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

async function _getOrdersJumlahColumnMode(client) {
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

let _cachedItemsCreatedByExists = null;
async function itemsHasCreatedByColumn() {
  if (_cachedItemsCreatedByExists !== null) return _cachedItemsCreatedByExists;
  try {
    const r = await db.query(
      `
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = 'public'
          AND table_name = 'items'
          AND column_name = 'created_by'
        LIMIT 1
      `,
      []
    );
    _cachedItemsCreatedByExists = r.rows.length > 0;
  } catch (_) {
    _cachedItemsCreatedByExists = false;
  }
  return _cachedItemsCreatedByExists;
}

const authRequired = authenticateToken(SECRET_KEY);

/** Di-set setelah `attachWebSocketServer`; dipakai GET /health. */
let wss = null;

/** Presence WebSocket (JWT); dipakai superadmin active-sessions + kick. */
const wsPresence = createWsPresenceRegistry(SECRET_KEY);

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

// Health checks (publik, tanpa JWT)
app.use(createHealthRouter({ db, getWss: () => wss }));

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
app.use('/store-operational', authRequired);
app.use('/payments', authRequired);
app.use('/transfers', authRequired);
app.use('/items', authRequired);
app.use('/item-conditions', authRequired);
app.use('/order-items', authRequired);
app.use('/stock-mutations', authRequired);
app.use('/stock-history', authRequired, requireRoles('superadmin', 'admin_toko', 'admin_workshop'));
app.use('/reports', authRequired, requireRoles('superadmin', 'manajer'));
app.use('/api', authRequired);
app.use(
  '/api/workshop',
  authRequired,
  requireRoles('superadmin', 'admin_workshop', 'tukang', 'manajer', 'stockist')
);

// Debug helper: inspect JWT payload (for troubleshooting role/branch issues)
app.get('/api/whoami', authRequired, (req, res) => {
  res.json({ user: req.user ?? null });
});

// Debug helper: sanity-check "Order Today" counts on server.
// Safe: requires auth; returns aggregate counts only.
app.get('/api/debug/order-today-sanity', authRequired, async (req, res) => {
  try {
    const tz =
      /^[\\w/-]+$/.test(String(process.env.BUSINESS_TIMEZONE || '').trim())
        ? String(process.env.BUSINESS_TIMEZONE).trim()
        : 'Asia/Jakarta';
    const bidRaw = String(req.query.branch_id ?? '').trim();
    const branchId = parseInt(bidRaw, 10);
    if (!Number.isFinite(branchId) || branchId <= 0) {
      return res.status(400).json({ error: 'branch_id is required' });
    }
    const datePat = /^\\d{4}-\\d{2}-\\d{2}$/;
    const dateKey = datePat.test(String(req.query.date ?? '').trim())
      ? String(req.query.date).trim()
      : new Intl.DateTimeFormat('en-CA', {
        timeZone: tz,
        year: 'numeric',
        month: '2-digit',
        day: '2-digit',
      }).format(new Date());

    const userId = parseInt(
      String(req.user?.user_id ?? req.user?.id ?? ''),
      10,
    );
    const role = String(req.user?.role ?? '').trim().toLowerCase();

    const q = `
      SELECT
        COUNT(*) FILTER (
          WHERE o.branch_id = $1
            AND (timezone('${tz}', o.created_at))::date = $2::date
        ) AS orders_created_today,
        COUNT(*) FILTER (
          WHERE o.branch_id = $1
            AND EXISTS (
              SELECT 1
              FROM payments p
              WHERE p.order_id = o.order_id
                AND p.status = 'completed'
                AND (timezone('${tz}', p.created_at))::date = $2::date
            )
        ) AS orders_paid_today,
        COUNT(*) FILTER (
          WHERE o.branch_id = $1
            AND (
              (timezone('${tz}', o.created_at))::date = $2::date
              OR EXISTS (
                SELECT 1
                FROM payments p
                WHERE p.order_id = o.order_id
                  AND p.status = 'completed'
                  AND (timezone('${tz}', p.created_at))::date = $2::date
              )
            )
        ) AS orders_today_union,
        COUNT(*) FILTER (
          WHERE o.branch_id = $1
            AND (
              (timezone('${tz}', o.created_at))::date = $2::date
              OR EXISTS (
                SELECT 1
                FROM payments p
                WHERE p.order_id = o.order_id
                  AND p.status = 'completed'
                  AND (timezone('${tz}', p.created_at))::date = $2::date
              )
            )
            AND o.user_id = $3
        ) AS orders_today_by_user,
        COUNT(*) FILTER (
          WHERE o.branch_id = $1
            AND (
              (timezone('${tz}', o.created_at))::date = $2::date
              OR EXISTS (
                SELECT 1
                FROM payments p
                WHERE p.order_id = o.order_id
                  AND p.status = 'completed'
                  AND (timezone('${tz}', p.created_at))::date = $2::date
              )
            )
            AND o.user_id IS NULL
        ) AS orders_today_user_null,
        MIN(o.created_at) FILTER (WHERE o.branch_id = $1) AS min_created_at_branch,
        MAX(o.created_at) FILTER (WHERE o.branch_id = $1) AS max_created_at_branch
      FROM orders o
    `;

    const r = await db.query(q, [
      branchId,
      dateKey,
      Number.isFinite(userId) ? userId : -1,
    ]);

    res.json({
      ok: true,
      tz,
      dateKey,
      branchId,
      auth: { role, userId: Number.isFinite(userId) ? userId : null },
      counts: r.rows?.[0] ?? null,
    });
  } catch (e) {
    console.error('debug/order-today-sanity error:', e);
    res.status(500).json({ error: 'Internal server error' });
  }
});

app.get('/api/admin/active-sessions', requireRoles('superadmin'), (req, res) => {
  res.json(wsPresence.getActivePresenceSnapshot());
});

// Superadmin: logout paksa semua koneksi Live (WebSocket) milik user — klien menerima force_logout.
app.post('/api/admin/active-sessions/:userId/kick', requireRoles('superadmin'), (req, res) => {
  try {
    const targetId = parseInt(String(req.params.userId), 10);
    if (!Number.isFinite(targetId)) {
      return res.status(400).json({ error: 'userId tidak valid' });
    }
    const adminId = parseInt(String(req.user?.user_id ?? req.user?.id ?? ''), 10);
    if (Number.isFinite(adminId) && adminId === targetId) {
      return res.status(400).json({
        error: 'Tidak dapat melogoutkan diri sendiri dari panel ini (gunakan logout).',
      });
    }
    const reasonRaw = req.body && req.body.reason != null ? String(req.body.reason) : '';
    const reason = reasonRaw.trim().slice(0, 500) || undefined;
    const { closed } = wsPresence.disconnectPresenceSessionsForUser(targetId, reason);
    res.json({ ok: true, closed, user_id: String(targetId) });
  } catch (error) {
    console.error('Error kicking active sessions:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

app.use(
  '/workshop-orders',
  authRequired,
  requireRoles('superadmin', 'admin_toko', 'admin_workshop', 'tukang', 'stockist', 'manajer')
);
app.use('/technicians', authRequired, requireRoles('superadmin', 'admin_workshop'));
app.use('/test-db', authRequired, requireRoles('superadmin'));
app.use(['/orders', '/payments', '/transfers', '/items', '/stock-history', '/stock-mutations', '/employees', '/branches', '/users', '/store-operational'], writeApiLimiter);

// Sample data
let orders = [];
let items = [];
let users = []; // eslint-disable-line no-unused-vars
let stockHistory = [];
// Legacy placeholder (sample data)
// eslint-disable-next-line no-unused-vars
let payments = [];

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

// CRUD untuk tabel orders
app.get('/orders', async (req, res) => {
  try {
    const { branch_id, status, order_number } = req.query;
    console.log('GET /orders called with query:', req.query);
    const itemsPhotoCol = await getItemsPhotoColumn(db);
    const orderItemsPhotoCol = await getOrderItemsPhotoColumn(db);
    const orderItemsPhotoSelect = orderItemsPhotoCol
      ? `oi.${orderItemsPhotoCol} as oi_photo_produk`
      : `NULL as oi_photo_produk`;
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
        ${orderItemsPhotoSelect},
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
        photo_produk: row.oi_photo_produk || row.item_photo_produk,
        material: row.material || row.item_material,
        purity: row.purity || row.item_purity,
        // Keep explicit fallbacks so clients can decide precedence
        item_material: row.item_material,
        item_purity: row.item_purity,
        kategori: row.kategori || row.item_kategori,
        jenis: row.jenis || row.item_jenis,
        tipe: row.tipe || row.item_tipe,
      })).filter(item => item.nama_item || item.item_id); // Filter out null items

      const custName =
        order.customer_name ||
        order.name ||
        null;
      const orderData = {
        order_id: order.order_id.toString(),
        order_number: order.order_number,
        order_type: order.order_type,
        status: order.status,
        customer_id:
          order.customer_id != null && order.customer_id !== undefined
            ? order.customer_id.toString()
            : null,
        customer_name: custName,
        customer_phone: order.customer_phone || order.phone || null,
        customer_address: order.customer_address || order.address || null,
        // Nama pada baris order (legacy / cadangan jika belum ada customers row)
        name: order.name ?? null,
        branch_id: order.branch_id.toString(),
        ...(order.pickup_branch_id != null && order.pickup_branch_id !== undefined
          ? { pickup_branch_id: String(order.pickup_branch_id) }
          : {}),
        user_id: order.user_id.toString(),
        total: parseFloat(order.total || 0),
        jumlah: parseFloat(order.jumlah || roundUpToNearest5000(order.total || 0) || 0),
        diskon: parseFloat(order.diskon || 0),
        mode: order.mode,
        created_at: order.created_at,
        updated_at: order.updated_at,
        items: items,
      };
      const parseOrderMetadataObject = (raw) => {
        if (raw == null || raw === '') return {};
        if (typeof raw === 'object' && !Array.isArray(raw)) return { ...raw };
        try {
          const p = JSON.parse(String(raw));
          return p && typeof p === 'object' && !Array.isArray(p) ? p : {};
        } catch (_) {
          return {};
        }
      };
      // Faktur / detail servis: GET tunggal sebelumnya hanya mengirim subset kolom — sertakan metadata & estimasi dari `o.*`.
      if (order.metadata !== undefined && order.metadata !== null) {
        orderData.metadata = order.metadata;
      }
      for (const k of [
        'estimate_amount',
        'estimate_due_at',
        'estimate_duration_text',
        'estimate_notes',
      ]) {
        if (order[k] !== undefined && order[k] !== null) {
          orderData[k] = order[k];
        }
      }
      // Selaraskan dengan payload POST /orders: field form servis/custom ada di metadata — salin ke root jika belum terisi.
      const metaObj = parseOrderMetadataObject(order.metadata);
      const metaRootKeys = [
        'kelengkapan',
        'keterangan',
        'estimasi_selesai',
        'estimasi_selesai_text',
        'jenis_service',
        'estimasi_waktu',
        'service_dp_amount',
        'spesifikasi',
      ];
      for (const mk of metaRootKeys) {
        const mv = metaObj[mk];
        if (mv == null || (typeof mv === 'string' && mv.trim() === '')) continue;
        const cur = orderData[mk];
        const curEmpty =
          cur == null ||
          (typeof cur === 'string' && cur.trim() === '');
        if (curEmpty) orderData[mk] = mv;
      }

      // Logo cabang untuk faktur (terutama GET by order_number / faktur ambil): payload order tidak punya join branches.
      try {
        const hasPb = await ordersHasPickupBranchColumn(db);
        const logoSql = hasPb
          ? `SELECT br.logo_url AS ob, pb.logo_url AS pb
             FROM orders o
             LEFT JOIN branches br ON br.branch_id = o.branch_id
             LEFT JOIN branches pb ON pb.branch_id = o.pickup_branch_id
             WHERE o.order_id = $1
             LIMIT 1`
          : `SELECT br.logo_url AS ob, NULL::text AS pb
             FROM orders o
             LEFT JOIN branches br ON br.branch_id = o.branch_id
             WHERE o.order_id = $1
             LIMIT 1`;
        const lr = await db.query(logoSql, [order.order_id]);
        if (lr.rows.length) {
          const ob = lr.rows[0].ob != null ? String(lr.rows[0].ob).trim() : '';
          const pb = lr.rows[0].pb != null ? String(lr.rows[0].pb).trim() : '';
          const ot = (order.order_type || '').toString().toLowerCase();
          let chosen = '';
          if (ot === 'service' || ot === 'custom') {
            chosen = pb || ob;
          } else {
            chosen = ob || pb;
          }
          if (chosen) {
            orderData.branch_logo_url = chosen;
            orderData.logo_url = chosen;
          }
        }
      } catch (e) {
        console.warn('GET /orders branch logo join skipped:', e.message);
      }

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

// Payment summary for a single order (used by Ambil Barang)
app.get('/orders/payment-summary', async (req, res) => {
  try {
    const orderIdRaw = (req.query.order_id ?? '').toString().trim();
    const orderId = parseInt(orderIdRaw, 10);
    if (!Number.isFinite(orderId) || orderId <= 0) {
      return res.status(400).json({ error: 'order_id harus berupa angka' });
    }

    const ordRes = await db.query(
      `SELECT order_id, order_type, status, total, branch_id
       FROM orders
       WHERE order_id = $1
       LIMIT 1`,
      [orderId]
    );
    if (ordRes.rows.length === 0) {
      return res.status(404).json({ error: 'Order tidak ditemukan' });
    }

    const total = parseFloat(ordRes.rows[0].total || 0);

    const sumRes = await db.query(
      `
        SELECT
          COALESCE(SUM(CASE WHEN status = 'pending' THEN COALESCE(amount, 0) ELSE 0 END), 0)::float8 AS dp_amount,
          COALESCE(SUM(CASE WHEN status = 'completed' THEN COALESCE(amount, 0) ELSE 0 END), 0)::float8 AS paid_completed_amount,
          COALESCE(SUM(CASE WHEN status IN ('pending','completed') THEN COALESCE(amount, 0) ELSE 0 END), 0)::float8 AS paid_amount
        FROM payments
        WHERE order_id = $1
      `,
      [orderId]
    );
    const row = sumRes.rows[0] || {};
    const dpAmount = parseFloat(row.dp_amount || 0);
    const paidAmount = parseFloat(row.paid_amount || 0);
    const remaining = Math.max(total - paidAmount, 0);

    return res.status(200).json({
      order_id: orderId,
      total,
      dp_amount: dpAmount,
      paid_amount: paidAmount,
      remaining_amount: remaining,
    });
  } catch (e) {
    console.error('Error fetching order payment summary:', e);
    return res.status(500).json({ error: 'Internal server error' });
  }
});

// Mark service/custom order as picked up (ambil barang)
app.post('/orders/pickup', async (req, res) => {
  const client = await db.getClient();
  try {
    const { order_id, order_number, branch_id, notes, photo_url } = req.body ?? {};

    const branchIdRaw = (branch_id ?? req.user?.branch_id ?? '').toString().trim();
    if (!branchIdRaw) {
      return res.status(400).json({ error: 'branch_id is required' });
    }
    const branchId = parseInt(branchIdRaw, 10);
    if (!Number.isFinite(branchId) || branchId <= 0) {
      return res.status(400).json({ error: 'branch_id must be a number' });
    }

    let orderId = order_id != null ? parseInt(order_id, 10) : null;
    const orderNumber = (order_number ?? '').toString().trim();
    if (!Number.isFinite(orderId) && !orderNumber) {
      return res.status(400).json({ error: 'order_id atau order_number wajib diisi' });
    }

    await client.query('BEGIN');

    const whereSql = Number.isFinite(orderId)
      ? 'o.order_id = $1'
      : 'o.order_number = $1';
    const whereVal = Number.isFinite(orderId) ? orderId : orderNumber;

    const hasPickupBranchCol = await ordersHasPickupBranchColumn(client);
    const hasMetadataCol = await ordersHasMetadataColumn(client);
    const selectParts = [
      'o.order_id',
      'o.order_number',
      'o.order_type',
      'o.status',
      'o.branch_id',
    ];
    if (hasPickupBranchCol) selectParts.push('o.pickup_branch_id');
    if (hasMetadataCol) selectParts.push('o.metadata');

    const ordRes = await client.query(
      `
        SELECT ${selectParts.join(', ')}
        FROM orders o
        WHERE ${whereSql}
        LIMIT 1
      `,
      [whereVal]
    );
    if (ordRes.rows.length === 0) {
      await client.query('ROLLBACK');
      return res.status(404).json({ error: 'Order tidak ditemukan' });
    }

    const ord = ordRes.rows[0];
    const ot = (ord.order_type ?? '').toString().trim().toLowerCase();
    if (ot !== 'service' && ot !== 'custom') {
      await client.query('ROLLBACK');
      return res.status(400).json({ error: 'Hanya order service/custom yang bisa diambil' });
    }
    const st = (ord.status ?? '').toString().trim().toLowerCase();

    // Sama dengan filter GET /workshop-orders: cabang order, pickup_branch_id, atau
    // metadata.service_workshop_branch_id (jsonb di DB — lebih andal daripada parse di Node).
    const branchOk = await orderVisibleAtWorkshopBranchSql(
      client,
      ord.order_id,
      branchId,
      hasPickupBranchCol,
      hasMetadataCol,
    );
    if (!branchOk) {
      await client.query('ROLLBACK');
      return res.status(403).json({ error: 'Order bukan milik branch ini' });
    }
    if (st !== 'ready_for_pickup' && st !== 'completed') {
      await client.query('ROLLBACK');
      return res.status(400).json({ error: 'Order belum siap diambil customer' });
    }

    const payRes = await client.query(
      `
        SELECT
          COALESCE(o.total, 0)::float8 AS total,
          COALESCE((
            SELECT SUM(COALESCE(p.amount, 0))::float8
            FROM payments p
            WHERE p.order_id = o.order_id
              AND p.status IN ('pending', 'completed')
          ), 0)::float8 AS paid_amount
        FROM orders o
        WHERE o.order_id = $1
        LIMIT 1
      `,
      [ord.order_id]
    );
    const total = parseFloat(payRes.rows[0]?.total || 0);
    const paidAmount = parseFloat(payRes.rows[0]?.paid_amount || 0);
    const remaining = Math.max(total - paidAmount, 0);
    const nextStatus = remaining > 0 ? 'pending' : 'completed';

    const pickedBy = req.user?.user_id ?? req.user?.id ?? null;
    await client.query(
      `
        UPDATE orders
        SET status = $1,
            picked_up_at = COALESCE(picked_up_at, NOW()),
            picked_up_by = $2,
            picked_up_notes = $3,
            picked_up_photo_url = $4,
            updated_at = NOW()
        WHERE order_id = $5
      `,
      [
        nextStatus,
        pickedBy,
        (notes ?? '').toString(),
        (photo_url ?? '').toString() || null,
        ord.order_id,
      ]
    );

    await client.query('COMMIT');
    sendNotificationToClients(`Order ${ord.order_id} (${ot}) telah diambil customer, status ${nextStatus}`);
    return res.status(200).json({
      message: 'Barang berhasil diambil',
      order_id: ord.order_id,
      order_number: ord.order_number,
      next_status: nextStatus,
      remaining_amount: remaining,
    });
  } catch (e) {
    try {
      await client.query('ROLLBACK');
    } catch (_) { }
    console.error('Error pickup order:', e);
    return res.status(500).json({ error: 'Internal server error' });
  } finally {
    try {
      client.release?.();
    } catch (_) { }
  }
});

/**
 * Cabang aktif di aplikasi bisa diganti (Switch Branch) tanpa JWT baru.
 * Jangan bandingkan hanya ke req.user.branch_id dari token — cek assignment DB.
 */
async function assertUserCanAccessStoreOperationalBranch(req, res, branchId) {
  const role = (req.user?.role ?? '').toString().trim().toLowerCase();
  if (role === 'superadmin') return true;

  const userId =
    req.user?.user_id != null ? parseInt(String(req.user.user_id), 10) : null;
  if (!Number.isFinite(userId) || userId <= 0) {
    res.status(401).json({ error: 'Unauthorized' });
    return false;
  }

  const check = await db.query(
    `SELECT 1 FROM user_branch_roles WHERE user_id = $1 AND branch_id = $2 LIMIT 1`,
    [userId, branchId]
  );
  if (check.rows.length === 0) {
    res.status(403).json({
      error: 'Tidak punya akses ke cabang ini',
      details:
        'Pastikan user punya assignment di user_branch_roles untuk branch_id yang dipilih.',
    });
    return false;
  }
  return true;
}

// Pengeluaran operasional toko (Keuangan Toko — kasir)
app.get('/store-operational', async (req, res) => {
  try {
    const branchIdRaw = (req.query.branch_id ?? '').toString().trim();
    if (!branchIdRaw) {
      return res.status(400).json({ error: 'branch_id is required' });
    }
    const branchId = parseInt(branchIdRaw, 10);
    if (!Number.isFinite(branchId) || branchId <= 0) {
      return res.status(400).json({ error: 'branch_id must be a number' });
    }
    if (!(await assertUserCanAccessStoreOperationalBranch(req, res, branchId))) {
      return;
    }

    const datePat = /^\d{4}-\d{2}-\d{2}$/;
    const dateRaw = (req.query.date ?? '').toString().trim();
    const fromRaw = (req.query.date_from ?? '').toString().trim();
    const toRaw = (req.query.date_to ?? '').toString().trim();

    let result;
    if (datePat.test(fromRaw) && datePat.test(toRaw)) {
      if (fromRaw > toRaw) {
        return res.status(400).json({
          error: 'date_from tidak boleh lebih besar dari date_to',
        });
      }
      result = await db.query(
        `
        SELECT entry_id, branch_id, user_id, amount, category, notes, entry_kind, proof_photo_url, created_at
        FROM store_operational_entries
        WHERE branch_id = $1
          AND created_at >= ($2::date AT TIME ZONE 'Asia/Jakarta')
          AND created_at < (($3::date + INTERVAL '1 day') AT TIME ZONE 'Asia/Jakarta')
        ORDER BY created_at DESC
      `,
        [branchId, fromRaw, toRaw]
      );
    } else {
      const targetDate = datePat.test(dateRaw)
        ? dateRaw
        : new Date().toISOString().split('T')[0];
      result = await db.query(
        `
        SELECT entry_id, branch_id, user_id, amount, category, notes, entry_kind, proof_photo_url, created_at
        FROM store_operational_entries
        WHERE branch_id = $1
          AND created_at >= ($2::date AT TIME ZONE 'Asia/Jakarta')
          AND created_at < (($2::date + INTERVAL '1 day') AT TIME ZONE 'Asia/Jakarta')
        ORDER BY created_at DESC
      `,
        [branchId, targetDate]
      );
    }

    const rows = result.rows.map((r) => ({
      entry_id: r.entry_id != null ? String(r.entry_id) : null,
      branch_id: r.branch_id != null ? String(r.branch_id) : null,
      user_id: r.user_id != null ? String(r.user_id) : null,
      amount: parseFloat(r.amount || 0),
      category: r.category,
      notes: r.notes,
      entry_kind: r.entry_kind === 'income' ? 'income' : 'expense',
      proof_photo_url: r.proof_photo_url,
      created_at: r.created_at,
    }));

    return res.status(200).json(rows);
  } catch (e) {
    console.error('Error listing store-operational:', e);
    if (e && e.code === '42P01') {
      return res.status(503).json({
        error: 'Tabel belum tersedia di database',
        details:
          'Jalankan migrasi backend/migrations/20260507_store_operational_entries.sql dan 20260508_store_operational_entry_kind.sql lalu restart server.',
      });
    }
    if (e && e.code === '42703' && /entry_kind/i.test(String(e.message || ''))) {
      return res.status(503).json({
        error: 'Skema perlu diperbarui (entry_kind)',
        details:
          'Jalankan backend/migrations/20260508_store_operational_entry_kind.sql lalu restart server.',
      });
    }
    if (
      e &&
      e.code === '42703' &&
      /proof_photo_url/i.test(String(e.message || ''))
    ) {
      return res.status(503).json({
        error: 'Skema perlu diperbarui (proof_photo_url)',
        details:
          'Jalankan backend/migrations/20260509_store_operational_proof_photo_url.sql lalu restart server.',
      });
    }
    return res.status(500).json({
      error: 'Internal server error',
      detail: process.env.NODE_ENV !== 'production' ? e.message : undefined,
    });
  }
});

app.post('/store-operational', async (req, res) => {
  try {
    const { branch_id, amount, category, notes, entry_kind, proof_photo_url } =
      req.body ?? {};
    const branchIdRaw = (branch_id ?? '').toString().trim();
    if (!branchIdRaw) {
      return res.status(400).json({ error: 'branch_id is required' });
    }
    const branchId = parseInt(branchIdRaw, 10);
    if (!Number.isFinite(branchId) || branchId <= 0) {
      return res.status(400).json({ error: 'branch_id must be a number' });
    }
    if (!(await assertUserCanAccessStoreOperationalBranch(req, res, branchId))) {
      return;
    }

    const amt = parseFloat(amount);
    if (!Number.isFinite(amt) || amt <= 0) {
      return res.status(400).json({ error: 'amount harus angka positif' });
    }
    const cat = (category ?? '').toString().trim();
    if (!cat) {
      return res.status(400).json({ error: 'category wajib diisi' });
    }
    const notesVal = (notes ?? '').toString().trim() || null;
    const kindRaw = (entry_kind ?? '').toString().trim().toLowerCase();
    const entryKind = kindRaw === 'income' ? 'income' : 'expense';
    const proofUrl =
      proof_photo_url != null && String(proof_photo_url).trim().length > 0
        ? String(proof_photo_url).trim()
        : null;
    const userId = req.user?.user_id != null
      ? parseInt(String(req.user.user_id), 10)
      : null;

    const ins = await db.query(
      `
        INSERT INTO store_operational_entries (branch_id, user_id, amount, category, notes, entry_kind, proof_photo_url)
        VALUES ($1, $2, $3, $4, $5, $6, $7)
        RETURNING entry_id, branch_id, user_id, amount, category, notes, entry_kind, proof_photo_url, created_at
      `,
      [
        branchId,
        Number.isFinite(userId) ? userId : null,
        amt,
        cat,
        notesVal,
        entryKind,
        proofUrl,
      ]
    );
    const r = ins.rows[0];
    return res.status(201).json({
      entry_id: r.entry_id != null ? String(r.entry_id) : null,
      branch_id: r.branch_id != null ? String(r.branch_id) : null,
      user_id: r.user_id != null ? String(r.user_id) : null,
      amount: parseFloat(r.amount || 0),
      category: r.category,
      notes: r.notes,
      entry_kind: r.entry_kind === 'income' ? 'income' : 'expense',
      proof_photo_url: r.proof_photo_url,
      created_at: r.created_at,
    });
  } catch (e) {
    console.error('Error creating store-operational:', e);
    if (e && e.code === '42P01') {
      return res.status(503).json({
        error: 'Tabel belum tersedia di database',
        details:
          'Jalankan migrasi backend/migrations/20260508_store_operational_entry_kind.sql (dan 20260507 jika tabel belum ada) lalu restart server.',
      });
    }
    if (e && e.code === '42703' && /entry_kind/i.test(String(e.message || ''))) {
      return res.status(503).json({
        error: 'Skema perlu diperbarui (entry_kind)',
        details:
          'Jalankan backend/migrations/20260508_store_operational_entry_kind.sql lalu restart server.',
      });
    }
    if (
      e &&
      e.code === '42703' &&
      /proof_photo_url/i.test(String(e.message || ''))
    ) {
      return res.status(503).json({
        error: 'Skema perlu diperbarui (proof_photo_url)',
        details:
          'Jalankan backend/migrations/20260509_store_operational_proof_photo_url.sql lalu restart server.',
      });
    }
    return res.status(500).json({
      error: 'Internal server error',
      detail: process.env.NODE_ENV !== 'production' ? e.message : undefined,
    });
  }
});

// Upload / update foto bukti untuk entri tertentu
app.post('/store-operational/:entry_id/proof-photo', async (req, res) => {
  try {
    const entryIdRaw = (req.params.entry_id ?? '').toString().trim();
    const entryId = parseInt(entryIdRaw, 10);
    if (!Number.isFinite(entryId) || entryId <= 0) {
      return res.status(400).json({ error: 'entry_id tidak valid' });
    }

    const { branch_id, proof_photo_url } = req.body ?? {};
    const branchIdRaw = (branch_id ?? '').toString().trim();
    const branchId = parseInt(branchIdRaw, 10);
    if (!Number.isFinite(branchId) || branchId <= 0) {
      return res.status(400).json({ error: 'branch_id tidak valid' });
    }
    if (!(await assertUserCanAccessStoreOperationalBranch(req, res, branchId))) {
      return;
    }

    const proofUrl =
      proof_photo_url != null && String(proof_photo_url).trim().length > 0
        ? String(proof_photo_url).trim()
        : null;
    if (!proofUrl) {
      return res.status(400).json({ error: 'proof_photo_url wajib diisi' });
    }

    const upd = await db.query(
      `
        UPDATE store_operational_entries
        SET proof_photo_url = $1
        WHERE entry_id = $2 AND branch_id = $3
        RETURNING entry_id, branch_id, user_id, amount, category, notes, entry_kind, proof_photo_url, created_at
      `,
      [proofUrl, entryId, branchId]
    );
    if (upd.rows.length === 0) {
      return res.status(404).json({ error: 'Entri tidak ditemukan' });
    }
    const r = upd.rows[0];
    return res.status(200).json({
      entry_id: r.entry_id != null ? String(r.entry_id) : null,
      branch_id: r.branch_id != null ? String(r.branch_id) : null,
      user_id: r.user_id != null ? String(r.user_id) : null,
      amount: parseFloat(r.amount || 0),
      category: r.category,
      notes: r.notes,
      entry_kind: r.entry_kind === 'income' ? 'income' : 'expense',
      proof_photo_url: r.proof_photo_url,
      created_at: r.created_at,
    });
  } catch (e) {
    console.error('Error updating store-operational proof photo:', e);
    if (e && e.code === '42P01') {
      return res.status(503).json({
        error: 'Tabel belum tersedia di database',
        details:
          'Jalankan migrasi backend/migrations/20260507_store_operational_entries.sql lalu restart server.',
      });
    }
    if (
      e &&
      e.code === '42703' &&
      /proof_photo_url/i.test(String(e.message || ''))
    ) {
      return res.status(503).json({
        error: 'Skema perlu diperbarui (proof_photo_url)',
        details:
          'Jalankan backend/migrations/20260509_store_operational_proof_photo_url.sql lalu restart server.',
      });
    }
    return res.status(500).json({
      error: 'Internal server error',
      detail: process.env.NODE_ENV !== 'production' ? e.message : undefined,
    });
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

    const toObject = (raw) => {
      if (raw && typeof raw === 'object' && !Array.isArray(raw)) return raw;
      if (typeof raw === 'string') {
        const s = raw.trim();
        if (!s) return {};
        try {
          const parsed = JSON.parse(s);
          return parsed && typeof parsed === 'object' && !Array.isArray(parsed)
            ? parsed
            : {};
        } catch (_) {
          return {};
        }
      }
      return {};
    };

    const toNumberLoose = (raw) => {
      if (typeof raw === 'number') return Number.isFinite(raw) ? raw : NaN;
      const s0 = String(raw ?? '').trim();
      if (!s0) return NaN;
      const s = s0.replace(/\s+/g, '');
      if (/^-?\d+$/.test(s)) return Number(s);
      let normalized = s;
      if (s.includes(',') && s.includes('.')) {
        if (s.lastIndexOf(',') > s.lastIndexOf('.')) {
          // 1.234,56 -> 1234.56
          normalized = s.replace(/\./g, '').replace(',', '.');
        } else {
          // 1,234.56 -> 1234.56
          normalized = s.replace(/,/g, '');
        }
      } else if (s.includes(',')) {
        // 1234,56 or 1.234,56
        normalized = s.replace(/\./g, '').replace(',', '.');
      } else {
        // 1.234.567 (thousands) vs 1234.56 (decimal)
        const dotCount = (s.match(/\./g) || []).length;
        if (dotCount > 1) normalized = s.replace(/\./g, '');
      }
      const n = Number(normalized);
      return Number.isFinite(n) ? n : NaN;
    };

    const firstFiniteNumber = (...vals) => {
      for (const v of vals) {
        const n = toNumberLoose(v);
        if (Number.isFinite(n)) return n;
      }
      return 0;
    };

    // Order jual dari stok: hanya status yang boleh di etalase (bukan buyback / servis / custom / sold).
    // Buyback harus lewat gudang (transfer) sampai status layak jual di cabang tujuan.
    {
      const ot = orderData.order_type;
      const ois = orderData.order_items;
      if (ot === 'jual' && Array.isArray(ois)) {
        const itemIds = [];
        for (const row of ois) {
          if (!row || row.item_id == null || row.item_id === '') continue;
          const n = parseInt(row.item_id, 10);
          if (Number.isFinite(n)) itemIds.push(n);
        }
        const uniqueIds = [...new Set(itemIds)];
        if (uniqueIds.length > 0) {
          const vr = await db.query(
            `SELECT item_id, status, kode_produk, name FROM items WHERE item_id = ANY($1::bigint[])`,
            [uniqueIds]
          );
          const found = new Set(vr.rows.map((r) => parseInt(r.item_id, 10)));
          for (const id of uniqueIds) {
            if (!found.has(id)) {
              return res.status(400).json({
                error: 'item_id tidak ditemukan',
                detail: String(id),
              });
            }
          }
          const allowed = new Set(['ready', 'available', 'reserved']);
          for (const row of vr.rows) {
            const st = (row.status ?? '').toString().trim().toLowerCase();
            if (!allowed.has(st)) {
              return res.status(400).json({
                error: 'Item tidak boleh dijual dalam status ini',
                detail: `item_id ${row.item_id} (${row.kode_produk || row.name || ''}) memiliki status "${row.status}". Barang buyback atau yang belum siap etalase harus diproses/ditransfer ke gudang dulu.`,
              });
            }
          }
        }
      }
    }

    await client.query('BEGIN');

    // Backward-compatible: DB may have items.photo_url (old) or items.photo_produk (new)
    const itemsPhotoCol = await getItemsPhotoColumn(client);
    const itemsPhotoColName = itemsPhotoCol || 'photo_url';

    // Persist upload metadata (safe: filename is server-generated)
    let _uploadId = null;
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
        _uploadId = upRes.rows[0]?.upload_id ?? null;
        await client.query('RELEASE SAVEPOINT uploads_insert');
      } catch (_) {
        _uploadId = null;
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
      status: requestedStatus,
      service_estimated_total,
      service_dp_amount: _service_dp_amount,
      // For backward compatibility
      item_id: _item_id,
      item_data: _item_data,
    } = orderData;
    const refOrderNumberRaw = String(
      orderData.reference_order_number ??
      orderData.nota_lama ??
      ''
    ).trim();
    const estimateAmountRaw = parseFloat(
      orderData.estimate_amount ??
      service_estimated_total ??
      orderData.custom_estimated_total ??
      0
    );
    const estimateAmount = Number.isFinite(estimateAmountRaw) && estimateAmountRaw > 0
      ? estimateAmountRaw
      : null;
    const estimateDueCandidate = String(
      orderData.estimate_due_at ??
      orderData.estimasi_selesai ??
      orderData.estimated_finish_at ??
      orderData.estimated_completion_date ??
      ''
    ).trim();
    let estimateDueAtIso = null;
    if (estimateDueCandidate) {
      const parsedDue = new Date(estimateDueCandidate);
      if (!Number.isNaN(parsedDue.getTime())) {
        estimateDueAtIso = parsedDue.toISOString();
      }
    }
    const estimateDurationText = String(
      orderData.estimate_duration_text ??
      orderData.estimasi_waktu ??
      ''
    ).trim() || null;
    const estimateNotes = String(
      orderData.estimate_notes ??
      orderData.keterangan ??
      orderData.catatan_service ??
      ''
    ).trim() || null;

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
    const rawRequestedStatus = (requestedStatus ?? '')
      .toString()
      .trim()
      .toLowerCase();
    let initialStatus = 'pending';
    if (order_type === 'service' || order_type === 'custom') {
      // Cabang toko: pending (DP → kasir; non-DP → admin toko). Workshop hanya setelah gudang setuju.
      initialStatus = 'pending';
      if (rawRequestedStatus === 'pending') {
        initialStatus = 'pending';
      } else if (rawRequestedStatus === 'sent-to-workshop') {
        initialStatus = 'pending';
      }
    } else if (rawRequestedStatus) {
      initialStatus = rawRequestedStatus;
    }

    const orderResult = await client.query(
      `INSERT INTO orders (
        order_type, customer_id, status, order_number, branch_id, user_id, diskon, mode, total
      ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)
      RETURNING *`,
      [order_type, customer_id, initialStatus, nota_order, branch_id, user_id, diskon, mode, 0] // total will be calculated later
    );

    const order = orderResult.rows[0];

    // Persist estimate fields to dedicated order columns when available.
    if (
      (estimateAmount !== null || estimateDueAtIso || estimateDurationText || estimateNotes) &&
      order?.order_id
    ) {
      const estCols = await ordersEstimateColumns(client);
      const setClauses = [];
      const values = [];
      if (estCols.estimate_amount) {
        setClauses.push(`estimate_amount = $${values.length + 1}`);
        values.push(estimateAmount);
      }
      if (estCols.estimate_due_at) {
        setClauses.push(`estimate_due_at = $${values.length + 1}`);
        values.push(estimateDueAtIso);
      }
      if (estCols.estimate_duration_text) {
        setClauses.push(`estimate_duration_text = $${values.length + 1}`);
        values.push(estimateDurationText);
      }
      if (estCols.estimate_notes) {
        setClauses.push(`estimate_notes = $${values.length + 1}`);
        values.push(estimateNotes);
      }
      if (setClauses.length > 0) {
        values.push(order.order_id);
        await client.query(
          `
            UPDATE orders
            SET ${setClauses.join(', ')}, updated_at = NOW()
            WHERE order_id = $${values.length}
          `,
          values
        );
      }
    }

    // Cabang pengambilan (service/custom): NULL = sama dengan cabang order.
    if ((order_type === 'service' || order_type === 'custom') && order?.order_id) {
      const hasPickupColOrd = await ordersHasPickupBranchColumn(client);
      if (hasPickupColOrd) {
        const pickupRaw =
          orderData.pickup_branch_id ?? orderData.pickupBranchId ?? null;
        const pickupBid =
          pickupRaw != null ? parseInt(String(pickupRaw), 10) : NaN;
        const orderBid = parseInt(String(branch_id), 10);
        if (
          Number.isFinite(pickupBid) &&
          pickupBid > 0 &&
          Number.isFinite(orderBid) &&
          pickupBid !== orderBid
        ) {
          await client.query(
            `UPDATE orders SET pickup_branch_id = $1, updated_at = NOW() WHERE order_id = $2`,
            [pickupBid, order.order_id]
          );
        }
      }
    }

    // Persist reference order number (nota lama) for future reprints.
    if ((order_type === 'buyback' || order_type === 'service') && refOrderNumberRaw) {
      const hasOrdersMetadata = await ordersHasMetadataColumn(client);
      if (hasOrdersMetadata) {
        await client.query(
          `
            UPDATE orders
            SET metadata = COALESCE(metadata, '{}'::jsonb) || $1::jsonb
            WHERE order_id = $2
          `,
          [
            JSON.stringify({
              reference_order_number: refOrderNumberRaw,
              nota_lama: refOrderNumberRaw,
              nota_jual: refOrderNumberRaw,
            }),
            order.order_id,
          ]
        );
      }
    }

    // Service/custom: simpan field form ke metadata agar cetak ulang / GET order sinkron dengan faktur.
    if ((order_type === 'service' || order_type === 'custom') && order?.order_id) {
      const hasSvcMeta = await ordersHasMetadataColumn(client);
      if (hasSvcMeta) {
        const firstReqItem =
          Array.isArray(order_items) && order_items.length > 0 ? order_items[0] : {};
        const kelengkapan = String(orderData.kelengkapan ?? '').trim();
        const keterangan = String(
          orderData.keterangan ?? orderData.estimate_notes ?? '',
        ).trim();
        const jenisService = String(
          firstReqItem.tipe ?? orderData.jenis_service ?? '',
        ).trim();
        const estimasiSelesaiRaw = String(orderData.estimasi_selesai ?? '').trim();
        const estimasiWaktuRaw = String(orderData.estimasi_waktu ?? '').trim();
        const metaPatch = {};
        if (kelengkapan) metaPatch.kelengkapan = kelengkapan;
        if (keterangan) metaPatch.keterangan = keterangan;
        if (jenisService) metaPatch.jenis_service = jenisService;
        if (estimasiWaktuRaw) metaPatch.estimasi_waktu = estimasiWaktuRaw;
        if (estimasiSelesaiRaw) {
          metaPatch.estimasi_selesai = estimasiSelesaiRaw;
          if (!estimateDueAtIso) metaPatch.estimasi_selesai_text = estimasiSelesaiRaw;
        } else if (
          order_type === 'custom' &&
          estimasiWaktuRaw &&
          !estimateDueAtIso
        ) {
          // Form custom: field "estimasi waktu" dipakai sebagai teks estimasi selesai bila tidak ada tanggal ter-parse.
          metaPatch.estimasi_selesai = estimasiWaktuRaw;
          metaPatch.estimasi_selesai_text = estimasiWaktuRaw;
        }
        if (estimateAmount !== null && estimateAmount > 0) {
          metaPatch.service_estimated_total = estimateAmount;
        }
        if (order_type === 'custom') {
          const spek = String(orderData.spesifikasi ?? '').trim();
          if (spek) metaPatch.spesifikasi = spek;
        }
        const serviceDpPersist = firstFiniteNumber(
          orderData.service_dp_amount,
          orderData.serviceDpAmount,
          _service_dp_amount,
          0,
        );
        if (serviceDpPersist > 0) {
          metaPatch.service_dp_amount = serviceDpPersist;
        }
        if (Object.keys(metaPatch).length > 0) {
          await client.query(
            `
              UPDATE orders
              SET metadata = COALESCE(metadata, '{}'::jsonb) || $1::jsonb, updated_at = NOW()
              WHERE order_id = $2
            `,
            [JSON.stringify(metaPatch), order.order_id],
          );
        }
      }
    }

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
            // Keep material/kadar from request (order_items) if provided; fallback to items table.
            material:
              (itemData.material != null && String(itemData.material).trim().length > 0)
                ? itemData.material
                : dbItem.material,
            purity:
              (itemData.purity != null && String(itemData.purity).trim().length > 0)
                ? itemData.purity
                : dbItem.purity,
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
          // Buyback stock should be added only when payment is completed.
          // Start from 0 to avoid double count (default DB quantity is 1).
          const initialItemQty = order_type === 'buyback'
            ? 0
            : (parseInt(itemData.quantity, 10) || 1);
          const itemResult = await client.query(
            `INSERT INTO items (
              name, kode_produk, weight, material, purity, kategori, jenis, tipe,
              ownership, stock_type, status, is_quick_registered, branch_id, source, quantity, ${itemsPhotoColName}
            ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15, $16)
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
              initialItemQty,
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

        const statusBeforeOrderUpdate = (
          itemData.status || 'unregistered'
        ).toString();

        await client.query(
          `UPDATE items SET
            status = $1, ownership = $2, stock_type = $3, updated_at = NOW()
           WHERE item_id = $4`,
          [newItemStatus, newOwnership, newStockType, final_item_id]
        );

        // Riwayat status: dari status baris setelah INSERT (bukan placeholder 'unknown')
        await client.query(
          `INSERT INTO stock_history (item_id, old_status, new_status, changed_by, notes)
           VALUES ($1, $2, $3, $4, $5)`,
          [
            final_item_id,
            statusBeforeOrderUpdate,
            newItemStatus,
            user_id,
            `Order ${order_type} created`,
          ]
        );

      }

      // Save item condition for buyback orders (works for existing and new items)
      if (order_type === 'buyback' && final_item_id) {
        const kondisiBarang = toObject(itemData.kondisi_barang ?? itemData.kondisiBarang);
        const itemRefOrderNumber = String(
          kondisiBarang.nota_jual ??
          refOrderNumberRaw ??
          ''
        ).trim();
        const catatanRaw = String(
          kondisiBarang.catatan_kondisi ??
          itemData.catatan_kondisi ??
          itemData.catatanKondisi ??
          ''
        ).trim();
        const catatanWithReference = (() => {
          if (!itemRefOrderNumber) return catatanRaw;
          if (/nota_jual_ref\s*:/i.test(catatanRaw)) return catatanRaw;
          return catatanRaw
            ? `${catatanRaw}\nnota_jual_ref: ${itemRefOrderNumber}`
            : `nota_jual_ref: ${itemRefOrderNumber}`;
        })();
        const itemConditionCols = await getItemConditionsColumns(client);
        const insertCols = ['item_id', 'order_id'];
        const insertParams = [final_item_id, order.order_id];
        const tipeBarang = String(
          kondisiBarang.tipe ??
          itemData.tipe ??
          itemDetails.tipe ??
          ''
        )
          .trim()
          .toLowerCase();
        const penyesuaianBerat = firstFiniteNumber(
          kondisiBarang.penyesuaian_berat,
          itemData.penyesuaian_berat,
          0
        );
        const hargaPerGramBuyback = firstFiniteNumber(
          kondisiBarang.harga_per_gram,
          itemData.harga_per_gram,
          itemDetails.harga_per_gram,
          0
        );
        const potonganKondisi = firstFiniteNumber(
          kondisiBarang.potongan_kondisi,
          itemData.potongan_kondisi,
          0
        );
        const untungRugiNormalized = String(
          kondisiBarang.untung_rugi ??
          itemData.untung_rugi ??
          itemData.untungRugi ??
          'UNTUNG'
        )
          .trim()
          .toUpperCase();
        let nilaiUntungRugiFormula = NaN;
        const coef =
          tipeBarang === 'biasa' ? 10000 :
            tipeBarang === 'gress' ? 12000 :
              0;
        if (coef > 0) {
          if (untungRugiNormalized === 'UNTUNG') {
            nilaiUntungRugiFormula = coef * penyesuaianBerat;
          } else if (untungRugiNormalized === 'RUGI') {
            nilaiUntungRugiFormula = -coef * penyesuaianBerat;
          } else {
            nilaiUntungRugiFormula = 0;
          }
        }
        const nilaiUntungRugiFinal = Number.isFinite(nilaiUntungRugiFormula)
          ? nilaiUntungRugiFormula
          : firstFiniteNumber(
            kondisiBarang.nilai_untung_rugi,
            itemData.nilai_untung_rugi,
            itemData.nilaiUntungRugi,
            0
          );
        const nilaiResaleRaw =
          (hargaPerGramBuyback * penyesuaianBerat) +
          nilaiUntungRugiFinal -
          potonganKondisi;
        const nilaiResaleRounded = roundUpToNearest5000(Math.ceil(nilaiResaleRaw));
        const optionalFields = {
          kondisi_fisik:
            (kondisiBarang.kondisi_fisik ??
              itemData.kondisi_fisik ??
              itemData.kondisiFisik ??
              'BAIK'),
          penyesuaian_berat: penyesuaianBerat,
          harga_per_gram: hargaPerGramBuyback,
          potongan_kondisi: potonganKondisi,
          nilai_resale: nilaiResaleRounded,
          untung_rugi: untungRugiNormalized || 'UNTUNG',
          nilai_untung_rugi: nilaiUntungRugiFinal,
          catatan_kondisi:
            catatanWithReference,
          foto_kondisi:
            kondisiBarang.foto_kondisi ||
            (itemData.photo_produk ? [itemData.photo_produk] : []),
        };
        for (const [col, val] of Object.entries(optionalFields)) {
          if (!itemConditionCols.has(col)) continue;
          insertCols.push(col);
          insertParams.push(val);
        }
        const placeholders = insertParams.map((_, i) => `$${i + 1}`).join(', ');
        await client.query(
          `INSERT INTO item_conditions (${insertCols.join(', ')}) VALUES (${placeholders})`,
          insertParams
        );
      }

      // Create order item
      // Catatan: diskon hanya level orders (bukan per item).
      // Default (jual/buyback): subtotal = qty * weight * harga_per_gram, lalu total dibulatkan naik ke kelipatan 5.000.
      // Service/Custom: boleh kirim angka final manual lewat `manual_total` (mis. biaya jasa / estimasi biaya).
      const qtyVal = parseInt(itemDetails.qty) || 1;
      const weightVal = parseFloat(itemDetails.weight) || 0;
      const hargaVal = parseFloat(itemDetails.harga_per_gram) || 0;

      const manualTotalRaw =
        itemDetails.manual_total ??
        itemDetails.manualTotal ??
        itemData.manual_total ??
        itemData.manualTotal;
      const manualTotalVal = parseFloat(manualTotalRaw);

      const isManualTotalAllowed = order_type === 'service' || order_type === 'custom';
      const subtotalVal =
        isManualTotalAllowed && Number.isFinite(manualTotalVal) && manualTotalVal > 0
          ? manualTotalVal
          : qtyVal * weightVal * hargaVal;
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

      // Update existing item stock if it's from items table (has item_id).
      // IMPORTANT: buyback should NOT check/consume stock like a sale.
      if (final_item_id && itemData.item_id) {
        const prevQtyRaw = itemDetails.item_quantity;
        const prevQty = Number.isFinite(parseInt(prevQtyRaw, 10))
          ? parseInt(prevQtyRaw, 10)
          : 0;

        if (order_type === 'jual') {
          // Decrease quantity for stock items. If stock remains, keep item as stock.
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

          // Always record stock mutation for this sale (type must satisfy stock_mutations_type_check: in|out|transfer|adjustment)
          await client.query(
            `
              INSERT INTO stock_mutations (
                item_id, branch_id, type, quantity, previous_stock, current_stock,
                notes, reference_id, reference_type, created_by
              )
              VALUES ($1, $2, 'out', $3, $4, $5, $6, $7, 'order', $8)
            `,
            [
              final_item_id,
              branch_id,
              qtyVal,
              prevQty,
              nextQty,
              `Order ${order_type} (${nota_order})`,
              order.order_id,
              user_id,
            ]
          );
        }
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

    const hasPickupPending = await ordersHasPickupBranchColumn(db);
    const pickupBranchExprPending = hasPickupPending
      ? 'COALESCE(o.pickup_branch_id, o.branch_id)'
      : 'o.branch_id';

    const result = await db.query(`
      SELECT
        o.order_id,
        o.order_number,
        o.order_type,
        o.total,
        o.diskon,
        o.created_at,
        o.updated_at,
        c.name AS customer_name,
        c.phone,
        c.address,
        EXISTS (
          SELECT 1 FROM payments p0
          WHERE p0.order_id = o.order_id AND p0.status = 'completed'
        ) AS has_completed_payment,
        COALESCE(
          (
            SELECT SUM(COALESCE(p.amount, 0))::float8
            FROM payments p
            WHERE p.order_id = o.order_id
              AND p.status IN ('pending', 'completed')
          ),
          0
        ) AS paid_amount,
        COALESCE(
          (
            SELECT STRING_AGG(
              COALESCE(
                NULLIF(BTRIM(oi.nama_item), ''),
                NULLIF(BTRIM(i.name), ''),
                '(tanpa nama)'
              ),
              ', ' ORDER BY oi.order_item_id
            )
            FROM order_items oi
            LEFT JOIN items i ON oi.item_id = i.item_id
            WHERE oi.order_id = o.order_id
          ),
          'Order ' || COALESCE(o.order_number, o.order_id::text)
        ) AS item_name,
        COALESCE(
          (
            SELECT SUM(GREATEST(COALESCE(oi.qty, 1), 1))::int
            FROM order_items oi
            WHERE oi.order_id = o.order_id
          ),
          1
        ) AS quantity,
        COALESCE(
          (
            SELECT SUM(
              COALESCE(oi.weight, i.weight, 0)::numeric
              * GREATEST(COALESCE(oi.qty, 1), 1)::numeric
            )
            FROM order_items oi
            LEFT JOIN items i ON oi.item_id = i.item_id
            WHERE oi.order_id = o.order_id
          ),
          0
        )::float8 AS weight,
        (
          SELECT MAX(
            COALESCE(
              NULLIF(BTRIM(oi.jenis), ''),
              NULLIF(BTRIM(i.material), '')
            )
          )
          FROM order_items oi
          LEFT JOIN items i ON oi.item_id = i.item_id
          WHERE oi.order_id = o.order_id
        ) AS material
      FROM orders o
      JOIN customers c ON o.customer_id = c.customer_id
      WHERE o.status IN ('pending', 'ready_for_payment', 'confirmed', 'ready_for_pickup')
        AND (
          (
            o.branch_id = $1::bigint
            AND NOT EXISTS (
              SELECT 1 FROM payments p
              WHERE p.order_id = o.order_id
                AND p.status = 'completed'
            )
            AND NOT (
              LOWER(TRIM(COALESCE(o.order_type::text, ''))) IN ('service', 'custom')
              AND o.status = 'pending'
              AND NOT EXISTS (
                SELECT 1 FROM payments p0 WHERE p0.order_id = o.order_id
              )
            )
          )
          OR (
            LOWER(TRIM(COALESCE(o.order_type::text, ''))) IN ('service', 'custom')
            AND EXISTS (
              SELECT 1 FROM payments p
              WHERE p.order_id = o.order_id
                AND p.status = 'completed'
            )
            AND COALESCE(o.total, 0) > COALESCE(
              (
                SELECT SUM(COALESCE(p2.amount, 0))::float8
                FROM payments p2
                WHERE p2.order_id = o.order_id
                  AND p2.status IN ('pending', 'completed')
              ),
              0
            ) + 0.000001
            AND ${pickupBranchExprPending} = $1::bigint
          )
        )
      ORDER BY o.created_at DESC
    `, [branch_id]);

    // Convert BigInt and other data types for JSON serialization
    const processedRows = result.rows.map((row) => {
      const w = parseFloat(row.weight || 0);
      const itemName = row.item_name;
      const total = parseFloat(row.total || 0);
      const paid = parseFloat(row.paid_amount || 0);
      const remaining = Math.max(total - paid, 0);
      return {
        order_id: row.order_id.toString(),
        order_number: row.order_number,
        order_type: row.order_type,
        total,
        diskon: parseFloat(row.diskon || 0),
        created_at: row.created_at,
        updated_at: row.updated_at,
        customer_name: row.customer_name,
        phone: row.phone,
        address: row.address,
        item_name: itemName,
        nama_item: itemName,
        quantity: parseInt(row.quantity || 1, 10),
        weight: w,
        berat: w,
        material: row.material,
        paid_amount: paid,
        remaining_amount: remaining,
        has_completed_payment: Boolean(row.has_completed_payment),
      };
    });

    res.status(200).json(processedRows);
  } catch (error) {
    console.error('Error fetching pending payment orders:', error);
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
        ic.penyesuaian_berat,
        ic.nilai_resale,
        ic.harga_per_gram,
        ic.potongan_kondisi,
        ic.untung_rugi,
        ic.nilai_untung_rugi,
        ic.catatan_kondisi,
        ic.foto_kondisi,
        ic.created_at,
        ic.updated_at,
        i.name as item_name,
        i.kode_produk,
        i.weight as item_weight,
        i.material,
        i.purity,
        o.order_number,
        o.order_type,
        c.name as customer_name
      FROM item_conditions ic
      JOIN items i ON ic.item_id = i.item_id
      JOIN orders o ON ic.order_id = o.order_id
      JOIN customers c ON o.customer_id = c.customer_id
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
      kerusakan: [],
      penyesuaian_berat: row.penyesuaian_berat,
      nilai_resale: parseInt(row.nilai_resale || 0),
      harga_per_gram: parseFloat(row.harga_per_gram || 0),
      potongan_kondisi: parseFloat(row.potongan_kondisi || 0),
      untung_rugi: row.untung_rugi,
      nilai_untung_rugi: parseFloat(row.nilai_untung_rugi || 0),
      catatan_kondisi: row.catatan_kondisi,
      foto_kondisi: row.foto_kondisi || [],
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
    }));

    res.status(200).json(processedRows);
  } catch (error) {
    console.error('Error fetching item conditions:', error);
    res.status(500).json({ error: 'Internal server error', details: error.message });
  }
});

// Get all branches (logo_url opsional: fallback jika kolom belum ada)
app.get('/branches', async (req, res) => {
  try {
    const qWithLogo = `
      SELECT
        branch_id,
        name,
        code,
        alias,
        initials,
        address,
        phone_number,
        status,
        logo_url
      FROM branches
      ORDER BY name
    `;
    const qNoLogo = `
      SELECT
        branch_id,
        name,
        code,
        alias,
        initials,
        address,
        phone_number,
        status,
        NULL::text AS logo_url
      FROM branches
      ORDER BY name
    `;
    let result;
    try {
      result = await db.query(qWithLogo);
    } catch (e) {
      if (String(e.message || '').includes('logo_url')) {
        result = await db.query(qNoLogo);
      } else {
        throw e;
      }
    }

    const processedRows = result.rows.map(row => ({
      branch_id: row.branch_id != null ? String(row.branch_id) : '',
      name: row.name,
      code: row.code,
      alias: row.alias,
      initials: row.initials,
      address: row.address,
      phone_number: row.phone_number,
      status: row.status,
      logo_url: row.logo_url || null,
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

    const { logo_url } = req.body || {};
    const insertQuery = `
      INSERT INTO branches (name, code, alias, initials, address, phone_number, status, logo_url, created_at, updated_at)
      VALUES ($1, $2, $3, $4, $5, $6, 'active', $7, NOW(), NOW())
      RETURNING branch_id, name, code, alias, initials, address, phone_number, status, logo_url, created_at, updated_at
    `;
    const result = await db.query(insertQuery, [name, code, alias, initials, address, phone_number, logo_url || null]);

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
    const {
      branch_id,
      item_code,
      stock_type: _stock_type,
      status,
      is_quick_registered,
      search,
      limit,
      sellable_only,
    } = req.query;
    const hasCreatorCol = await itemsHasCreatedByColumn();
    const fromSql = hasCreatorCol
      ? 'items i LEFT JOIN users icu ON i.created_by = icu.user_id'
      : 'items i';
    const selectSql = hasCreatorCol
      ? 'i.*, icu.username AS item_created_by_name'
      : 'i.*';
    let query = `SELECT ${selectSql} FROM ${fromSql}`;
    let params = [];
    let conditions = [];

    if (branch_id) {
      conditions.push(`i.branch_id = $${params.length + 1}`);
      params.push(branch_id);
    }

    if (item_code) {
      // Backward compatible: DB schema uses kode_produk
      conditions.push(`(i.kode_produk = $${params.length + 1})`);
      params.push(item_code);
    }

    // stock_type is not available in older schema; ignore when present

    if (status) {
      conditions.push(`i.status = $${params.length + 1}`);
      params.push(status);
    } else if (sellable_only === 'true' || sellable_only === '1') {
      // Stok yang boleh dipakai untuk penjualan etalase (exclude buyback, service, custom, sold, …)
      conditions.push(
        `LOWER(TRIM(COALESCE(i.status, ''))) IN ('ready', 'available', 'reserved')`
      );
    }

    if (is_quick_registered !== undefined) {
      conditions.push(`i.is_quick_registered = $${params.length + 1}`);
      params.push(is_quick_registered === 'true');
    }

    if (search) {
      conditions.push(
        `(CAST(i.item_id AS TEXT) ILIKE $${params.length + 1} OR i.kode_produk ILIKE $${params.length + 1} OR i.name ILIKE $${params.length + 1})`
      );
      params.push(`%${search}%`);
    }

    if (conditions.length > 0) {
      query += ' WHERE ' + conditions.join(' AND ');
    }

    query += ' ORDER BY i.created_at DESC';

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

// Riwayat perubahan status item (dari tabel stock_history, untuk pelengkap mutasi fisik).
app.get('/items/:id/status-history', async (req, res) => {
  try {
    const id = parseInt(String(req.params.id ?? '').trim(), 10);
    if (!Number.isFinite(id) || id <= 0) {
      return res.status(400).json({ error: 'Invalid item id' });
    }
    const result = await db.query(
      `
        SELECT
          sh.history_id,
          sh.item_id,
          sh.old_status,
          sh.new_status,
          sh.notes,
          sh.created_at,
          sh.changed_by,
          u.username AS changed_by_name
        FROM stock_history sh
        LEFT JOIN users u ON sh.changed_by = u.user_id
        WHERE sh.item_id = $1
        ORDER BY sh.created_at DESC NULLS LAST, sh.history_id DESC
        LIMIT 200
      `,
      [id]
    );
    return res.status(200).json(result.rows);
  } catch (error) {
    console.error('Error fetching item status history:', error);
    return res.status(500).json({ error: 'Internal server error' });
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

    const creatorId = parseInt(String(req.user?.user_id ?? req.user?.id ?? ''), 10);
    const creatorOk = Number.isFinite(creatorId) && creatorId > 0;
    const hasCb = await itemsHasCreatedByColumn();
    const qtyParsed = parseInt(String(quantity), 10);
    const qtyForMutation = Number.isFinite(qtyParsed) && qtyParsed > 0 ? qtyParsed : 1;

    const client = await db.getClient();
    let result;
    try {
      await client.query('BEGIN');
      if (hasCb) {
        result = await client.query(
          `INSERT INTO items (
            branch_id, kode_produk, kategori, jenis, tipe, name, material, purity, weight, quantity,
            status, source, metadata, created_by, created_at, updated_at
          ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, NOW(), NOW())
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
            creatorOk ? creatorId : null,
          ]
        );
      } else {
        result = await client.query(
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
      }

      const row = result.rows[0];
      await client.query(
        `
          INSERT INTO stock_mutations (
            item_id, branch_id, type, quantity, previous_stock, current_stock,
            notes, reference_id, reference_type, created_by
          )
          VALUES ($1, $2, 'in', $3, 0, $3, $4, NULL, 'item_create', $5)
        `,
        [
          row.item_id,
          branch_id,
          qtyForMutation,
          'Pembuatan / input stok baru',
          creatorOk ? creatorId : null,
        ]
      );

      await client.query('COMMIT');
      res.status(201).json(row);
    } catch (txErr) {
      await client.query('ROLLBACK');
      throw txErr;
    } finally {
      client.release();
    }
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
    const id = parseInt(req.params.id, 10);
    if (!Number.isFinite(id) || id <= 0) {
      return res.status(400).json({ error: 'Invalid item id' });
    }
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

    const newStatusStr = String(status);
    const editorId = parseInt(
      String(req.user?.user_id ?? req.user?.id ?? ''),
      10
    );
    const editorOk = Number.isFinite(editorId) && editorId > 0;

    const client = await db.getClient();
    try {
      await client.query('BEGIN');

      const prevRes = await client.query(
        `SELECT status FROM items WHERE item_id = $1 FOR UPDATE`,
        [id]
      );
      if (prevRes.rows.length === 0) {
        await client.query('ROLLBACK');
        return res.status(404).json({ error: 'Item not found' });
      }
      const oldStatus = String(prevRes.rows[0].status ?? '');

      const result = await client.query(
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
        await client.query('ROLLBACK');
        return res.status(404).json({ error: 'Item not found' });
      }

      if (oldStatus !== newStatusStr) {
        await client.query(
          `INSERT INTO stock_history (item_id, old_status, new_status, changed_by, notes)
           VALUES ($1, $2, $3, $4, $5)`,
          [
            id,
            oldStatus,
            newStatusStr,
            editorOk ? editorId : null,
            'Perubahan status / edit data item (toko atau admin)',
          ]
        );
      }

      await client.query('COMMIT');
      return res.json(result.rows[0]);
    } catch (txErr) {
      await client.query('ROLLBACK');
      throw txErr;
    } finally {
      client.release();
    }
  } catch (error) {
    console.error('Error updating item:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// Restock: increment item quantity safely
app.post('/items/:id/restock', async (req, res) => {
  try {
    const id = parseInt(req.params.id, 10);
    const { delta_quantity, branch_id } = req.body || {};

    const delta = parseInt(delta_quantity, 10);
    if (!Number.isFinite(delta) || delta <= 0) {
      return res
        .status(400)
        .json({ error: 'delta_quantity wajib diisi dan harus > 0' });
    }

    const creatorId = parseInt(String(req.user?.user_id ?? req.user?.id ?? ''), 10);
    const creatorOk = Number.isFinite(creatorId) && creatorId > 0;

    const client = await db.getClient();
    try {
      await client.query('BEGIN');

      const selParams = [id];
      let selSql = `SELECT item_id, branch_id, COALESCE(quantity, 0) AS quantity FROM items WHERE item_id = $1`;
      if (branch_id != null && String(branch_id).trim() !== '') {
        selSql += ` AND branch_id = $2`;
        selParams.push(branch_id);
      }
      const prevRes = await client.query(selSql, selParams);
      if (prevRes.rows.length === 0) {
        await client.query('ROLLBACK');
        return res.status(404).json({ error: 'Item not found' });
      }
      const prevQty = parseInt(prevRes.rows[0].quantity, 10) || 0;
      const itemBranchId = prevRes.rows[0].branch_id;

      const updParams = [delta, id];
      let updSql = `
      UPDATE items
      SET quantity = COALESCE(quantity, 0) + $1,
          updated_at = NOW()
      WHERE item_id = $2
    `;
      if (branch_id != null && String(branch_id).trim() !== '') {
        updSql += ` AND branch_id = $3`;
        updParams.push(branch_id);
      }
      updSql += ` RETURNING *`;
      const result = await client.query(updSql, updParams);
      if (result.rows.length === 0) {
        await client.query('ROLLBACK');
        return res.status(404).json({ error: 'Item not found' });
      }
      const row = result.rows[0];
      const nextQty = parseInt(row.quantity, 10) || 0;

      await client.query(
        `
          INSERT INTO stock_mutations (
            item_id, branch_id, type, quantity, previous_stock, current_stock,
            notes, reference_id, reference_type, created_by
          )
          VALUES ($1, $2, 'in', $3, $4, $5, $6, NULL, 'restock', $7)
        `,
        [
          id,
          itemBranchId,
          delta,
          prevQty,
          nextQty,
          'Restok penambahan quantity',
          creatorOk ? creatorId : null,
        ]
      );

      await client.query('COMMIT');
      return res.status(200).json(row);
    } catch (txErr) {
      await client.query('ROLLBACK');
      throw txErr;
    } finally {
      client.release();
    }
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

// CRUD for Branches (GET /branches list — gunakan handler tunggal di atas; duplikat dihapus agar tidak membingungkan)

app.get('/branches/:id/basic', async (req, res) => {
  try {
    const id = parseInt(req.params.id);
    const qWithLogo = `
      SELECT
        branch_id,
        name,
        code,
        alias,
        initials,
        address,
        phone_number,
        status,
        logo_url,
        created_at,
        updated_at
      FROM branches
      WHERE branch_id = $1
    `;
    const qNoLogo = `
      SELECT
        branch_id,
        name,
        code,
        alias,
        initials,
        address,
        phone_number,
        status,
        NULL::text AS logo_url,
        created_at,
        updated_at
      FROM branches
      WHERE branch_id = $1
    `;
    let result;
    try {
      result = await db.query(qWithLogo, [id]);
    } catch (e) {
      if (String(e.message || '').includes('logo_url')) {
        result = await db.query(qNoLogo, [id]);
      } else {
        throw e;
      }
    }

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

app.get('/branches/:id/logo', (req, res) => handleBranchLogoGet(req, res, db));

app.get('/branches/:id', async (req, res) => {
  try {
    const id = parseInt(req.params.id);
    const qWithLogo = `
      SELECT
        branch_id,
        name,
        code,
        alias,
        initials,
        address,
        phone_number,
        status,
        logo_url,
        created_at,
        updated_at
      FROM branches
      WHERE branch_id = $1
    `;
    const qNoLogo = `
      SELECT
        branch_id,
        name,
        code,
        alias,
        initials,
        address,
        phone_number,
        status,
        NULL::text AS logo_url,
        created_at,
        updated_at
      FROM branches
      WHERE branch_id = $1
    `;
    let result;
    try {
      result = await db.query(qWithLogo, [id]);
    } catch (e) {
      if (String(e.message || '').includes('logo_url')) {
        result = await db.query(qNoLogo, [id]);
      } else {
        throw e;
      }
    }

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

// Upload / hapus logo cabang (multipart field name: `logo`)
async function ensureBranchesLogoColumn() {
  await db.query('ALTER TABLE branches ADD COLUMN IF NOT EXISTS logo_url TEXT');
}

app.post(
  '/branches/:id/logo',
  requireRoles('superadmin'),
  (req, res, next) => {
    upload.single('logo')(req, res, (err) => {
      if (err) {
        return res.status(400).json({ error: err.message || 'Upload failed' });
      }
      next();
    });
  },
  async (req, res) => {
    try {
      await ensureBranchesLogoColumn();
      const id = parseInt(req.params.id, 10);
      if (!Number.isFinite(id)) {
        return res.status(400).json({ error: 'Invalid branch id' });
      }
      if (!req.file) {
        return res.status(400).json({ error: 'File logo wajib diisi (field: logo)' });
      }
      const urlPath = `/uploads/${req.file.filename}`;
      const result = await db.query(
        `UPDATE branches SET logo_url = $1, updated_at = now() WHERE branch_id = $2 RETURNING branch_id, logo_url`,
        [urlPath, id]
      );
      if (result.rowCount === 0) {
        return res.status(404).json({ error: 'Branch not found' });
      }
      res.status(200).json({ branch_id: String(id), logo_url: result.rows[0].logo_url });
    } catch (error) {
      console.error('Error uploading branch logo:', error);
      res.status(500).json({ error: 'Internal server error' });
    }
  }
);

app.delete('/branches/:id/logo', requireRoles('superadmin'), async (req, res) => {
  try {
    await ensureBranchesLogoColumn();
    const id = parseInt(req.params.id, 10);
    if (!Number.isFinite(id)) {
      return res.status(400).json({ error: 'Invalid branch id' });
    }
    const result = await db.query(
      `UPDATE branches SET logo_url = NULL, updated_at = now() WHERE branch_id = $1 RETURNING branch_id`,
      [id]
    );
    if (result.rowCount === 0) {
      return res.status(404).json({ error: 'Branch not found' });
    }
    res.json({ message: 'Logo cabang dihapus', branch_id: String(id) });
  } catch (error) {
    console.error('Error clearing branch logo:', error);
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

wss = attachWebSocketServer(server, wsPresence);

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

registerPaymentsCoreRoutes(app, {
  db,
  notifyClients: sendNotificationToClients,
});

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
    // Produksi: hanya jika ALLOW_LEGACY_PLAINTEXT_PASSWORD=true.
    // Non-produksi: default izinkan migrasi hash lama kecuali ALLOW_LEGACY_PLAINTEXT_PASSWORD=false.
    const allowLegacyPlaintext =
      process.env.ALLOW_LEGACY_PLAINTEXT_PASSWORD === 'true' ||
      (process.env.NODE_ENV !== 'production' &&
        process.env.ALLOW_LEGACY_PLAINTEXT_PASSWORD !== 'false');
    if (passwordHash.startsWith('$2')) {
      isPasswordValid = await bcrypt.compare(password, passwordHash);
    } else if (allowLegacyPlaintext) {
      // Legacy: hash tidak bcrypt — hanya jika ALLOW_LEGACY_PLAINTEXT_PASSWORD=true
      isPasswordValid = password === passwordHash;
      if (isPasswordValid) {
        const migratedHash = await bcrypt.hash(password, 10);
        await db.query(
          'UPDATE users SET password_hash = $1, updated_at = CURRENT_TIMESTAMP WHERE user_id = $2',
          [migratedHash, user.user_id]
        );
      }
    } else {
      isPasswordValid = false;
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
      `SELECT ubr.branch_id, b.name, b.alias, b.initials, array_agg(ubr.role) as roles
        FROM user_branch_roles ubr
        JOIN branches b ON ubr.branch_id = b.branch_id
        WHERE ubr.user_id = $1
        GROUP BY ubr.branch_id, b.name, b.alias, b.initials`,
      [user.user_id]
    );
    const roles = rolesResult.rows.map(r => r.role);
    // branches: array of objects {branch_id, name, alias, initials, roles}
    const branches = branchesWithRolesResult.rows.map(b => ({
      branch_id: b.branch_id,
      name: b.name,
      alias: b.alias,
      initials: b.initials,
      roles: b.roles,
    }));

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

/**
 * Tukar konteks JWT ke kombinasi cabang + peran yang valid di user_branch_roles.
 * Diperlukan karena login hanya mengembalikan satu assignment (primary) sementara
 * app bisa mengganti peran lewat UI tanpa login ulang — tanpa ini, JWT tetap berisi role lama.
 */
app.post('/api/auth/switch-context', async (req, res) => {
  try {
    const uid = req.user?.user_id;
    const username = req.user?.username;
    if (uid == null) {
      return res.status(401).json({ error: 'Unauthorized' });
    }
    const branchIdRaw = req.body?.branch_id ?? req.body?.branch;
    const roleRaw = req.body?.role;
    const branchIdNum = parseInt(String(branchIdRaw ?? '').trim(), 10);
    const role = (roleRaw ?? '').toString().trim().toLowerCase();
    if (!Number.isFinite(branchIdNum) || branchIdNum <= 0 || !role) {
      return res.status(400).json({ error: 'branch_id and role are required' });
    }
    const chk = await db.query(
      `
        SELECT 1
        FROM user_branch_roles
        WHERE user_id = $1
          AND branch_id = $2
          AND lower(trim(role::text)) = $3
        LIMIT 1
      `,
      [uid, branchIdNum, role]
    );
    if (chk.rows.length === 0) {
      return res.status(403).json({
        error: 'Forbidden',
        details: 'Kombinasi cabang dan peran tidak valid untuk akun ini.',
      });
    }
    const branchIdStr = String(branchIdNum);
    let mainModule = 'dashboard';
    switch (role) {
      case 'cs':
        mainModule = 'cs';
        break;
      case 'kasir':
        mainModule = 'kasir';
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
    const token = jwt.sign(
      {
        user_id: uid,
        username,
        role,
        branch_id: branchIdStr,
      },
      SECRET_KEY,
      { expiresIn: JWT_EXPIRES_IN }
    );
    res.status(200).json({
      success: true,
      token,
      role,
      branch: branchIdStr,
      mainModule,
    });
  } catch (error) {
    console.error('Error in switch-context:', error);
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
      total_akhir: r.total == null ? null : parseFloat(r.total),
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

// Order harian: juga lewat router /api (dashboard_orders) → GET /api/orders/daily.
app.get('/orders/daily', getOrdersDaily);

registerTransfersRoutes(app, { db });

// Endpoint untuk mendapatkan data mutasi stok (admin_toko)
app.get('/stock-mutations', async (req, res) => {
  try {
    const {
      branch_id,
      type,
      item_id,
      start_date,
      end_date,
      limit = 50,
      offset = 0,
    } = req.query;

    let query = `
      SELECT
        sm.*,
        i.name as item_name,
        i.material,
        i.purity,
        b.name as branch_name,
        u.username as created_by_name,
        o.order_type,
        o.order_number,
        o.created_at as order_created_at,
        cust.name as customer_name,
        cust.phone as customer_phone,
        ou.username as order_user_name,
        t.from_branch_id as transfer_from_branch_id,
        t.to_branch_id as transfer_to_branch_id,
        bfb.name as transfer_from_branch_name,
        btb.name as transfer_to_branch_name,
        appr.username as transfer_approved_by_username
      FROM stock_mutations sm
      LEFT JOIN items i ON sm.item_id = i.item_id
      LEFT JOIN branches b ON sm.branch_id = b.branch_id
      LEFT JOIN users u ON sm.created_by = u.user_id
      LEFT JOIN orders o
        ON sm.reference_type = 'order' AND sm.reference_id IS NOT NULL AND sm.reference_id = o.order_id
      LEFT JOIN customers cust ON o.customer_id = cust.customer_id
      LEFT JOIN users ou ON o.user_id = ou.user_id
      LEFT JOIN transfers t
        ON sm.reference_type = 'transfer' AND sm.reference_id IS NOT NULL AND sm.reference_id = t.transfer_id
      LEFT JOIN branches bfb ON t.from_branch_id = bfb.branch_id
      LEFT JOIN branches btb ON t.to_branch_id = btb.branch_id
      LEFT JOIN users appr ON t.approved_by = appr.user_id
      WHERE 1=1
    `;

    const params = [];
    let paramIndex = 1;

    const itemIdTrim = item_id != null ? String(item_id).trim() : '';
    const itemIdParsed =
      itemIdTrim !== '' ? parseInt(itemIdTrim, 10) : NaN;
    const itemScoped =
      Number.isFinite(itemIdParsed) && itemIdParsed > 0;

    // Filter cabang untuk daftar mutasi per cabang. Untuk riwayat per-item_id,
    // jangan filter branch_id — mutasi order di toko memakai branch_id toko,
    // sedangkan stockist gudang tetap perlu melihat alur penuh (transfer + jual).
    if (branch_id && !itemScoped) {
      query += ` AND sm.branch_id = $${paramIndex}`;
      params.push(branch_id);
      paramIndex++;
    }

    if (type) {
      query += ` AND sm.type = $${paramIndex}`;
      params.push(type);
      paramIndex++;
    }

    if (itemScoped) {
      query += ` AND sm.item_id = $${paramIndex}`;
      params.push(itemIdParsed);
      paramIndex++;
    }

    const startDateTrim =
      start_date != null ? String(start_date).trim() : '';
    const endDateTrim = end_date != null ? String(end_date).trim() : '';
    if (startDateTrim) {
      query += ` AND DATE(sm.created_at) >= $${paramIndex}`;
      params.push(startDateTrim);
      paramIndex++;
    }
    if (endDateTrim) {
      query += ` AND DATE(sm.created_at) <= $${paramIndex}`;
      params.push(endDateTrim);
      paramIndex++;
    }

    const lim = Math.min(Math.max(parseInt(String(limit), 10) || 50, 1), 200);
    const off = Math.max(parseInt(String(offset), 10) || 0, 0);
    query += ` ORDER BY sm.created_at DESC LIMIT $${paramIndex} OFFSET $${paramIndex + 1}`;
    params.push(lim, off);

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

registerWorkshopRoutes(app, { db });

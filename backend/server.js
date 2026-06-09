const { app, port, SECRET_KEY, JWT_EXPIRES_IN } = require('./app');
const express = require('express');
const multer = require('multer');
const path = require('path');
const cron = require('node-cron');
const rateLimit = require('express-rate-limit');
const db = require('./db');
const { ORDER_CALENDAR_TIMEZONE } = require('./lib/business_timezone');
const { authenticateToken, requireRoles } = require('./middleware/auth');
const { createUploadsAuthMiddleware } = require('./middleware/uploads_auth');
const { emitNotification } = require('./websocket/emit');
const { createWsPresenceRegistry } = require('./websocket/presence_registry');
const { attachWebSocketServer } = require('./websocket/attach');
const { local: localStorage } = require('./storage/storage.service');
const customersRoute = require('./routes/customers'); // Import customers route
const apiRoutes = require('./api'); // Import new API routes
const createDashboardOrdersRoute = require('./routes/dashboard_orders');
const branchesRoute = require('./routes/branches'); // Import branches route
const userInfoRoute = require('./routes/userInfo');
const getOrdersDaily = require('./routes/orders_daily_handler');
const { registerWorkshopRoutes } = require('./routes/workshop');
const { registerTransfersRoutes } = require('./routes/transfers');
const { registerPaymentsCoreRoutes } = require('./routes/payments_core');
const { createHealthRouter } = require('./routes/health');
const { registerLoginRoutes } = require('./routes/login');
const { registerEmployeesRoutes } = require('./routes/employees');
const { registerBranchesServerRoutes } = require('./routes/branches_server');
const { registerStockMutationsRoutes } = require('./routes/stock_mutations');
const { registerReportsRoutes } = require('./routes/reports');
const { registerUsersRoutes } = require('./routes/users');
const { registerOrdersCoreRoutes } = require('./routes/orders_core');
const { registerServerMiscRoutes } = require('./routes/server_misc');
const { registerAdminApiRoutes } = require('./routes/admin_api');
const { registerItemsRoutes } = require('./routes/items');
const { registerSuppliersRoutes } = require('./routes/suppliers');
const { registerImportDataRoutes } = require('./routes/import_data');
const { purgeExpiredIdempotency } = require('./lib/idempotency_helpers');


const authRequired = authenticateToken(SECRET_KEY);

/** Di-set setelah `attachWebSocketServer`; dipakai GET /health. */
let wss = null;

/** Presence WebSocket (JWT); dipakai superadmin active-sessions + kick. */
const wsPresence = createWsPresenceRegistry(SECRET_KEY);

// Login: bucket per username+IP, hanya hitung percobaan GAGAL (brute-force protection).
// Banyak user login bersamaan dari WiFi toko tidak saling memblokir.
const loginLimiter = rateLimit({
  windowMs: Number(process.env.LOGIN_RATE_LIMIT_WINDOW_MS) || 15 * 60 * 1000,
  max: Number(process.env.LOGIN_RATE_LIMIT_MAX) || 60,
  standardHeaders: true,
  legacyHeaders: false,
  skipSuccessfulRequests: true,
  keyGenerator: (req) => {
    const username = (req.body?.username ?? '').toString().trim().toLowerCase();
    const ip = req.ip ?? 'unknown';
    return username ? `login:${username}@${ip}` : `login-ip:${ip}`;
  },
  message: {
    error: 'Terlalu banyak percobaan login gagal. Coba lagi beberapa menit.',
  },
});

// Tulis data: skip GET/HEAD, bucket per user (JWT) bila sudah login.
const writeApiLimiter = rateLimit({
  windowMs: Number(process.env.WRITE_RATE_LIMIT_WINDOW_MS) || 60 * 1000,
  max: Number(process.env.WRITE_RATE_LIMIT_MAX) || 300,
  standardHeaders: true,
  legacyHeaders: false,
  skip: (req) => ['GET', 'HEAD', 'OPTIONS'].includes(req.method),
  keyGenerator: (req) => {
    const auth = req.headers.authorization;
    if (typeof auth === 'string' && auth.startsWith('Bearer ')) {
      return `write:${auth.slice(7, 40)}`;
    }
    return `write-ip:${req.ip ?? 'unknown'}`;
  },
  message: { error: 'Terlalu banyak permintaan. Coba lagi sebentar.' },
});

// Uploads: JWT required (Authorization header or ?access_token= for Image.network)
app.use(
  '/uploads',
  createUploadsAuthMiddleware(SECRET_KEY),
  express.static(path.join(__dirname, 'uploads')),
);

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
      'admin_warehouse',
      'manajer',
    )(req, res, next);
  }
  return requireRoles('superadmin', 'admin_toko', 'admin_workshop', 'admin_warehouse')(
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
app.use('/reports', authRequired, requireRoles('superadmin', 'manajer', 'owner'));
const suppliersAuth = [
  authRequired,
  requireRoles('superadmin', 'admin_warehouse', 'manajer'),
];
app.use('/suppliers', ...suppliersAuth);
app.use('/api/suppliers', ...suppliersAuth);
app.use('/api', authRequired);
registerLoginRoutes(app, { db, loginLimiter, SECRET_KEY, JWT_EXPIRES_IN });
app.use(
  '/api/workshop',
  authRequired,
  requireRoles('superadmin', 'admin_workshop', 'tukang', 'manajer', 'stockist', 'admin_warehouse')
);

registerImportDataRoutes(app, { db, authRequired, requireRoles });

app.use(
  '/workshop-orders',
  authRequired,
  requireRoles('superadmin', 'admin_toko', 'admin_workshop', 'admin_warehouse', 'tukang', 'stockist', 'manajer')
);
app.use('/technicians', authRequired, requireRoles('superadmin', 'admin_workshop'));
app.use('/test-db', authRequired, requireRoles('superadmin'));
app.use(['/orders', '/payments', '/transfers', '/items', '/stock-mutations', '/employees', '/branches', '/users', '/store-operational', '/suppliers'], writeApiLimiter);

function sendNotificationToClients(message, options = {}) {
  console.log(`Broadcasting message: ${message}`);
  emitNotification(wss, message, options);
}

// Pecahan domain routes (rencana B)
registerServerMiscRoutes(app, { db, upload });
registerPaymentsCoreRoutes(app, { db, notifyClients: sendNotificationToClients });
registerTransfersRoutes(app, { db });
registerItemsRoutes(app, { db });
registerSuppliersRoutes(app, { db });
registerBranchesServerRoutes(app, { db, requireRoles, upload });
registerEmployeesRoutes(app, { db });
registerOrdersCoreRoutes(app, {
  db,
  upload,
  notifyClients: sendNotificationToClients,
  getOrdersDaily,
});
registerUsersRoutes(app, { db });
registerReportsRoutes(app, { db });
registerStockMutationsRoutes(app, { db });

app.use('/api', customersRoute);
app.use('/api', apiRoutes);
app.use('/api', createDashboardOrdersRoute(sendNotificationToClients));
app.use('/api', branchesRoute);
app.use('/api', userInfoRoute);

registerWorkshopRoutes(app, { db, notifyClients: sendNotificationToClients });

// Admin API (backup lokal/Drive, sesi aktif) — didaftarkan terakhir agar tidak tertutup router /api lain.
registerAdminApiRoutes(app, {
  db,
  wsPresence,
  orderCalendarTimezone: ORDER_CALENDAR_TIMEZONE,
  requireRoles,
  authRequired,
});

const server = app.listen(port, '0.0.0.0', () => {
  console.log('[routes] POST /api/admin/backup/local (superadmin backup lokal)');
  console.log(`Server running at http://0.0.0.0:${port}`);
  console.log(`Accessible at http://localhost:${port} and http://10.0.2.2:${port} (Android emulator)`);
});

wss = attachWebSocketServer(server, wsPresence);

cron.schedule('0 9 * * *', () => {
  console.log('Mengirim pengingat harian ke semua pengguna pada pukul 09:00');
  sendNotificationToClients('Jangan lupa untuk memeriksa stok dan pesanan hari ini!');
});

cron.schedule('0 3 * * *', async () => {
  try {
    const removed = await purgeExpiredIdempotency(db, 30);
    if (removed > 0) {
      console.log(`[idempotency] Purged ${removed} expired row(s)`);
    }
  } catch (e) {
    console.warn('[idempotency] purge failed:', e.message);
  }
});

console.log('Cron job untuk pengingat otomatis telah diaktifkan.');

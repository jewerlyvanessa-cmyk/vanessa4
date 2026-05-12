const express = require('express');
const db = require('../db');
const {
  getOrderItemsPkColumn: _getOrderItemsPkColumn,
  orderItemLineAmountSql: _orderItemLineAmountSql,
} = require('./order_items_sql');

const ORDER_CALENDAR_TIMEZONE =
  /^[\w/-]+$/.test(String(process.env.BUSINESS_TIMEZONE || '').trim())
    ? String(process.env.BUSINESS_TIMEZONE).trim()
    : 'Asia/Jakarta';

const { computeOrderTodayStats } = require('../lib/order_today_stats_compute');
const getOrdersDaily = require('./orders_daily_handler');
const multer = require('multer');
const _path = require('path');
const crypto = require('crypto');

const router = express.Router();

// Configure multer for file uploads
const allowedUploadMimeTypes = new Set(['image/jpeg', 'image/png', 'image/webp']);
const uploadExtByMime = {
  'image/jpeg': 'jpg',
  'image/png': 'png',
  'image/webp': 'webp',
};

function createSafeUploadFilename(file) {
  const ext = uploadExtByMime[file.mimetype] || 'bin';
  return `${Date.now()}-${crypto.randomUUID()}.${ext}`;
}

const storage = multer.diskStorage({
  destination: (req, file, cb) => {
    cb(null, 'uploads/');
  },
  filename: (req, file, cb) => {
    cb(null, createSafeUploadFilename(file));
  },
});

const upload = multer({
  storage,
  limits: { fileSize: 5 * 1024 * 1024 },
  fileFilter: (req, file, cb) => {
    if (!allowedUploadMimeTypes.has(file.mimetype)) {
      cb(new Error('Only JPEG, PNG, and WEBP uploads are allowed'));
      return;
    }
    cb(null, true);
  },
});

// GET /api/dashboard/order-today
// Returns today's order statistics for dashboard
router.get('/dashboard/order-today', async (req, res) => {
  const r = await computeOrderTodayStats(req);
  if (!r.ok) {
    return res.status(r.status).json(r.body);
  }
  return res.json(r.data);
});

// GET /api/dashboard/order-today-snapshot
// Satu respons: stats (sama seperti order-today) + orders flat (sama seperti /api/orders/daily).
// Hanya satu hari: tolak date_from/date_to; gunakan ?date=YYYY-MM-DD seperti order-today.
router.get('/dashboard/order-today-snapshot', async (req, res) => {
  try {
    const dfClient = String(req.query.date_from ?? '').trim();
    const dtClient = String(req.query.date_to ?? '').trim();
    if (dfClient.length > 0 || dtClient.length > 0) {
      return res.status(400).json({
        error:
          'Snapshot hanya mendukung satu hari (parameter date). Untuk rentang gunakan /dashboard/order-today.',
      });
    }
    const statsResult = await computeOrderTodayStats(req);
    if (!statsResult.ok) {
      return res.status(statsResult.status).json(statsResult.body);
    }
    const dailyResult = await getOrdersDaily.fetchOrdersDailyPayload(req);
    if (!dailyResult.ok) {
      return res.status(dailyResult.status).json(dailyResult.body);
    }
    return res.json({
      stats: statsResult.data,
      orders: dailyResult.rows,
    });
  } catch (error) {
    console.error('Error order-today-snapshot:', error);
    res.status(500).json({
      error: 'Internal server error',
      detail: error && error.message ? String(error.message) : undefined,
    });
  }
});

// GET /api/orders/today
// Returns list of today's orders with complete item details
router.get('/orders/today', async (req, res) => {
  try {
    const branchId = req.query.branch_id || 1;
    const localToday = new Intl.DateTimeFormat('en-CA', {
      timeZone: ORDER_CALENDAR_TIMEZONE,
      year: 'numeric',
      month: '2-digit',
      day: '2-digit',
    }).format(new Date());

    const query = `
      SELECT
        o.order_id,
        o.order_type,
        o.status,
        o.total as total_amount,
        o.created_at,
        o.updated_at,
        c.customer_id,
        c.name as customer_name,
        c.phone as customer_phone,
        c.address as customer_address,
        oi.order_item_id,
        oi.nama_item,
        oi.weight,
        oi.harga_per_gram,
        oi.qty,
        oi.jumlah as item_jumlah,
        i.kategori,
        i.jenis,
        i.tipe,
        i.material,
        i.purity as kadar
      FROM orders o
      LEFT JOIN customers c ON o.customer_id = c.customer_id
      LEFT JOIN order_items oi ON o.order_id = oi.order_id
      LEFT JOIN items i ON oi.item_id = i.item_id
      WHERE (timezone('${ORDER_CALENDAR_TIMEZONE}', o.created_at))::date = $1::date
      AND o.branch_id = $2
      ORDER BY o.created_at DESC, o.order_id DESC, oi.order_item_id ASC
    `;

    const result = await db.query(query, [localToday, branchId]);

    // Group orders and their items
    const ordersMap = new Map();

    result.rows.forEach(row => {
      const orderId = row.order_id;

      if (!ordersMap.has(orderId)) {
        // Create order object
        ordersMap.set(orderId, {
          order_id: row.order_id,
          type: row.order_type,
          status: row.status,
          total_amount: parseFloat(row.total_amount) || 0,
          created_at: row.created_at,
          updated_at: row.updated_at,
          customer_id: row.customer_id,
          customer_name: row.customer_name || 'Unknown Customer',
          customer_phone: row.customer_phone,
          customer_address: row.customer_address,
          items: []
        });
      }

      // Add item to order if it exists
      if (row.order_item_id) {
        const line = parseFloat(row.item_jumlah) || 0;
        ordersMap.get(orderId).items.push({
          id: row.order_item_id,
          nama_item: row.nama_item,
          weight: parseFloat(row.weight) || 0,
          harga_per_gram: parseFloat(row.harga_per_gram) || 0,
          qty: parseInt(row.qty, 10) || 0,
          jumlah: line,
          diskon: 0,
          total: line,
          total_akhir: line,
          terbilang: null,
          kategori: row.kategori,
          jenis: row.jenis,
          tipe: row.tipe,
          material: row.material,
          kadar: row.kadar
        });
      }
    });

    const orders = Array.from(ordersMap.values());
    res.json(orders);
  } catch (error) {
    console.error('Error fetching today orders:', error);
    res.status(500).json({
      error: 'Internal server error',
      detail: error && error.message ? String(error.message) : undefined,
    });
  }
});

// POST /orders
// Create new order (Service, Buyback, Custom)
router.post('/orders', async (req, res) => {
  const client = await db.connect();

  try {
    await client.query('BEGIN');

    const {
      customer_id,
      order_type,
      item_name,
      weight,
      material,
      purity,
      description,
      price,
      specification,
      target_weight,
      estimation_time,
      photo_produk,
      scanned_qr,
      branch_id = 1,
      user_id,
      // Jual order specific fields
      customer_name: _customer_name,
      customer_phone: _customer_phone,
      customer_address: _customer_address,
      nama_item,
      jual_weight,
      kategori: _kategori,
      jenis: _jenis,
      tipe: _tipe,
      kadar: _kadar,
      qty,
      harga_per_gram,
      jumlah,
      diskon,
      total,
      total_akhir,
      terbilang,
      foto_new,
      mode,
      status: _statusFromRequest,
    } = req.body;

    // Validate required fields based on order type
    if (!customer_id || !order_type) {
      return res.status(400).json({ error: 'customer_id and order_type are required' });
    }

    // Determine status based on order type
    let status;
    switch (order_type) {
      case 'service':
      case 'custom':
        // Sama seperti POST /orders utama: cabang toko dulu (pending), workshop setelah gudang.
        status = 'pending';
        break;
      case 'buyback':
        status = 'buyback';
        break;
      case 'jual':
        status = req.body.status || 'pending'; // Use status from request or default to 'pending'
        break;
      default:
        return res.status(400).json({ error: 'Invalid order_type' });
    }

    // Insert order - handle different order types
    let orderQuery, orderValues;

    if (order_type === 'jual') {
      // Jual order insertion
      orderQuery = `
        INSERT INTO orders (
          customer_id,
          order_type,
          jumlah,
          diskon,
          total,
          total_akhir,
          harga_per_gram,
          mode,
          status,
          terbilang,
          qty,
          foto_new,
          user_id,
          branch_id,
          created_at,
          updated_at
        ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, NOW(), NOW())
        RETURNING order_id
      `;

      orderValues = [
        customer_id,
        order_type,
        jumlah,
        diskon || 0,
        total,
        total_akhir,
        harga_per_gram,
        mode,
        status,
        terbilang,
        qty || 1,
        foto_new || photo_produk,
        user_id,
        branch_id,
      ];
    } else {
      // Service/Buyback/Custom order insertion
      orderQuery = `
        INSERT INTO orders (
          customer_id,
          order_type,
          item_name,
          weight,
          material,
          purity,
          description,
          price,
          specification,
          target_weight,
          estimation_time,
          photo_url,
          scanned_qr,
          status,
          branch_id,
          user_id,
          created_at,
          updated_at
        ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15, $16, NOW(), NOW())
        RETURNING order_id
      `;

      orderValues = [
        customer_id,
        order_type,
        item_name,
        weight,
        material,
        purity,
        description,
        price,
        specification,
        target_weight,
        estimation_time,
        photo_produk,
        scanned_qr,
        status,
        branch_id,
        user_id,
      ];
    }

    const orderResult = await client.query(orderQuery, orderValues);
    const orderId = orderResult.rows[0].order_id;

    // Create item/order_items record if needed
    if (order_type === 'jual') {
      // Create order_items record for jual orders
      const orderItemQuery = `
        INSERT INTO order_items (
          order_id,
          nama_item,
          weight,
          harga_per_gram,
          jumlah,
          diskon,
          total,
          total_akhir,
          terbilang
        ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)
      `;

      const orderItemValues = [
        orderId,
        nama_item,
        jual_weight,
        harga_per_gram,
        jumlah,
        diskon || 0,
        total,
        total_akhir,
        terbilang,
      ];

      await client.query(orderItemQuery, orderItemValues);
    } else if (order_type === 'buyback' || order_type === 'service') {
      // Create item record for buyback/service orders
      const itemQuery = `
        INSERT INTO items (
          name,
          weight,
          material,
          purity,
          status,
          branch_id,
          photo_produk,
          created_at,
          updated_at
        ) VALUES ($1, $2, $3, $4, $5, $6, $7, NOW(), NOW())
        RETURNING item_id
      `;

      const itemValues = [
        item_name,
        weight,
        material,
        purity,
        'active', // default status
        branch_id,
        photo_produk,
      ];

      const itemResult = await client.query(itemQuery, itemValues);
      const itemId = itemResult.rows[0].item_id;

      // Update order with item_id
      await client.query(
        'UPDATE orders SET item_id = $1 WHERE order_id = $2',
        [itemId, orderId]
      );
    }

    await client.query('COMMIT');

    res.status(201).json({
      success: true,
      order_id: orderId,
      message: 'Order created successfully',
    });

  } catch (error) {
    await client.query('ROLLBACK');
    console.error('Error creating order:', error);
    res.status(500).json({ error: 'Internal server error' });
  } finally {
    client.release();
  }
});

// GET /api/customers
// Get customers for autocomplete
router.get('/customers', async (req, res) => {
  try {
    const search = req.query.search || '';
    const limit = parseInt(req.query.limit) || 20;

    let query;
    let params;

    if (search) {
      query = `
        SELECT customer_id, name, phone, address
        FROM customers
        WHERE name ILIKE $1 OR phone ILIKE $1
        ORDER BY name
        LIMIT $2
      `;
      params = [`%${search}%`, limit];
    } else {
      query = `
        SELECT customer_id, name, phone, address
        FROM customers
        ORDER BY name
        LIMIT $1
      `;
      params = [limit];
    }

    const result = await db.query(query, params);

    const customers = result.rows.map(row => ({
      id: row.customer_id,
      name: row.name,
      phone: row.phone,
      address: row.address,
    }));

    res.json({ customers });
  } catch (error) {
    console.error('Error fetching customers:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// POST /upload
// Upload file (photo)
router.post('/upload', upload.single('photo'), async (req, res) => {
  try {
    if (!req.file) {
      return res.status(400).json({ error: 'No file uploaded' });
    }

    // Return file URL
    const fileUrl = `/uploads/${req.file.filename}`;

    // Persist upload metadata (safe: filename is server-generated)
    const uploaderUserId = req.user?.user_id ? parseInt(req.user.user_id, 10) : null;
    const upRes = await db.query(
      `INSERT INTO uploads (storage_key, original_name, mime_type, size_bytes, url_path, uploaded_by_user_id)
       VALUES ($1, $2, $3, $4, $5, $6)
       RETURNING upload_id`,
      [
        req.file.filename,
        req.file.originalname || null,
        req.file.mimetype || null,
        typeof req.file.size === 'number' ? req.file.size : null,
        fileUrl,
        Number.isFinite(uploaderUserId) ? uploaderUserId : null,
      ]
    );

    res.json({
      success: true,
      url: fileUrl,
      filename: req.file.filename,
      upload_id: upRes.rows[0]?.upload_id ?? null,
    });
  } catch (error) {
    console.error('Error uploading file:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

router.get('/orders/daily', getOrdersDaily);

module.exports = router;

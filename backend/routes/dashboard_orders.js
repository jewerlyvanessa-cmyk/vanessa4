const express = require('express');
const db = require('../db');
const multer = require('multer');
const path = require('path');
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
  try {
    const branchId = req.query.branch_id || 1; // Default branch_id for now
    const userId = req.query.user_id; // Optional user_id filter

    // Get today's date in YYYY-MM-DD format (local date)
    const today = new Date();
    const year = today.getFullYear();
    const month = String(today.getMonth() + 1).padStart(2, '0');
    const day = String(today.getDate()).padStart(2, '0');
    const localToday = `${year}-${month}-${day}`;

    // Build WHERE clause for filtering
    let whereClause = `WHERE DATE(o.created_at) = $1 AND o.branch_id = $2`;
    let queryParams = [localToday, branchId];
    let paramIndex = 3;

    if (userId) {
      whereClause += ` AND o.user_id = $${paramIndex}`;
      queryParams.push(userId);
      paramIndex++;
    }

    // Query for order statistics
    const statsQuery = `
      SELECT
        COUNT(DISTINCT o.order_id) as total_orders,
        COUNT(DISTINCT CASE WHEN o.status = 'completed' THEN o.order_id END) as completed_orders,
        COUNT(DISTINCT CASE WHEN o.status != 'completed' THEN o.order_id END) as pending_orders,
        COUNT(DISTINCT CASE WHEN o.order_type = 'jual' THEN o.order_id END) as jual_count,
        COUNT(DISTINCT CASE WHEN o.order_type = 'buyback' THEN o.order_id END) as buyback_count,
        COUNT(DISTINCT CASE WHEN o.order_type = 'service' THEN o.order_id END) as service_count,
        COUNT(DISTINCT CASE WHEN o.order_type = 'custom' THEN o.order_id END) as custom_count,
        COALESCE(SUM(CASE WHEN o.order_type = 'buyback' THEN oi.total ELSE 0 END), 0) as total_revenue
      FROM orders o
      LEFT JOIN order_items oi ON o.order_id = oi.order_id
      ${whereClause}
    `;

    const statsResult = await db.query(statsQuery, queryParams);
    const stats = statsResult.rows[0];

    // Format response
    const response = {
      total_orders: parseInt(stats.total_orders) || 0,
      completed_orders: parseInt(stats.completed_orders) || 0,
      pending_orders: parseInt(stats.pending_orders) || 0,
      orders_by_type: {
        jual: parseInt(stats.jual_count) || 0,
        buyback: parseInt(stats.buyback_count) || 0,
        service: parseInt(stats.service_count) || 0,
        custom: parseInt(stats.custom_count) || 0,
      },
      orders_by_status: {
        draft: 0, // Will be calculated from actual data
        reserved: 0,
        sold: 0,
        buyback: 0,
        'on-service': 0,
        production: 0,
      },
      total_revenue: parseFloat(stats.total_revenue) || 0,
      date: new Date().toISOString(),
    };

    // Get status breakdown
    const statusQuery = `
      SELECT status, COUNT(*) as count
      FROM orders o
      LEFT JOIN order_items oi ON o.order_id = oi.order_id
      ${whereClause}
      GROUP BY status
    `;

    const statusResult = await db.query(statusQuery, queryParams);
    statusResult.rows.forEach(row => {
      response.orders_by_status[row.status] = parseInt(row.count);
    });

    res.json(response);
  } catch (error) {
    console.error('Error fetching order today stats:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// GET /api/orders/today
// Returns list of today's orders with complete item details
router.get('/orders/today', async (req, res) => {
  try {
    const branchId = req.query.branch_id || 1;
    // Use local date instead of UTC date
    const today = new Date();
    const year = today.getFullYear();
    const month = String(today.getMonth() + 1).padStart(2, '0');
    const day = String(today.getDate()).padStart(2, '0');
    const localToday = `${year}-${month}-${day}`;

    const query = `
      SELECT
        o.order_id,
        o.order_type,
        o.status,
        o.total_akhir as total_amount,
        o.created_at,
        o.updated_at,
        c.customer_id,
        c.name as customer_name,
        c.phone as customer_phone,
        c.address as customer_address,
        oi.id as order_item_id,
        oi.nama_item,
        oi.weight,
        oi.harga_per_gram,
        oi.jumlah,
        oi.diskon,
        oi.total,
        oi.total_akhir as item_total_akhir,
        oi.terbilang,
        i.kategori,
        i.jenis,
        i.tipe,
        i.material,
        i.purity as kadar
      FROM orders o
      LEFT JOIN customers c ON o.customer_id = c.customer_id
      LEFT JOIN order_items oi ON o.order_id = oi.order_id
      LEFT JOIN items i ON o.item_id = i.item_id
      WHERE DATE(o.created_at) = $1
      AND o.branch_id = $2
      ORDER BY o.created_at DESC, o.order_id DESC, oi.id ASC
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
        ordersMap.get(orderId).items.push({
          id: row.order_item_id,
          nama_item: row.nama_item,
          weight: parseFloat(row.weight) || 0,
          harga_per_gram: parseFloat(row.harga_per_gram) || 0,
          jumlah: parseFloat(row.jumlah) || 0,
          diskon: parseFloat(row.diskon) || 0,
          total: parseFloat(row.total) || 0,
          total_akhir: parseFloat(row.item_total_akhir) || 0,
          terbilang: row.terbilang,
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
    res.status(500).json({ error: 'Internal server error' });
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
      customer_name,
      customer_phone,
      customer_address,
      nama_item,
      jual_weight,
      kategori,
      jenis,
      tipe,
      kadar,
      qty,
      harga_per_gram,
      jumlah,
      diskon,
      total,
      total_akhir,
      terbilang,
      foto_new,
      mode,
      status: statusFromRequest,
    } = req.body;

    // Validate required fields based on order type
    if (!customer_id || !order_type) {
      return res.status(400).json({ error: 'customer_id and order_type are required' });
    }

    // Determine status based on order type
    let status;
    switch (order_type) {
      case 'service':
        status = 'in_workshop';
        break;
      case 'buyback':
        status = 'buyback';
        break;
      case 'custom':
        status = 'custom_work';
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
        foto_new || photo_url,
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

module.exports = router;

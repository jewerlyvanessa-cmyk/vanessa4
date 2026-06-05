'use strict';

const { ordersHasPickupBranchColumn } = require('../lib/orders_workshop_helpers');
const {
  getItemsPhotoColumn,
  getOrderItemsPhotoColumn,
  roundUpToNearest5000,
} = require('../lib/orders_http_helpers');

function registerOrdersReadRoutes(app, deps) {
  const { db, getOrdersDaily } = deps;

  app.get('/orders', async (req, res) => {
    try {
      const { branch_id, status, order_number: orderNumberRaw, order_id: orderIdRaw } = req.query;
      const sn = orderNumberRaw != null ? String(orderNumberRaw).trim() : '';
      const oidParsed = orderIdRaw != null && String(orderIdRaw).trim() !== ''
        ? parseInt(String(orderIdRaw).trim(), 10)
        : NaN;
      const lookupByOrderId = Number.isFinite(oidParsed) && oidParsed > 0;
      const singleOrderLookup = Boolean(sn || lookupByOrderId);
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
          u.username AS created_by_username,
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
        LEFT JOIN users u ON u.user_id = o.user_id
        LEFT JOIN customers c ON o.customer_id = c.customer_id
        LEFT JOIN order_items oi ON o.order_id = oi.order_id
        LEFT JOIN items i ON oi.item_id = i.item_id
      `;
      const params = [];
      const conditions = [];
  
      if (branch_id && !singleOrderLookup) {
        conditions.push(`o.branch_id = $${params.length + 1}`);
        params.push(branch_id);
      }
  
      if (status) {
        conditions.push(`o.status = $${params.length + 1}`);
        params.push(status);
      }
  
      if (sn) {
        conditions.push(`LOWER(TRIM(o.order_number)) = $${params.length + 1}`);
        params.push(sn.toLowerCase());
      } else if (lookupByOrderId) {
        conditions.push(`o.order_id = $${params.length + 1}`);
        params.push(oidParsed);
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
  
      if (singleOrderLookup) {
        // Satu order lengkap + items[] — sama untuk lookup by order_number atau order_id (QR faktur fallback).
        console.log('Processing single order lookup:', sn ? `order_number=${sn}` : `order_id=${oidParsed}`);
        if (result.rows.length === 0) {
          console.log('No rows found for lookup');
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

  // Konteks cetak faktur: payment summary + logo cabang + item conditions (satu round-trip).
  app.get('/orders/faktur-context', async (req, res) => {
    try {
      const orderIdRaw = (req.query.order_id ?? '').toString().trim();
      const orderId = parseInt(orderIdRaw, 10);
      if (!Number.isFinite(orderId) || orderId <= 0) {
        return res.status(400).json({ error: 'order_id harus berupa angka' });
      }

      const pickupBranchIdRaw = (req.query.pickup_branch_id ?? '').toString().trim();
      const pickupBranchId = pickupBranchIdRaw
        ? parseInt(pickupBranchIdRaw, 10)
        : null;

      const ordRes = await db.query(
        `SELECT o.order_id, o.order_type, o.branch_id, o.pickup_branch_id, o.metadata, o.total,
                o.user_id, u.username AS created_by_username
         FROM orders o
         LEFT JOIN users u ON u.user_id = o.user_id
         WHERE o.order_id = $1
         LIMIT 1`,
        [orderId]
      );
      if (ordRes.rows.length === 0) {
        return res.status(404).json({ error: 'Order tidak ditemukan' });
      }
      const order = ordRes.rows[0];

      const branchIds = new Set();
      if (order.branch_id != null) branchIds.add(Number(order.branch_id));
      if (Number.isFinite(pickupBranchId) && pickupBranchId > 0) {
        branchIds.add(pickupBranchId);
      } else if (order.pickup_branch_id != null) {
        branchIds.add(Number(order.pickup_branch_id));
      }

      let meta = order.metadata;
      if (typeof meta === 'string') {
        try {
          meta = JSON.parse(meta);
        } catch (_) {
          meta = {};
        }
      }
      if (meta && meta.pickup_branch_id != null) {
        const pb = parseInt(String(meta.pickup_branch_id), 10);
        if (Number.isFinite(pb) && pb > 0) branchIds.add(pb);
      }

      const branchIdList = Array.from(branchIds).filter(
        (id) => Number.isFinite(id) && id > 0
      );

      const [sumRes, branchesRes, condRes] = await Promise.all([
        db.query(
          `
            SELECT
              COALESCE(SUM(CASE WHEN status = 'pending' THEN COALESCE(amount, 0) ELSE 0 END), 0)::float8 AS dp_amount,
              COALESCE(SUM(CASE WHEN status = 'completed' THEN COALESCE(amount, 0) ELSE 0 END), 0)::float8 AS paid_completed_amount,
              COALESCE(SUM(CASE WHEN status IN ('pending','completed') THEN COALESCE(amount, 0) ELSE 0 END), 0)::float8 AS paid_amount
            FROM payments
            WHERE order_id = $1
          `,
          [orderId]
        ),
        branchIdList.length > 0
          ? db.query(
              `
                SELECT branch_id, name, alias, logo_url
                FROM branches
                WHERE branch_id = ANY($1::bigint[])
              `,
              [branchIdList]
            )
          : Promise.resolve({ rows: [] }),
        db.query(
          `
            SELECT
              condition_id,
              item_id,
              order_id,
              kondisi_fisik,
              penyesuaian_berat,
              nilai_resale,
              harga_per_gram,
              potongan_kondisi,
              untung_rugi,
              nilai_untung_rugi,
              catatan_kondisi
            FROM item_conditions
            WHERE order_id = $1
            ORDER BY created_at DESC
            LIMIT 30
          `,
          [orderId]
        ),
      ]);

      const total = parseFloat(order.total || 0);
      const row = sumRes.rows[0] || {};
      const dpAmount = parseFloat(row.dp_amount || 0);
      const paidAmount = parseFloat(row.paid_amount || 0);
      const remaining = Math.max(total - paidAmount, 0);

      const branches = (branchesRes.rows || []).map((b) => ({
        branch_id: b.branch_id != null ? String(b.branch_id) : '',
        name: b.name ?? '',
        alias: b.alias ?? '',
        logo_url: b.logo_url ?? '',
      }));

      const itemConditions = (condRes.rows || []).map((ic) => ({
        condition_id: ic.condition_id != null ? String(ic.condition_id) : '',
        item_id: ic.item_id != null ? String(ic.item_id) : '',
        order_id: ic.order_id != null ? String(ic.order_id) : '',
        kondisi_fisik: ic.kondisi_fisik,
        penyesuaian_berat: ic.penyesuaian_berat,
        nilai_resale: parseFloat(ic.nilai_resale || 0),
        harga_per_gram: parseFloat(ic.harga_per_gram || 0),
        potongan_kondisi: parseFloat(ic.potongan_kondisi || 0),
        untung_rugi: ic.untung_rugi,
        nilai_untung_rugi: parseFloat(ic.nilai_untung_rugi || 0),
        catatan_kondisi: ic.catatan_kondisi,
        kerusakan: [],
      }));

      const creatorUsername = (order.created_by_username ?? '').toString().trim();

      return res.status(200).json({
        order_id: orderId,
        user_id: order.user_id != null ? String(order.user_id) : '',
        created_by_username: creatorUsername || null,
        created_by_name: creatorUsername || null,
        cs_name: creatorUsername || null,
        payment_summary: {
          order_id: orderId,
          total,
          dp_amount: dpAmount,
          paid_amount: paidAmount,
          remaining_amount: remaining,
        },
        branches,
        item_conditions: itemConditions,
      });
    } catch (e) {
      console.error('Error fetching faktur context:', e);
      return res.status(500).json({ error: 'Internal server error' });
    }
  });
  
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
          o.status,
          o.total,
          o.diskon,
          o.created_at,
          o.updated_at,
          c.name AS customer_name,
          c.phone,
          c.address,
          (
            SELECT p.method
            FROM payments p
            WHERE p.order_id = o.order_id
              AND p.status = 'pending'
            ORDER BY COALESCE(p.payment_date, p.created_at) DESC NULLS LAST,
              p.payment_id DESC NULLS LAST
            LIMIT 1
          ) AS payment_method,
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
          status: row.status,
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
          amount: remaining,
          payment_method: row.payment_method ?? null,
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
  app.get('/order-items', async (req, res) => {
    try {
      const baseSelect = `
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
      `;
  
      const oidSingle = parseInt(String(req.query.order_id ?? '').trim(), 10);
      if (Number.isFinite(oidSingle) && oidSingle > 0) {
        const q = `${baseSelect}
          WHERE o.order_id = $1 AND o.order_type = 'jual'
          ORDER BY oi.order_item_id ASC`;
        const result = await db.query(q, [oidSingle]);
        return res.json(result.rows);
      }
  
      const idsRaw = String(req.query.order_ids ?? req.query.order_id_list ?? '')
        .trim();
      if (idsRaw.length > 0) {
        const ids = idsRaw
          .split(/[\s,]+/)
          .map((s) => parseInt(s.trim(), 10))
          .filter((n) => Number.isFinite(n) && n > 0);
        const uniq = [...new Set(ids)].slice(0, 500);
        if (uniq.length > 0) {
          const q = `${baseSelect}
            WHERE o.order_id = ANY($1::bigint[]) AND o.order_type = 'jual'
            ORDER BY o.created_at DESC, oi.order_item_id ASC`;
          const result = await db.query(q, [uniq]);
          return res.json(result.rows);
        }
      }
  
      let cap = parseInt(String(req.query.limit ?? '').trim(), 10);
      if (!Number.isFinite(cap) || cap <= 0) cap = 500;
      cap = Math.min(cap, 2000);
  
      const q = `${baseSelect}
        WHERE o.order_type = 'jual'
        ORDER BY o.created_at DESC
        LIMIT ${cap}`;
      const result = await db.query(q);
      return res.json(result.rows);
    } catch (error) {
      console.error('Error fetching order items:', error);
      res.status(500).json({ error: 'Failed to fetch order items' });
    }
  });

  app.get('/orders/daily', getOrdersDaily);

}

module.exports = { registerOrdersReadRoutes };

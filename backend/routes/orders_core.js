'use strict';

const {
  ordersHasMetadataColumn,
  ordersHasPickupBranchColumn,
  orderAllowedForStorePickup,
  ordersEstimateColumns,
} = require('../lib/orders_workshop_helpers');
const {
  ordersHasPickedUpAtColumn,
  paymentsHasRevenueBranchColumn,
} = require('../lib/payments_schema_helpers');
const {
  getItemsColumnFlags,
  itemSelectStockFields,
  insertManualOrderItem,
  formatDbErrorForClient,
  updateItemStatusAndStock,
  defaultItemsPhotoColumnName,
} = require('../lib/items_schema_helpers');
const {
  roundUpToNearest5000,
  getItemsPhotoColumn,
  getOrderItemsPhotoColumn,
  getItemConditionsColumns,
  getOrdersJumlahColumnMode,
} = require('../lib/orders_http_helpers');
const { ORDER_CALENDAR_TIMEZONE } = require('../lib/business_timezone');
const { resolveNotaOrder } = require('../lib/order_nota_helpers');
const {
  timestampOnBusinessDateSql,
  timestampOnBusinessDateBetweenSql,
} = require('../lib/order_calendar_date_sql');

function registerOrdersCoreRoutes(app, deps) {
  const { db, upload, notifyClients, getOrdersDaily } = deps;

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
        `SELECT order_id, order_type, branch_id, pickup_branch_id, metadata, total
         FROM orders
         WHERE order_id = $1
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

      return res.status(200).json({
        order_id: orderId,
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
      const hasRevenueCol = await paymentsHasRevenueBranchColumn(client);
      const hasPickedUpCols = await ordersHasPickedUpAtColumn(client);
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
  
      // Sama dengan GET /orders/ready-for-pickup-list (cabang toko + admin toko sudah «Terima»).
      const branchOk = await orderAllowedForStorePickup(
        client,
        ord.order_id,
        branchId,
        hasPickupBranchCol,
        hasMetadataCol,
        hasRevenueCol,
      );
      if (!branchOk) {
        await client.query('ROLLBACK');
        return res.status(403).json({
          error:
            'Order tidak dapat diambil di cabang ini. Pastikan barang sudah «Terima» admin toko dan muncul di daftar siap ambil.',
        });
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
  
      const pickedByRaw = req.user?.user_id ?? req.user?.id ?? null;
      const pickedBy =
        pickedByRaw != null ? parseInt(String(pickedByRaw), 10) : null;
      const notesText = (notes ?? '').toString();
      const photoText = (photo_url ?? '').toString() || null;
  
      if (hasPickedUpCols) {
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
          [nextStatus, pickedBy, notesText, photoText, ord.order_id]
        );
      } else {
        await client.query(
          `
            UPDATE orders
            SET status = $1,
                updated_at = NOW()
            WHERE order_id = $2
          `,
          [nextStatus, ord.order_id]
        );
      }
  
      await client.query('COMMIT');
      notifyClients(`Order ${ord.order_id} (${ot}) telah diambil customer, status ${nextStatus}`);
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
      const detail =
        process.env.NODE_ENV !== 'production' && e?.message
          ? String(e.message)
          : undefined;
      return res.status(500).json({
        error: 'Internal server error',
        ...(detail ? { detail } : {}),
      });
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
  
  function assertStoreOperationalCategoryManager(req, res) {
    const role = (req.user?.role ?? '').toString().trim().toLowerCase();
    if (role === 'manajer' || role === 'superadmin' || role === 'owner') {
      return true;
    }
    res.status(403).json({ error: 'Hanya manajer dapat mengelola kategori' });
    return false;
  }

  function mapStoreOperationalCategoryRow(r) {
    return {
      category_id: r.category_id != null ? String(r.category_id) : null,
      name: r.name,
      entry_kind: r.entry_kind === 'income' ? 'income' : 'expense',
      sort_order: r.sort_order != null ? Number(r.sort_order) : 0,
      is_active: r.is_active !== false,
    };
  }

  app.get('/store-operational/categories', async (req, res) => {
    try {
      const kindRaw = (req.query.entry_kind ?? '').toString().trim().toLowerCase();
      const params = [];
      let kindSql = '';
      if (kindRaw === 'income' || kindRaw === 'expense') {
        params.push(kindRaw);
        kindSql = ` AND entry_kind = $${params.length}`;
      }
      const result = await db.query(
        `
          SELECT category_id, name, entry_kind, sort_order, is_active
          FROM store_operational_categories
          WHERE is_active = TRUE
            ${kindSql}
          ORDER BY entry_kind, sort_order, lower(name)
        `,
        params
      );
      return res.status(200).json(result.rows.map(mapStoreOperationalCategoryRow));
    } catch (e) {
      console.error('Error listing store-operational categories:', e);
      if (e && e.code === '42P01') {
        return res.status(503).json({
          error: 'Tabel kategori belum tersedia',
          details:
            'Jalankan backend/migrations/20260521_store_operational_categories.sql lalu restart server.',
        });
      }
      return res.status(500).json({
        error: 'Internal server error',
        detail: process.env.NODE_ENV !== 'production' ? e.message : undefined,
      });
    }
  });

  app.post('/store-operational/categories', async (req, res) => {
    try {
      if (!assertStoreOperationalCategoryManager(req, res)) return;

      const { name, entry_kind } = req.body ?? {};
      const catName = (name ?? '').toString().trim();
      if (!catName || catName.length > 120) {
        return res.status(400).json({
          error: 'Nama kategori wajib diisi (maks. 120 karakter)',
        });
      }
      const kindRaw = (entry_kind ?? '').toString().trim().toLowerCase();
      const entryKind = kindRaw === 'income' ? 'income' : 'expense';

      const maxSort = await db.query(
        `
          SELECT COALESCE(MAX(sort_order), 0) AS mx
          FROM store_operational_categories
          WHERE entry_kind = $1
        `,
        [entryKind]
      );
      const nextSort = Number(maxSort.rows[0]?.mx || 0) + 10;

      const ins = await db.query(
        `
          INSERT INTO store_operational_categories (name, entry_kind, sort_order)
          VALUES ($1, $2, $3)
          RETURNING category_id, name, entry_kind, sort_order, is_active
        `,
        [catName, entryKind, nextSort]
      );
      return res.status(201).json(mapStoreOperationalCategoryRow(ins.rows[0]));
    } catch (e) {
      console.error('Error creating store-operational category:', e);
      if (e && e.code === '23505') {
        return res.status(409).json({
          error: 'Kategori dengan nama ini sudah ada untuk jenis yang sama',
        });
      }
      if (e && e.code === '42P01') {
        return res.status(503).json({
          error: 'Tabel kategori belum tersedia',
          details:
            'Jalankan backend/migrations/20260521_store_operational_categories.sql lalu restart server.',
        });
      }
      return res.status(500).json({
        error: 'Internal server error',
        detail: process.env.NODE_ENV !== 'production' ? e.message : undefined,
      });
    }
  });

  app.patch('/store-operational/categories/:category_id', async (req, res) => {
    try {
      if (!assertStoreOperationalCategoryManager(req, res)) return;

      const categoryIdRaw = (req.params.category_id ?? '').toString().trim();
      const categoryId = parseInt(categoryIdRaw, 10);
      if (!Number.isFinite(categoryId) || categoryId <= 0) {
        return res.status(400).json({ error: 'category_id tidak valid' });
      }

      const catName = (req.body?.name ?? '').toString().trim();
      if (!catName || catName.length > 120) {
        return res.status(400).json({
          error: 'Nama kategori wajib diisi (maks. 120 karakter)',
        });
      }

      const upd = await db.query(
        `
          UPDATE store_operational_categories
          SET name = $2, updated_at = NOW()
          WHERE category_id = $1 AND is_active = TRUE
          RETURNING category_id, name, entry_kind, sort_order, is_active
        `,
        [categoryId, catName]
      );
      if (upd.rows.length === 0) {
        return res.status(404).json({ error: 'Kategori tidak ditemukan' });
      }
      return res.status(200).json(mapStoreOperationalCategoryRow(upd.rows[0]));
    } catch (e) {
      console.error('Error updating store-operational category:', e);
      if (e && e.code === '23505') {
        return res.status(409).json({
          error: 'Kategori dengan nama ini sudah ada untuk jenis yang sama',
        });
      }
      if (e && e.code === '42P01') {
        return res.status(503).json({
          error: 'Tabel kategori belum tersedia',
          details:
            'Jalankan backend/migrations/20260521_store_operational_categories.sql lalu restart server.',
        });
      }
      return res.status(500).json({
        error: 'Internal server error',
        detail: process.env.NODE_ENV !== 'production' ? e.message : undefined,
      });
    }
  });

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
  
      const userIdRaw = (req.query.user_id ?? '').toString().trim();
      const filterUserId = parseInt(userIdRaw, 10);
      const hasUserFilter =
        userIdRaw.length > 0 &&
        Number.isFinite(filterUserId) &&
        filterUserId > 0;
  
      let result;
      if (datePat.test(fromRaw) && datePat.test(toRaw)) {
        if (fromRaw > toRaw) {
          return res.status(400).json({
            error: 'date_from tidak boleh lebih besar dari date_to',
          });
        }
        const rangeParams = [branchId, fromRaw, toRaw];
        if (hasUserFilter) rangeParams.push(filterUserId);
        const rangeUserSql = hasUserFilter
          ? ` AND user_id = $${rangeParams.length}::bigint`
          : '';
        const rangeDateSql = timestampOnBusinessDateBetweenSql(
          'created_at',
          '$2',
          '$3'
        );
        result = await db.query(
          `
          SELECT entry_id, branch_id, user_id, amount, category, notes, entry_kind, proof_photo_url, created_at
          FROM store_operational_entries
          WHERE branch_id = $1
            AND ${rangeDateSql}
            ${rangeUserSql}
          ORDER BY created_at DESC
        `,
          rangeParams
        );
      } else {
        const targetDate = datePat.test(dateRaw)
          ? dateRaw
          : new Intl.DateTimeFormat('en-CA', {
              timeZone: ORDER_CALENDAR_TIMEZONE,
              year: 'numeric',
              month: '2-digit',
              day: '2-digit',
            }).format(new Date());
        const dayParams = [branchId, targetDate];
        if (hasUserFilter) dayParams.push(filterUserId);
        const dayUserSql = hasUserFilter
          ? ` AND user_id = $${dayParams.length}::bigint`
          : '';
        const dayDateSql = timestampOnBusinessDateSql('created_at', '$2');
        result = await db.query(
          `
          SELECT entry_id, branch_id, user_id, amount, category, notes, entry_kind, proof_photo_url, created_at
          FROM store_operational_entries
          WHERE branch_id = $1
            AND ${dayDateSql}
            ${dayUserSql}
          ORDER BY created_at DESC
        `,
          dayParams
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
                  detail: `item_id ${row.item_id} (${row.kode_produk || row.name || ''}) memiliki status "${row.status}". Barang buyback atau yang belum siap etalase harus diproses/ditransfer ke warehouse dulu.`,
                });
              }
            }
          }
        }
      }
  
      // Backward-compatible: DB may have items.photo_url (old) or items.photo_produk (new)
      const itemsPhotoCol = await getItemsPhotoColumn(client);
      const itemsColFlags = await getItemsColumnFlags(client);
      const itemStockSelect = itemSelectStockFields(itemsColFlags);
  
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
  
      const resolvedOrderUserId = (() => {
        const fromBody = parseInt(String(user_id ?? ''), 10);
        if (Number.isFinite(fromBody) && fromBody > 0) return fromBody;
        const fromJwt = parseInt(
          String(req.user?.user_id ?? req.user?.id ?? ''),
          10
        );
        if (Number.isFinite(fromJwt) && fromJwt > 0) return fromJwt;
        return null;
      })();
  
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
      if (!customer_id || !branch_id || resolvedOrderUserId == null) {
        return res.status(400).json({
          error: 'Missing required fields: customer_id, branch_id, user_id',
        });
      }
  
      if (!order_items || !Array.isArray(order_items) || order_items.length === 0) {
        return res.status(400).json({ error: 'Order must have at least one item' });
      }
  
      await client.query('BEGIN');
  
      const itemsPhotoColName = defaultItemsPhotoColumnName(itemsPhotoCol);
      const orderItemsPhotoCol = await getOrderItemsPhotoColumn(client);
      const orderItemsPhotoColName = orderItemsPhotoCol || 'photo_produk';
  
      // Persist upload metadata (safe: filename is server-generated)
      let _uploadId = null;
      if (req.file) {
        const uploaderUserId = req.user?.user_id ? parseInt(req.user.user_id, 10) : null;
        const urlPath = `/uploads/${req.file.filename}`;
  
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
  
      let nota_order = await resolveNotaOrder(client, {
        branch_id,
        order_type,
        order_number,
      });
  
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
        [
          order_type,
          customer_id,
          initialStatus,
          nota_order,
          branch_id,
          resolvedOrderUserId,
          diskon,
          mode,
          0,
        ] // total will be calculated later
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
               quantity, status${itemStockSelect}
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
              item_ownership: dbItem.ownership ?? null,
              item_stock_type: dbItem.stock_type ?? null,
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
            final_item_id = await insertManualOrderItem(
              client,
              itemsColFlags,
              itemsPhotoColName,
              {
                nama_item: itemData.nama_item,
                kode_produk: itemData.kode_produk,
                weight: itemData.weight,
                material: itemData.material,
                purity: itemData.purity,
                kategori: itemData.kategori,
                jenis: itemData.jenis,
                tipe: itemData.tipe,
                ownership: itemData.ownership || 'unknown',
                stock_type: itemData.stock_type || 'non_inventory',
                status: itemData.status || 'unregistered',
                is_quick_registered: itemData.is_quick_registered || false,
                branch_id,
                initialItemQty,
                photo_produk: itemData.photo_produk,
              }
            );
          } catch (e) {
            // Handle unique constraint on kode_produk: find existing item
            if (e && e.code === '23505') {
              const existing = await client.query(
                `SELECT item_id FROM items WHERE kode_produk = $1 AND branch_id = $2 LIMIT 1`,
                [itemData.kode_produk, branch_id]
              );
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
  
          await updateItemStatusAndStock(client, itemsColFlags, {
            itemId: final_item_id,
            status: newItemStatus,
            ownership: newOwnership,
            stockType: newStockType,
          });
  
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
            subtotal, diskon, total, ${orderItemsPhotoColName}, kategori, jenis, tipe, material, purity
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
              await client.query('ROLLBACK');
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
  
              await updateItemStatusAndStock(client, itemsColFlags, {
                itemId: final_item_id,
                status: newItemStatus,
                ownership: newOwnership,
                stockType: newStockType,
              });
  
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
  
      // orders.jumlah may be GENERATED ALWAYS (vanessa3_schema) — never UPDATE it then.
      const jumlahRounded = roundUpToNearest5000(orderTotal);
      const jumlahMode = await getOrdersJumlahColumnMode(client);
      if (jumlahMode === 'plain') {
        await client.query(
          `UPDATE orders
           SET total = $1,
               jumlah = $2,
               updated_at = NOW()
           WHERE order_id = $3`,
          [orderTotal, jumlahRounded, order.order_id]
        );
      } else {
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
      console.error('Error creating order:', {
        code: error?.code,
        message: error?.message,
        detail: error?.detail,
        table: error?.table,
        column: error?.column,
      });
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
        detail: formatDbErrorForClient(error),
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

module.exports = { registerOrdersCoreRoutes };

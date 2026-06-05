'use strict';

const express = require('express');
const {
  ordersHasPickupBranchColumn,
  ordersHasMetadataColumn,
  orderCostBreakdownsTableExists,
  ensureOrderCostBreakdownsSchema,
  sqlOrdersVisibleAtWorkshopBranch,
  orderVisibleAtWorkshopBranchId,
  orderVisibleForWorkshopStatusPut,
  sqlWorkshopTukangQueueStatuses,
  sqlWorkshopOrderIsUnassigned,
  sqlWorkshopOrderAssignedToTechnician,
  sqlWorkshopAntrianVisibleAtBranch,
  ordersHasMetadataColumnLive,
  jsonSafeDbRow,
} = require('../lib/orders_workshop_helpers');

/**
 * Status yang boleh admin_workshop set lewat PUT /workshop-orders/:id/status.
 * Tanpa in_workshop / repairing / polishing / custom_work — pekerjaan diambil & progres oleh tukang (POST update-progress).
 */
const ADMIN_WORKSHOP_PUT_ALLOWED_STATUSES = Object.freeze([
  'sent-to-workshop',
  'done_workshop',
  'ready_for_pickup',
  'cancelled',
]);

/**
 * Endpoint workshop / tukang (dipisah dari server.js).
 * Auth: /api/* dan /workshop-orders / /technicians diatur di server.js.
 */
function registerWorkshopRoutes(app, deps) {
  const { db, notifyClients } = deps;

  const broadcastWorkshop = (message, wsType, extra = {}) => {
    if (typeof notifyClients !== 'function') return;
    try {
      notifyClients(message, {
        wsType,
        branch_id: extra.branch_id ?? null,
        event: extra.event ?? wsType,
        payload: extra.payload ?? null,
      });
    } catch (e) {
      console.error('Workshop notify failed:', e?.message || e);
    }
  };

  const workshopApi = express.Router();
  const technicianApi = express.Router();
workshopApi.get("/work-queue", async (req, res) => {
  try {
    const branchId = req.query.branch_id;
    const technicianIdRaw = req.query.technician_id;
    const technicianId = parseInt(String(technicianIdRaw ?? ''), 10);
    const unassignedOnlyRaw = String(req.query.unassigned_only ?? '')
      .trim()
      .toLowerCase();
    const unassignedOnly =
      unassignedOnlyRaw === '1' ||
      unassignedOnlyRaw === 'true' ||
      unassignedOnlyRaw === 'yes';

    if (!branchId) {
      return res.status(400).json({ error: "branch_id is required" });
    }

    const hasPickupWq = await ordersHasPickupBranchColumn(db);
    const hasMetaWq = await ordersHasMetadataColumn(db);
    const brScopeWq = sqlOrdersVisibleAtWorkshopBranch('o', 1, hasPickupWq, hasMetaWq);
    // Satu baris per order + pelanggan + item utama (selaras GET /workshop-orders) agar UI tukang punya nama item & customer.
    let inner = `
      SELECT DISTINCT ON (o.order_id)
        o.*,
        c.name AS customer_name,
        c.phone AS customer_phone,
        COALESCE(oi.nama_item, i.name) AS item_name,
        COALESCE(oi.qty, 1) AS quantity,
        COALESCE(oi.weight, i.weight, 0) AS weight,
        COALESCE(oi.jenis, i.material) AS material
      FROM orders o
      LEFT JOIN customers c ON o.customer_id = c.customer_id
      LEFT JOIN order_items oi ON o.order_id = oi.order_id
      LEFT JOIN items i ON oi.item_id = i.item_id
      WHERE ${brScopeWq}
        AND o.order_type::text IN ('service', 'custom')
        AND ${sqlWorkshopTukangQueueStatuses('o')}
    `;
    const params = [branchId];

    if (unassignedOnly) {
      inner += ` AND (${sqlWorkshopOrderIsUnassigned('o', hasMetaWq)})`;
    }

    // Dengan technician_id: filter "pekerjaan milik teknisi ini" (halaman Update Progress).
    // Jika kolom metadata ada, penugasan workshop = hanya metadata (assigned_*), BUKAN orders.user_id
    // (user_id sering pembuat order/kasir — menyebabkan order muncul di Update Progress padahal belum Mulai).
    // Tanpa kolom metadata: legacy memakai orders.user_id sebagai teknisi.
    if (Number.isFinite(technicianId) && technicianId > 0) {
      if (hasMetaWq) {
        inner += ` AND (${sqlWorkshopOrderAssignedToTechnician('o', 2, hasMetaWq)})`;
        params.push(technicianId);
      } else {
        inner += ` AND o.user_id = $2`;
        params.push(technicianId);
      }
    }
    inner += `
      ORDER BY o.order_id, o.created_at ASC, oi.order_item_id ASC NULLS LAST
    `;
    const query = `SELECT * FROM (${inner}) AS wq ORDER BY wq.created_at ASC`;

    const result = await db.query(query, params);
    const rows = result.rows.map((r) => {
      const row = jsonSafeDbRow(r);
      const est =
        row.estimated_time ??
        row.estimate_duration_text ??
        (row.metadata && typeof row.metadata === 'object' && row.metadata.estimasi_waktu
          ? row.metadata.estimasi_waktu
          : null);
      if (row.estimated_time == null && est != null) {
        row.estimated_time = est;
      }
      return row;
    });
    // Verifikasi deploy: di DevTools → Network → response headers, atau curl -I.
    res.setHeader('X-Vanessa-WorkQueue-Rules', '2026-05-11-v3');
    res.status(200).json(rows);
  } catch (error) {
    console.error("Error fetching work queue:", error);
    res.status(500).json({ error: "Internal server error" });
  }
});

/** Cek apakah proses Node ini benar-benar pakai logika workshop terbaru + introspeksi DB. */
workshopApi.get('/work-queue-diagnostics', async (req, res) => {
  try {
    const hasMeta = await ordersHasMetadataColumn(db);
    res.setHeader('X-Vanessa-WorkQueue-Rules', '2026-05-11-v3');
    return res.status(200).json({
      rules_version: '2026-05-11-v3',
      orders_table_has_metadata_column: hasMeta,
      unassigned_mode: hasMeta
        ? 'metadata_positive_id_only_no_user_id_gate'
        : 'legacy_user_id_null_means_unassigned',
      technician_id_filter: hasMeta
        ? 'metadata_assigned_fields_only'
        : 'orders_user_id_equals_technician',
      note:
        'Jika orders_table_has_metadata_column false padahal kolom ada, restart Node; ' +
        'jika true tapi antrian kosong, cek branch_id & visibilitas order di cabang workshop.',
    });
  } catch (e) {
    console.error('work-queue-diagnostics:', e);
    return res.status(500).json({ error: 'Internal server error' });
  }
});

// Service/custom menunggu kirim gudang → workshop (`awaiting_warehouse`).
app.get('/api/workshop/warehouse-service-queue', async (req, res) => {
  try {
    const role = (req.user?.role ?? '').toString().trim().toLowerCase();
    if (!new Set(['admin_warehouse', 'superadmin', 'manajer', 'stockist']).has(role)) {
      return res.status(403).json({ error: 'Role tidak diizinkan' });
    }
    const hasPickupWq = await ordersHasPickupBranchColumn(db);
    const result = await db.query(
      `
        SELECT DISTINCT ON (o.order_id)
          o.order_id,
          o.order_number,
          o.order_type,
          o.status,
          o.branch_id,
          ${hasPickupWq ? 'o.pickup_branch_id,' : ''}
          o.created_at,
          o.updated_at,
          c.name AS customer_name,
          c.phone,
          b.name AS store_branch_name,
          COALESCE(oi.nama_item, i.name) AS item_name
        FROM orders o
        JOIN customers c ON o.customer_id = c.customer_id
        LEFT JOIN branches b ON b.branch_id = o.branch_id
        LEFT JOIN order_items oi ON o.order_id = oi.order_id
        LEFT JOIN items i ON oi.item_id = i.item_id
        WHERE o.order_type::text IN ('service', 'custom')
          AND o.status::text = 'awaiting_warehouse'
        ORDER BY o.order_id, o.created_at ASC, oi.order_item_id ASC NULLS LAST
      `
    );
    const processedRows = result.rows.map((row) => ({
      order_id: row.order_id.toString(),
      order_number: row.order_number,
      order_type: row.order_type,
      status: row.status,
      branch_id: row.branch_id != null ? String(row.branch_id) : null,
      pickup_branch_id:
        hasPickupWq && row.pickup_branch_id != null
          ? String(row.pickup_branch_id)
          : null,
      store_branch_name: row.store_branch_name,
      created_at: row.created_at,
      updated_at: row.updated_at,
      customer_name: row.customer_name,
      phone: row.phone,
      item_name: row.item_name,
    }));
    res.status(200).json(processedRows);
  } catch (error) {
    console.error('Error fetching warehouse service queue:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// Service/custom: menunggu persetujuan admin workshop (bukan gudang) sebelum masuk antrian pekerjaan.
app.get('/api/workshop/service-incoming', async (req, res) => {
  try {
    const branchId = parseInt(String(req.query.branch_id ?? ''), 10);
    if (!Number.isFinite(branchId) || branchId <= 0) {
      return res.status(400).json({ error: 'branch_id is required' });
    }
    const role = (req.user?.role ?? '').toString().trim().toLowerCase();
    if (!new Set(['admin_workshop', 'superadmin', 'manajer']).has(role)) {
      return res.status(403).json({ error: 'Role tidak diizinkan' });
    }
    const hasPickupSi = await ordersHasPickupBranchColumn(db);
    const hasMetaSi = await ordersHasMetadataColumn(db);
    const brScopeSi = sqlOrdersVisibleAtWorkshopBranch('o', 1, hasPickupSi, hasMetaSi);
    const unassignedIncoming =
      hasPickupSi
        ? `(
            o.pickup_branch_id IS NULL
            OR o.pickup_branch_id = o.branch_id
          )
          AND o.branch_id IS DISTINCT FROM $1::bigint`
        : 'FALSE';
    const result = await db.query(
      `
        SELECT DISTINCT ON (o.order_id)
          o.order_id,
          o.order_number,
          o.order_type,
          o.status,
          o.branch_id,
          ${hasPickupSi ? 'o.pickup_branch_id,' : ''}
          o.created_at,
          o.updated_at,
          c.name AS customer_name,
          c.phone,
          COALESCE(oi.nama_item, i.name) AS item_name
        FROM orders o
        JOIN customers c ON o.customer_id = c.customer_id
        LEFT JOIN order_items oi ON o.order_id = oi.order_id
        LEFT JOIN items i ON oi.item_id = i.item_id
        WHERE o.order_type::text IN ('service', 'custom')
          AND o.status::text = 'awaiting_warehouse'
          AND (
            ${brScopeSi}
            OR (${unassignedIncoming})
          )
        ORDER BY o.order_id, o.created_at ASC, oi.order_item_id ASC NULLS LAST
      `,
      [branchId]
    );
    const processedRows = result.rows.map((row) => ({
      order_id: row.order_id.toString(),
      order_number: row.order_number,
      order_type: row.order_type,
      status: row.status,
      branch_id: row.branch_id != null ? String(row.branch_id) : null,
      pickup_branch_id: hasPickupSi && row.pickup_branch_id != null
        ? String(row.pickup_branch_id)
        : null,
      created_at: row.created_at,
      updated_at: row.updated_at,
      customer_name: row.customer_name,
      phone: row.phone,
      item_name: row.item_name,
    }));
    res.status(200).json(processedRows);
  } catch (error) {
    console.error('Error fetching service incoming:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

workshopApi.get("/material-stock", async (req, res) => {
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
      item_name: row.name,
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

workshopApi.post("/material-stock", async (req, res) => {
  try {
    const {
      branch_id,
      name,
      kode_produk,
      item_code,
      material,
      purity,
      kategori = 'BAHAN',
      jenis = 'UMUM',
      tipe = 'BIASA',
      weight,
      quantity = 1,
      location,
      supplier,
      min_stock,
    } = req.body;

    const branchId = parseInt(String(branch_id ?? ''), 10);
    const finalCode = String(item_code || kode_produk || '').trim();
    const itemName = String(name ?? '').trim();
    const mat = String(material ?? '').trim();
    const pur = String(purity ?? '').trim();
    const weightNum = parseFloat(String(weight ?? ''));

    if (!Number.isFinite(branchId) || branchId <= 0) {
      return res.status(400).json({ error: 'branch_id wajib berupa angka cabang yang valid' });
    }
    if (!itemName || !finalCode) {
      return res.status(400).json({ error: 'name dan kode_produk/item_code wajib diisi' });
    }
    if (!mat || !pur) {
      return res.status(400).json({ error: 'material dan purity wajib diisi' });
    }
    if (!Number.isFinite(weightNum) || weightNum <= 0) {
      return res.status(400).json({ error: 'weight harus angka positif (gram)' });
    }

    const qtyParsed = parseInt(String(quantity), 10);
    const qty = Number.isFinite(qtyParsed) && qtyParsed > 0 ? qtyParsed : 1;

    const metadata = {};
    if (location != null && String(location).trim()) {
      metadata.location = String(location).trim();
    }
    if (supplier != null && String(supplier).trim()) {
      metadata.supplier = String(supplier).trim();
    }
    if (min_stock != null && String(min_stock).trim() !== '') {
      metadata.min_stock = String(min_stock).trim();
    }

    const result = await db.query(
      `
        INSERT INTO items (
          branch_id, kode_produk, kategori, jenis, tipe, name, material, purity, weight,
          quantity, status, stock_type, source, metadata, created_at, updated_at
        ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, 'available', 'non_inventory', 'workshop_material', $11::jsonb, NOW(), NOW())
        RETURNING item_id, name, material, purity, kategori, weight, quantity, status
      `,
      [
        branchId,
        finalCode,
        kategori,
        jenis,
        tipe,
        itemName,
        mat,
        pur,
        weightNum,
        qty,
        JSON.stringify(metadata),
      ]
    );

    const row = result.rows[0];
    res.status(201).json({
      item_id: row.item_id.toString(),
      name: row.name,
      material: row.material,
      purity: row.purity,
      kategori: row.kategori,
      weight: parseFloat(row.weight || 0),
      quantity: parseInt(row.quantity || 0, 10),
      status: row.status,
    });
  } catch (error) {
    console.error('Error creating workshop material stock:', error);
    if (error?.code === '23505') {
      return res.status(400).json({ error: 'Kode material sudah terdaftar' });
    }
    res.status(500).json({ error: 'Internal server error' });
  }
});

workshopApi.post('/produce-from-material', async (req, res) => {
  const client = await db.getClient();
  try {
    const {
      branch_id,
      order_id,
      technician_id,
      material_item_id,
      material_qty_used,
      notes,
      output,
    } = req.body ?? {};

    const branchId = parseInt(String(branch_id ?? ''), 10);
    const orderIdParsed = parseInt(String(order_id ?? '').trim(), 10);
    const hasOrder =
      order_id != null &&
      String(order_id).trim() !== '' &&
      Number.isFinite(orderIdParsed) &&
      orderIdParsed > 0;
    const orderId = hasOrder ? orderIdParsed : null;
    const techId = parseInt(String(technician_id ?? req.user?.user_id ?? req.user?.id ?? ''), 10);
    const materialItemId = parseInt(String(material_item_id ?? ''), 10);
    const qtyUsed = parseFloat(String(material_qty_used ?? ''));

    const out = output && typeof output === 'object' ? output : {};
    const outputName = String(out.name ?? '').trim();
    const outputCode = String(out.kode_produk ?? out.item_code ?? '').trim();
    const outputMaterial = String(out.material ?? '').trim();
    const outputPurity = String(out.purity ?? '').trim();
    const outputKategori = String(out.kategori ?? 'PERHIASAN').trim();
    const outputJenis = String(out.jenis ?? 'UMUM').trim();
    const outputTipe = String(out.tipe ?? 'BIASA').trim();
    const outputWeight = parseFloat(String(out.weight ?? ''));
    const outputQty = parseInt(String(out.quantity ?? '1'), 10);

    if (!Number.isFinite(branchId) || branchId <= 0) {
      return res.status(400).json({ error: 'branch_id wajib' });
    }
    if (!Number.isFinite(materialItemId) || materialItemId <= 0) {
      return res.status(400).json({ error: 'material_item_id wajib' });
    }
    if (!Number.isFinite(qtyUsed) || qtyUsed <= 0) {
      return res.status(400).json({ error: 'material_qty_used harus angka positif' });
    }
    if (!outputName || !outputCode) {
      return res.status(400).json({ error: 'output.name dan output.kode_produk wajib' });
    }
    if (!outputMaterial || !outputPurity) {
      return res.status(400).json({ error: 'output.material dan output.purity wajib' });
    }
    if (!Number.isFinite(outputWeight) || outputWeight <= 0) {
      return res.status(400).json({ error: 'output.weight harus angka positif (gram)' });
    }
    const outQty = Number.isFinite(outputQty) && outputQty > 0 ? outputQty : 1;

    if (hasOrder) {
      const orderCheck = await db.query(
        `SELECT order_id, status, order_type::text AS order_type FROM orders WHERE order_id = $1 LIMIT 1`,
        [orderId]
      );
      if (orderCheck.rows.length === 0) {
        return res.status(404).json({ error: 'Order tidak ditemukan' });
      }
      const ot = String(orderCheck.rows[0].order_type ?? '').trim().toLowerCase();
      if (ot !== 'service' && ot !== 'custom') {
        return res.status(400).json({
          error: 'Order opsional hanya untuk tipe service atau custom',
        });
      }
    }

    await client.query('BEGIN');

    const matRes = await client.query(
      `
        SELECT item_id, branch_id, name, quantity, stock_type, source
        FROM items
        WHERE item_id = $1 AND branch_id = $2
        FOR UPDATE
      `,
      [materialItemId, branchId]
    );
    if (matRes.rows.length === 0) {
      await client.query('ROLLBACK');
      return res.status(404).json({ error: 'Material tidak ditemukan di cabang ini' });
    }
    const matRow = matRes.rows[0];
    if (matRow.stock_type !== 'non_inventory') {
      await client.query('ROLLBACK');
      return res.status(400).json({ error: 'Item bukan stok material workshop' });
    }
    const prevMatQty = parseFloat(matRow.quantity ?? 0) || 0;
    if (prevMatQty < qtyUsed) {
      await client.query('ROLLBACK');
      return res.status(400).json({
        error: `Stok material tidak cukup (tersedia ${prevMatQty})`,
      });
    }
    const nextMatQty = prevMatQty - qtyUsed;

    await client.query(
      `
        UPDATE items
        SET quantity = $1, updated_at = NOW(),
            metadata = COALESCE(metadata, '{}'::jsonb) || $2::jsonb
        WHERE item_id = $3
      `,
      [
        nextMatQty,
        JSON.stringify({
          last_updated_by: String(techId),
          last_update_notes:
            notes ||
            (hasOrder
              ? `Produksi perhiasan order #${orderId}`
              : 'Produksi mandiri tukang'),
          updated_at: new Date().toISOString(),
        }),
        materialItemId,
      ]
    );

    const productionMeta = {
      ...(hasOrder
        ? { order_id: String(orderId) }
        : { production_kind: 'self_initiated' }),
      technician_id: String(techId),
      material_item_id: String(materialItemId),
      material_name: matRow.name,
      material_qty_used: String(qtyUsed),
      production_notes: notes || '',
      produced_at: new Date().toISOString(),
    };

    const outRes = await client.query(
      `
        INSERT INTO items (
          branch_id, kode_produk, kategori, jenis, tipe, name, material, purity, weight,
          quantity, status, stock_type, source, metadata, created_at, updated_at
        ) VALUES (
          $1, $2, $3, $4, $5, $6, $7, $8, $9, $10,
          'available', 'non_inventory', 'workshop_production', $11::jsonb, NOW(), NOW()
        )
        RETURNING item_id, name, kode_produk, weight, quantity
      `,
      [
        branchId,
        outputCode,
        outputKategori,
        outputJenis,
        outputTipe,
        outputName,
        outputMaterial,
        outputPurity,
        outputWeight,
        outQty,
        JSON.stringify(productionMeta),
      ]
    );
    const outputRow = outRes.rows[0];
    const outputItemId = outputRow.item_id;

    const creatorId = parseInt(String(req.user?.user_id ?? req.user?.id ?? ''), 10);
    const creatorOk = Number.isFinite(creatorId) && creatorId > 0;

    await client.query(
      `
        INSERT INTO stock_mutations (
          item_id, branch_id, type, quantity, previous_stock, current_stock,
          notes, reference_id, reference_type, created_by
        )
        VALUES ($1, $2, 'out', $3, $4, $5, $6, $7, 'workshop_production', $8)
      `,
      [
        materialItemId,
        branchId,
        qtyUsed,
        prevMatQty,
        nextMatQty,
        hasOrder
          ? `Bahan untuk produksi order #${orderId} → ${outputName}`
          : `Bahan produksi mandiri → ${outputName}`,
        outputItemId,
        creatorOk ? creatorId : null,
      ]
    );

    await client.query(
      `
        INSERT INTO stock_mutations (
          item_id, branch_id, type, quantity, previous_stock, current_stock,
          notes, reference_id, reference_type, created_by
        )
        VALUES ($1, $2, 'in', $3, 0, $3, $4, $5, 'workshop_production', $6)
      `,
      [
        outputItemId,
        branchId,
        outQty,
        hasOrder
          ? `Hasil produksi tukang dari material ${matRow.name} (order #${orderId})`
          : `Hasil produksi mandiri dari material ${matRow.name}`,
        hasOrder ? orderId : outputItemId,
        creatorOk ? creatorId : null,
      ]
    );

    const hasMeta = await ordersHasMetadataColumnLive(db);
    if (hasOrder && hasMeta) {
      const prodEntry = {
        output_item_id: outputItemId,
        output_name: outputName,
        output_kode: outputCode,
        material_item_id: materialItemId,
        material_name: matRow.name,
        material_qty_used: qtyUsed,
        technician_id: techId,
        at: productionMeta.produced_at,
      };
      await client.query(
        `
          UPDATE orders
          SET metadata = jsonb_set(
            COALESCE(metadata, '{}'::jsonb),
            '{workshop_productions}',
            COALESCE(metadata->'workshop_productions', '[]'::jsonb) || $1::jsonb
          ),
          updated_at = NOW()
          WHERE order_id = $2
        `,
        [JSON.stringify([prodEntry]), orderId]
      );
    }

    await client.query('COMMIT');

    broadcastWorkshop(
      hasOrder
        ? `Tukang memproduksi ${outputName} dari material (Order #${orderId})`
        : `Tukang memproduksi ${outputName} (produksi mandiri)`,
      'order_update',
      {
        branch_id: branchId,
        event: 'workshop_production_created',
        payload: {
          order_id: hasOrder ? orderId : null,
          output_item_id: outputItemId,
          technician_id: techId,
          production_kind: hasOrder ? 'order_linked' : 'self_initiated',
        },
      }
    );

    res.status(201).json({
      success: true,
      output_item_id: String(outputItemId),
      output_name: outputRow.name,
      output_kode: outputRow.kode_produk,
      material_remaining: nextMatQty,
      order_id: hasOrder ? orderId : null,
      production_kind: hasOrder ? 'order_linked' : 'self_initiated',
    });
  } catch (error) {
    await client.query('ROLLBACK').catch(() => {});
    console.error('Error produce-from-material:', error);
    if (error?.code === '23505') {
      return res.status(400).json({ error: 'Kode produk hasil produksi sudah terdaftar' });
    }
    res.status(500).json({ error: 'Internal server error' });
  } finally {
    client.release();
  }
});

workshopApi.get('/productions', async (req, res) => {
  try {
    const branchId = parseInt(String(req.query.branch_id ?? ''), 10);
    const period = String(req.query.period ?? 'month').trim().toLowerCase();
    const orderIdFilter = parseInt(String(req.query.order_id ?? ''), 10);

    if (!Number.isFinite(branchId) || branchId <= 0) {
      return res.status(400).json({ error: 'branch_id wajib' });
    }

    let dateFilter = '';
    if (period === 'today') {
      dateFilter = 'AND DATE(i.created_at) = CURRENT_DATE';
    } else if (period === 'week') {
      dateFilter = "AND i.created_at >= CURRENT_DATE - INTERVAL '7 days'";
    } else if (period === 'month') {
      dateFilter = "AND i.created_at >= CURRENT_DATE - INTERVAL '30 days'";
    }

    const params = [branchId];
    let orderClause = '';
    if (Number.isFinite(orderIdFilter) && orderIdFilter > 0) {
      params.push(String(orderIdFilter));
      orderClause = `AND (i.metadata->>'order_id') = $${params.length}`;
    }

    const result = await db.query(
      `
        SELECT
          i.item_id AS output_item_id,
          i.name AS output_name,
          i.kode_produk AS output_kode,
          i.weight AS output_weight,
          i.material AS output_material,
          i.purity AS output_purity,
          i.kategori AS output_kategori,
          i.jenis AS output_jenis,
          i.quantity AS output_quantity,
          i.created_at,
          i.metadata->>'order_id' AS order_id,
          i.metadata->>'production_kind' AS production_kind,
          i.metadata->>'technician_id' AS technician_id,
          i.metadata->>'material_item_id' AS material_item_id,
          i.metadata->>'material_name' AS material_name,
          i.metadata->>'material_qty_used' AS material_qty_used,
          i.metadata->>'production_notes' AS production_notes,
          u.username AS technician_name,
          o.status AS order_status
        FROM items i
        LEFT JOIN users u ON u.user_id = NULLIF(i.metadata->>'technician_id', '')::int
        LEFT JOIN orders o ON o.order_id = NULLIF(i.metadata->>'order_id', '')::int
        WHERE i.branch_id = $1
          AND i.source = 'workshop_production'
          ${dateFilter}
          ${orderClause}
        ORDER BY i.created_at DESC
        LIMIT 500
      `,
      params
    );

    const rows = result.rows.map((row) => jsonSafeDbRow({
      ...row,
      output_item_id: row.output_item_id?.toString(),
      output_weight: parseFloat(row.output_weight ?? 0),
      output_quantity: parseInt(row.output_quantity ?? 0, 10),
      material_qty_used: parseFloat(row.material_qty_used ?? 0),
    }));

    res.status(200).json(rows);
  } catch (error) {
    console.error('Error fetching workshop productions:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

workshopApi.get("/dashboard", async (req, res) => {
  try {
    const branchId = parseInt(String(req.query.branch_id ?? ''), 10);
    if (!Number.isFinite(branchId) || branchId <= 0) {
      return res.status(400).json({ error: 'branch_id wajib berupa angka cabang yang valid' });
    }

    const hasMetaDash = await ordersHasMetadataColumnLive(db);
    const brScopeDash = sqlWorkshopAntrianVisibleAtBranch('o', 1, hasMetaDash);
    const queueStatusesDash = sqlWorkshopTukangQueueStatuses('o');
    const unassDash = sqlWorkshopOrderIsUnassigned('o', hasMetaDash);
    const inProgressDash = hasMetaDash
      ? `(
          o.status::text IN ('repairing', 'polishing', 'custom_work')
          OR (
            o.status::text = 'in_workshop'
            AND NOT (${sqlWorkshopOrderIsUnassigned('o', hasMetaDash)})
          )
        )`
      : `o.status::text IN ('repairing', 'polishing', 'custom_work', 'in_workshop')`;

    // Selaras GET /workshop-orders: antrian = belum assign; ON PROGRESS = sedang dikerjakan.
    const statsResult = await db.query(
      `
      SELECT
        COUNT(*) FILTER (
          WHERE (${queueStatusesDash}) AND (${unassDash})
        )::int AS pending_orders,
        COUNT(*) FILTER (
          WHERE (${inProgressDash})
        )::int AS in_progress_orders,
        COUNT(*) FILTER (
          WHERE o.status::text IN ('done_workshop', 'ready_for_pickup', 'completed', 'delivered')
            AND DATE(o.updated_at) = CURRENT_DATE
        )::int AS completed_orders
      FROM orders o
      WHERE ${brScopeDash}
        AND o.order_type::text IN ('service', 'custom')
    `,
      [branchId]
    );

    const stats = statsResult.rows[0];

    // Get recent orders
    const recentOrdersResult = await db.query(
      `
      SELECT
        o.order_id,
        o.order_type,
        o.status,
        o.created_at,
        COALESCE(oi.nama_item, i.name) AS item_name,
        c.name AS customer_name
      FROM orders o
      LEFT JOIN customers c ON o.customer_id = c.customer_id
      LEFT JOIN order_items oi ON o.order_id = oi.order_id
      LEFT JOIN items i ON oi.item_id = i.item_id
      WHERE ${brScopeDash}
        AND o.order_type::text IN ('service', 'custom')
      ORDER BY o.created_at DESC
      LIMIT 5
    `,
      [branchId]
    );

    // Get technician count (simplified - count users with technician role in this branch)
    const technicianResult = await db.query(
      `
      SELECT COUNT(*)::int AS total_technicians
      FROM user_branch_roles ubr
      JOIN users u ON ubr.user_id = u.user_id
      WHERE ubr.branch_id = $1 AND ubr.role = 'tukang' AND u.status = 'active'
    `,
      [branchId]
    );

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

workshopApi.get("/reports", async (req, res) => {
  try {
    const branchId = parseInt(String(req.query.branch_id ?? ""), 10);
    const periodRaw = String(req.query.period ?? "month").toLowerCase();
    const period = ["week", "month", "year", "quarter"].includes(periodRaw)
      ? periodRaw
      : "month";

    if (!Number.isFinite(branchId) || branchId <= 0) {
      return res.status(400).json({ error: "branch_id wajib diisi dan valid" });
    }

    let dateFilter = "";
    if (period === "week") {
      dateFilter = "AND o.created_at >= DATE_TRUNC('week', CURRENT_DATE)";
    } else if (period === "year") {
      dateFilter = "AND o.created_at >= DATE_TRUNC('year', CURRENT_DATE)";
    } else if (period === "quarter") {
      dateFilter = "AND o.created_at >= CURRENT_DATE - INTERVAL '90 days'";
    } else {
      dateFilter = "AND o.created_at >= DATE_TRUNC('month', CURRENT_DATE)";
    }

    const hasOrdersMetadata = await ordersHasMetadataColumn(db);
    const technicianExpr = hasOrdersMetadata
      ? "COALESCE(NULLIF(o.metadata->>'assigned_technician', ''), NULLIF(o.metadata->>'assigned_technician_id', ''), 'Unassigned')"
      : "'Unassigned'";
    const sellingPriceExpr = hasOrdersMetadata
      ? "COALESCE((o.metadata->>'selling_price')::numeric, 0)"
      : "0::numeric";
    const buybackPriceExpr = hasOrdersMetadata
      ? "COALESCE((o.metadata->>'buyback_price')::numeric, 0)"
      : "0::numeric";
    const materialCostExpr = hasOrdersMetadata
      ? "COALESCE((o.metadata->>'material_cost')::numeric, 0)"
      : "0::numeric";
    const laborCostExpr = hasOrdersMetadata
      ? "COALESCE((o.metadata->>'labor_cost')::numeric, 0)"
      : "0::numeric";

    const orderStats = await db.query(
      `
        SELECT
          COUNT(*) as total_orders,
          COUNT(CASE WHEN o.status IN ('completed', 'done_workshop', 'ready_for_pickup', 'delivered') THEN 1 END) as completed_orders,
          COUNT(CASE WHEN o.status IN ('repairing', 'polishing', 'custom_work') THEN 1 END) as in_progress_orders,
          COUNT(CASE WHEN o.status IN ('pending', 'sent-to-workshop', 'in_workshop') THEN 1 END) as pending_orders,
          AVG(
            CASE
              WHEN o.status IN ('completed', 'done_workshop', 'ready_for_pickup', 'delivered')
              THEN EXTRACT(EPOCH FROM (o.updated_at - o.created_at))/3600
              ELSE NULL
            END
          ) as avg_completion_hours
        FROM orders o
        WHERE o.branch_id = $1
          AND o.order_type IN ('service', 'custom')
          ${dateFilter}
      `,
      [branchId]
    );

    const technicianStats = await db.query(
      `
        SELECT
          ${technicianExpr} as technician,
          COUNT(*) as orders_assigned,
          COUNT(CASE WHEN o.status IN ('completed', 'done_workshop', 'ready_for_pickup', 'delivered') THEN 1 END) as orders_completed,
          AVG(
            CASE
              WHEN o.status IN ('completed', 'done_workshop', 'ready_for_pickup', 'delivered')
              THEN EXTRACT(EPOCH FROM (o.updated_at - o.created_at))/3600
              ELSE NULL
            END
          ) as avg_time_hours
        FROM orders o
        WHERE o.branch_id = $1
          AND o.order_type IN ('service', 'custom')
          ${dateFilter}
        GROUP BY 1
        ORDER BY orders_assigned DESC
      `,
      [branchId]
    );

    const materialStats = await db.query(
      `
        SELECT
          COALESCE(
            NULLIF(BTRIM(oi.jenis), ''),
            NULLIF(BTRIM(i.material), ''),
            'Unknown'
          ) as material,
          SUM(COALESCE(oi.qty, 1)) as usage_count,
          SUM(COALESCE(oi.weight, i.weight, 0) * GREATEST(COALESCE(oi.qty, 1), 1)) as total_weight_used
        FROM orders o
        LEFT JOIN order_items oi ON o.order_id = oi.order_id
        LEFT JOIN items i ON oi.item_id = i.item_id
        WHERE o.branch_id = $1
          AND o.order_type IN ('service', 'custom')
          AND o.status IN ('completed', 'done_workshop', 'ready_for_pickup', 'delivered')
          ${dateFilter}
        GROUP BY 1
        ORDER BY total_weight_used DESC NULLS LAST
      `,
      [branchId]
    );

    const financialStats = await db.query(
      `
        SELECT
          SUM(CASE WHEN o.order_type = 'jual' THEN ${sellingPriceExpr} ELSE 0 END) as sales_revenue,
          SUM(CASE WHEN o.order_type = 'buyback' THEN ${buybackPriceExpr} ELSE 0 END) as buyback_revenue,
          SUM(${materialCostExpr}) as material_cost,
          SUM(${laborCostExpr}) as labor_cost
        FROM orders o
        WHERE o.branch_id = $1
          ${dateFilter}
      `,
      [branchId]
    );

    const stats = orderStats.rows[0] || {};
    const financial = financialStats.rows[0] || {};
    const totalOrders = parseInt(stats.total_orders || 0, 10) || 0;
    const completedOrders = parseInt(stats.completed_orders || 0, 10) || 0;
    const inProgressOrders = parseInt(stats.in_progress_orders || 0, 10) || 0;
    const pendingOrders = parseInt(stats.pending_orders || 0, 10) || 0;
    const avgCompletionHours = parseFloat(stats.avg_completion_hours || 0) || 0;

    const totalMaterialUsed = materialStats.rows.reduce(
      (acc, row) => acc + (parseFloat(row.total_weight_used || 0) || 0),
      0
    );
    const materialTypes = materialStats.rows.filter(
      (row) => String(row.material ?? '').trim().length > 0
    ).length;
    const materialEfficiency = totalOrders > 0
      ? (completedOrders / totalOrders) * 100
      : 0;
    const activeTechnicians = technicianStats.rows.filter(
      (row) => (parseInt(row.orders_assigned || 0, 10) || 0) > 0
    ).length;

    const salesRevenue = parseFloat(financial.sales_revenue || 0) || 0;
    const buybackRevenue = parseFloat(financial.buyback_revenue || 0) || 0;
    const materialCost = parseFloat(financial.material_cost || 0) || 0;
    const laborCost = parseFloat(financial.labor_cost || 0) || 0;

    res.status(200).json({
      // Flat keys for legacy/mobile UI compatibility
      total_orders: totalOrders,
      completed_orders: completedOrders,
      in_progress_orders: inProgressOrders,
      pending_orders: pendingOrders,
      avg_production_time: avgCompletionHours,
      total_material_used: totalMaterialUsed,
      material_types: materialTypes,
      material_efficiency: materialEfficiency,
      total_technicians: technicianStats.rows.length,
      active_technicians: activeTechnicians,

      // Rich structure for newer UI/widgets
      period,
      order_summary: {
        total_orders: totalOrders,
        completed_orders: completedOrders,
        in_progress_orders: inProgressOrders,
        pending_orders: pendingOrders,
        avg_completion_time: `${Math.round(avgCompletionHours * 10) / 10} jam`,
      },
      technician_performance: technicianStats.rows,
      material_usage: materialStats.rows,
      financial_summary: {
        total_revenue: salesRevenue + buybackRevenue,
        total_cost: materialCost + laborCost,
        net_profit: (salesRevenue + buybackRevenue) - (materialCost + laborCost),
      },
    });
  } catch (error) {
    console.error("Error fetching workshop reports:", error);
    res.status(500).json({ error: "Internal server error" });
  }
});

workshopApi.get("/order-cost-breakdown", async (req, res) => {
  try {
    const orderId = parseInt(String(req.query.order_id ?? ""), 10);
    const branchId = parseInt(String(req.query.branch_id ?? ""), 10);
    if (!Number.isFinite(orderId) || orderId <= 0) {
      return res.status(400).json({ error: "order_id tidak valid" });
    }
    if (!Number.isFinite(branchId) || branchId <= 0) {
      return res.status(400).json({ error: "branch_id wajib diisi" });
    }

    const hasPickupBreakdownGet = await ordersHasPickupBranchColumn(db);
    const hasMetaBreakdownGet = await ordersHasMetadataColumn(db);
    const orderRes = await db.query(
      `
        SELECT order_id, branch_id, order_type
          ${hasPickupBreakdownGet ? ", pickup_branch_id" : ""}
          ${hasMetaBreakdownGet ? ", metadata" : ""}
        FROM orders
        WHERE order_id = $1
        LIMIT 1
      `,
      [orderId]
    );
    if (orderRes.rows.length === 0) {
      return res.status(404).json({ error: "Order tidak ditemukan" });
    }
    const order = orderRes.rows[0];
    if (!orderVisibleAtWorkshopBranchId(order, branchId, hasPickupBreakdownGet, hasMetaBreakdownGet)) {
      return res.status(403).json({ error: "Order tidak untuk cabang workshop ini" });
    }
    const orderType = String(order.order_type ?? "").toLowerCase();
    if (orderType !== "service" && orderType !== "custom") {
      return res.status(400).json({ error: "Hanya order service/custom" });
    }

    const hasBreakdownTable = await orderCostBreakdownsTableExists(db);
    if (!hasBreakdownTable) {
      return res.status(200).json({ latest: null, history: [] });
    }

    const rows = await db.query(
      `
        SELECT
          breakdown_id,
          order_id,
          revision,
          material_cost,
          labor_cost,
          other_cost,
          notes,
          created_by,
          created_at
        FROM order_cost_breakdowns
        WHERE order_id = $1
        ORDER BY revision DESC
      `,
      [orderId]
    );
    const history = rows.rows.map((row) => ({
      ...row,
      breakdown_id: String(row.breakdown_id),
      order_id: String(row.order_id),
      revision: parseInt(row.revision ?? 0, 10) || 0,
      material_cost: parseFloat(row.material_cost ?? 0) || 0,
      labor_cost: parseFloat(row.labor_cost ?? 0) || 0,
      other_cost: parseFloat(row.other_cost ?? 0) || 0,
      created_by: row.created_by == null ? null : String(row.created_by),
    }));
    return res.status(200).json({
      latest: history.length > 0 ? history[0] : null,
      history,
    });
  } catch (error) {
    console.error("Error fetching order cost breakdown:", error);
    return res.status(500).json({ error: "Internal server error" });
  }
});

workshopApi.post("/order-cost-breakdown", async (req, res) => {
  const { order_id, branch_id, material_cost, labor_cost, other_cost, notes } = req.body ?? {};
  const orderId = parseInt(String(order_id ?? ""), 10);
  const branchId = parseInt(String(branch_id ?? ""), 10);
  if (!Number.isFinite(orderId) || orderId <= 0) {
    return res.status(400).json({ error: "order_id tidak valid" });
  }
  if (!Number.isFinite(branchId) || branchId <= 0) {
    return res.status(400).json({ error: "branch_id wajib diisi" });
  }

  const role = (req.user?.role ?? "").toString().trim().toLowerCase();
  const allowedRoles = new Set(["superadmin", "admin_toko", "admin_workshop", "tukang"]);
  if (!allowedRoles.has(role)) {
    return res.status(403).json({ error: "Role tidak diizinkan update biaya" });
  }

  try {
    await ensureOrderCostBreakdownsSchema(db);
  } catch (ensureErr) {
    console.error("order-cost-breakdown: ensure schema failed:", ensureErr);
    return res.status(503).json({
      error: "Gagal menyiapkan tabel biaya (order_cost_breakdowns)",
      details:
        ensureErr && ensureErr.message ? String(ensureErr.message) : String(ensureErr),
      migration:
        "backend/migrations/20260513_add_order_estimates_and_cost_breakdowns.sql",
    });
  }

  const materialCost = Math.max(0, parseFloat(String(material_cost ?? 0)) || 0);
  const laborCost = Math.max(0, parseFloat(String(labor_cost ?? 0)) || 0);
  const otherCost = Math.max(0, parseFloat(String(other_cost ?? 0)) || 0);
  const cleanNotes = String(notes ?? "").trim() || null;
  const updatedBy = parseInt(String(req.user?.user_id ?? req.body?.technician_id ?? 0), 10);
  const safeUpdatedBy = Number.isFinite(updatedBy) && updatedBy > 0 ? updatedBy : null;

  // backend/db.js exposes `getClient()` (Pool.connect). Some older code used `connect()`.
  const client = db.getClient ? await db.getClient() : await db.connect();
  let committed = false;
  try {
    await client.query("BEGIN");

    const hasPickupBreakdownPost = await ordersHasPickupBranchColumn(client);
    const hasMetaBreakdownPost = await ordersHasMetadataColumn(client);
    const orderRes = await client.query(
      `
        SELECT order_id, branch_id, order_type, status,
               COALESCE(diskon, 0)::float8 AS diskon
          ${hasPickupBreakdownPost ? ", pickup_branch_id" : ""}
          ${hasMetaBreakdownPost ? ", metadata" : ""}
        FROM orders
        WHERE order_id = $1
        LIMIT 1
      `,
      [orderId]
    );
    if (orderRes.rows.length === 0) {
      await client.query("ROLLBACK");
      return res.status(404).json({ error: "Order tidak ditemukan" });
    }
    const order = orderRes.rows[0];
    if (!orderVisibleAtWorkshopBranchId(order, branchId, hasPickupBreakdownPost, hasMetaBreakdownPost)) {
      await client.query("ROLLBACK");
      return res.status(403).json({ error: "Order tidak untuk cabang workshop ini" });
    }
    const orderType = String(order.order_type ?? "").toLowerCase();
    if (orderType !== "service" && orderType !== "custom") {
      await client.query("ROLLBACK");
      return res.status(400).json({ error: "Hanya order service/custom" });
    }

    const st = (order.status ?? "").toString().trim().toLowerCase();
    const noCostEditStatuses = new Set(["cancelled", "completed", "sold"]);
    if (noCostEditStatuses.has(st)) {
      await client.query("ROLLBACK");
      return res.status(400).json({
        error: `Tidak bisa mengubah biaya pada status "${st}"`,
      });
    }

    const revRes = await client.query(
      `
        SELECT COALESCE(MAX(revision), 0) + 1 AS next_revision
        FROM order_cost_breakdowns
        WHERE order_id = $1
      `,
      [orderId]
    );
    const nextRevision = parseInt(revRes.rows?.[0]?.next_revision ?? 1, 10) || 1;

    const inserted = await client.query(
      `
        INSERT INTO order_cost_breakdowns (
          order_id,
          revision,
          material_cost,
          labor_cost,
          other_cost,
          notes,
          created_by
        ) VALUES ($1, $2, $3, $4, $5, $6, $7)
        RETURNING *
      `,
      [orderId, nextRevision, materialCost, laborCost, otherCost, cleanNotes, safeUpdatedBy]
    );

    // Opsi B: selaraskan tagihan (orders.total) dengan breakdown — sama seperti POST /orders:
    // jumlah baris (dibulatkan ke kelipatan 5.000) lalu diskon level order.
    const preDiscountBase = materialCost + laborCost + otherCost;
    const diskonOrder = parseFloat(order.diskon) || 0;
    const lineRounded =
      preDiscountBase > 0 ? Math.ceil(preDiscountBase / 5000) * 5000 : 0;
    const newOrderTotal = lineRounded * (1 - diskonOrder / 100);

    const itemsRes = await client.query(
      `
        SELECT order_item_id
        FROM order_items
        WHERE order_id = $1
        ORDER BY order_item_id ASC
      `,
      [orderId]
    );
    if (itemsRes.rows.length > 0) {
      const firstId = itemsRes.rows[0].order_item_id;
      await client.query(
        `
          UPDATE order_items
          SET subtotal = $1,
              total = $2,
              diskon = 0
          WHERE order_item_id = $3
        `,
        [preDiscountBase, lineRounded, firstId]
      );
      if (itemsRes.rows.length > 1) {
        await client.query(
          `
            UPDATE order_items
            SET subtotal = 0,
                total = 0,
                diskon = 0
            WHERE order_id = $1
              AND order_item_id <> $2
          `,
          [orderId, firstId]
        );
      }
    }

    try {
      await client.query(
        `
          UPDATE orders
          SET total = $1,
              updated_at = NOW()
          WHERE order_id = $2
        `,
        [newOrderTotal, orderId]
      );
    } catch (updErr) {
      await client.query("ROLLBACK");
      console.error("order-cost-breakdown: update orders.total failed:", updErr);
      return res.status(500).json({ error: "Gagal memperbarui total order" });
    }

    // Jangan tulis ke estimate_amount: itu untuk estimasi awal (CS). Biaya tukang = aktual → orders.total + metadata.

    const hasOrdersMetadata = await ordersHasMetadataColumn(client);
    if (hasOrdersMetadata) {
      await client.query(
        `
          UPDATE orders
          SET metadata = COALESCE(metadata, '{}'::jsonb) || $1::jsonb,
              updated_at = NOW()
          WHERE order_id = $2
        `,
        [
          JSON.stringify({
            material_cost: materialCost,
            labor_cost: laborCost,
            other_cost: otherCost,
            actual_total_cost: preDiscountBase,
            invoice_pre_discount_rounded: lineRounded,
            order_total_after_discount: newOrderTotal,
            cost_revision: nextRevision,
            cost_updated_at: new Date().toISOString(),
          }),
          orderId,
        ]
      );
    }

    await client.query("COMMIT");
    committed = true;

    const row = inserted.rows[0] || {};
    return res.status(200).json({
      success: true,
      order_total: newOrderTotal,
      items_pre_discount_rounded: lineRounded,
      pre_discount_sum: preDiscountBase,
      breakdown: {
        ...row,
        breakdown_id: row.breakdown_id == null ? null : String(row.breakdown_id),
        order_id: row.order_id == null ? null : String(row.order_id),
        revision: parseInt(row.revision ?? 0, 10) || 0,
        material_cost: parseFloat(row.material_cost ?? 0) || 0,
        labor_cost: parseFloat(row.labor_cost ?? 0) || 0,
        other_cost: parseFloat(row.other_cost ?? 0) || 0,
        created_by: row.created_by == null ? null : String(row.created_by),
      },
    });
  } catch (error) {
    if (!committed) {
      try {
        await client.query("ROLLBACK");
      } catch (_) { /* ignore */ }
    }
    console.error("Error saving order cost breakdown:", error);
    return res.status(500).json({ error: "Internal server error" });
  } finally {
    try {
      client.release();
    } catch (_) { /* ignore */ }
  }
});

workshopApi.post("/update-progress", async (req, res) => {
  try {
    const { order_id, status, technician_id, notes, branch_id } = req.body;
    const orderId = parseInt(String(order_id ?? ''), 10);
    const branchId = parseInt(
      String(branch_id ?? req.query?.branch_id ?? ''),
      10
    );
    if (!Number.isFinite(orderId) || orderId <= 0) {
      return res.status(400).json({ error: 'order_id tidak valid' });
    }
    if (!Number.isFinite(branchId) || branchId <= 0) {
      return res.status(400).json({ error: 'branch_id wajib diisi' });
    }

    const role = (req.user?.role ?? '').toString().trim().toLowerCase();
    // Mulai kerja + bind teknisi hanya tukang (break-glass: superadmin/manajer).
    const allowedRoles = new Set([
      'superadmin',
      'admin_toko',
      'tukang',
      'manajer',
    ]);
    if (!allowedRoles.has(role)) {
      return res
        .status(403)
        .json({ error: 'Role tidak diizinkan update progress workshop' });
    }

    const hasPickupProgress = await ordersHasPickupBranchColumn(db);
    const hasMetaProgress = await ordersHasMetadataColumn(db);
    const curRes = await db.query(
      `
        SELECT order_id, order_type, branch_id, status
          ${hasPickupProgress ? ', pickup_branch_id' : ''}
          ${hasMetaProgress ? ', metadata' : ''}
        FROM orders
        WHERE order_id = $1
        LIMIT 1
      `,
      [orderId]
    );
    if (curRes.rows.length === 0) {
      return res.status(404).json({ error: 'Order tidak ditemukan' });
    }
    const order = curRes.rows[0];
    const visibleProgress = await orderVisibleForWorkshopStatusPut(
      db,
      orderId,
      branchId,
      hasPickupProgress,
      hasMetaProgress,
    );
    if (!visibleProgress) {
      return res.status(403).json({ error: 'Order tidak untuk cabang workshop ini' });
    }
    const orderType = (order.order_type ?? '').toString().trim().toLowerCase();
    if (orderType !== 'service' && orderType !== 'custom') {
      return res.status(400).json({
        error: 'Hanya order service/custom untuk workflow workshop',
      });
    }

    const incoming = (status ?? '').toString().trim().toLowerCase();
    const statusAlias = {
      pending: 'in_workshop',
      in_progress: 'repairing',
      completed: 'done_workshop',
    };
    const nextStatus = statusAlias[incoming] ?? incoming;

    const allowedByRole = {
      admin_toko: new Set(['awaiting_warehouse', 'ready_for_pickup']),
      tukang: new Set([
        'in_workshop',
        'repairing',
        'polishing',
        'custom_work',
        'done_workshop',
        'cancelled',
      ]),
      superadmin: new Set([
        'awaiting_warehouse',
        'sent-to-workshop',
        'in_workshop',
        'repairing',
        'polishing',
        'done_workshop',
        'ready_for_pickup',
        'custom_work',
        'cancelled',
      ]),
      manajer: new Set([
        'awaiting_warehouse',
        'sent-to-workshop',
        'in_workshop',
        'repairing',
        'polishing',
        'done_workshop',
        'ready_for_pickup',
        'custom_work',
        'cancelled',
      ]),
    };
    const roleAllowedSet = allowedByRole[role] ?? new Set();
    if (!roleAllowedSet.has(nextStatus)) {
      return res.status(400).json({
        error: `Status "${nextStatus}" tidak diizinkan untuk role ${role}`,
      });
    }

    const currentStatus = (order.status ?? '').toString().trim().toLowerCase();
    const validTransitions = {
      pending: new Set(['awaiting_warehouse']),
      confirmed: new Set(['awaiting_warehouse']),
      awaiting_warehouse: new Set(['sent-to-workshop']),
      // Tukang "Mulai" langsung ke repairing/custom_work; admin bisa ke in_workshop dulu.
      'sent-to-workshop': new Set(['in_workshop', 'repairing', 'custom_work']),
      in_workshop: new Set(['repairing', 'polishing', 'custom_work', 'done_workshop']),
      repairing: new Set(['polishing', 'done_workshop']),
      polishing: new Set(['done_workshop']),
      custom_work: new Set(['done_workshop']),
      'done_workshop': new Set(['ready_for_pickup']),
      'ready_for_pickup': new Set(['completed']),
    };
    if (nextStatus === 'cancelled') {
      const mayCancel =
        (role === 'tukang' || role === 'admin_workshop' || role === 'superadmin') &&
        new Set([
          'pending',
          'confirmed',
          'awaiting_warehouse',
          'sent-to-workshop',
          'in_workshop',
          'repairing',
          'polishing',
          'custom_work',
        ]).has(currentStatus);
      if (!mayCancel) {
        return res.status(400).json({
          error: `Pembatalan tidak diizinkan dari status "${currentStatus}"`,
        });
      }
    } else if (
      validTransitions[currentStatus] &&
      !validTransitions[currentStatus].has(nextStatus) &&
      currentStatus !== nextStatus
    ) {
      return res.status(400).json({
        error: `Transisi status tidak valid (${currentStatus} -> ${nextStatus})`,
      });
    }

    const techIdParsed = parseInt(String(technician_id ?? ''), 10);
    const techId = Number.isFinite(techIdParsed) && techIdParsed > 0 ? techIdParsed : null;
    const isTukang = role === 'tukang';
    const metaPatch = {
      last_updated_by: technician_id,
      last_update_notes: notes,
      updated_at: new Date().toISOString(),
    };
    // When a technician starts/updating, bind assignment so the order moves from "Antrian kerja"
    // to "Update progress" for that technician.
    if (isTukang && techId != null) {
      metaPatch.assigned_technician_id = String(techId);
    }

    if (hasMetaProgress) {
      await db.query(
        `
          UPDATE orders
          SET status = $1,
              updated_at = NOW(),
              metadata = COALESCE(metadata, '{}'::jsonb) || $2::jsonb
          WHERE order_id = $3
        `,
        [nextStatus, JSON.stringify(metaPatch), orderId],
      );
    } else {
      // Legacy DB without metadata: use orders.user_id to keep assignment working.
      await db.query(
        `
          UPDATE orders
          SET status = $1,
              updated_at = NOW(),
              user_id = COALESCE(user_id, $2::bigint)
          WHERE order_id = $3
        `,
        [nextStatus, techId, orderId],
      );
    }

    if (
      new Set(['in_workshop', 'repairing', 'polishing', 'custom_work']).has(nextStatus) &&
      currentStatus !== nextStatus
    ) {
      broadcastWorkshop(
        `Order #${orderId} sedang dikerjakan tukang (${nextStatus})`,
        'order_update',
        {
          branch_id: branchId,
          event: 'workshop_in_progress',
          payload: { order_id: orderId, status: nextStatus, technician_id: techId },
        }
      );
    }
    if (nextStatus === 'done_workshop' && currentStatus !== 'done_workshop') {
      broadcastWorkshop(
        `Order #${orderId} selesai di tukang — siap kirim ke toko`,
        'order_update',
        {
          branch_id: branchId,
          event: 'workshop_done_tukang',
          payload: { order_id: orderId, status: 'done_workshop' },
        }
      );
    }

    res.status(200).json({ success: true, message: "Progress updated successfully" });
  } catch (error) {
    console.error("Error updating work progress:", error);
    res.status(500).json({ error: "Internal server error" });
  }
});

workshopApi.post("/update-stock", async (req, res) => {
  try {
    const { item_id, quantity, technician_id, notes } = req.body;

    await db.query(`
      UPDATE items
      SET quantity = $1, updated_at = NOW(),
          metadata = COALESCE(metadata, '{}'::jsonb) || $2::jsonb
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

workshopApi.get("/work-history", async (req, res) => {
  try {
    const { technician_id: _technician_id, branch_id, period = 'all' } = req.query;

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

workshopApi.get("/technician-reports", async (req, res) => {
  try {
    const branchId = (req.query.branch_id ?? '').toString().trim();
    const periodRaw = (req.query.period ?? 'today').toString().trim().toLowerCase();
    const period = ['today', 'week', 'month', 'quarter'].includes(periodRaw)
      ? periodRaw
      : 'today';
    const technicianId = parseInt(String(req.query.technician_id ?? ''), 10);
    const sessionUserId = parseInt(
      String(req.user?.user_id ?? req.user?.id ?? ''),
      10,
    );
    const role = (req.user?.role ?? '').toString().trim().toLowerCase();

    if (!branchId) {
      return res.status(400).json({ error: 'branch_id wajib diisi' });
    }
    if (!Number.isFinite(technicianId) || technicianId <= 0) {
      return res.status(400).json({ error: 'technician_id wajib diisi' });
    }
    if (role === 'tukang' && sessionUserId !== technicianId) {
      return res.status(403).json({
        error: 'Tidak boleh melihat laporan tukang lain',
      });
    }

    const hasMeta = await ordersHasMetadataColumn(db);
    const techFilter = hasMeta
      ? sqlWorkshopOrderAssignedToTechnician('o', 2, hasMeta)
      : 'o.user_id::bigint = $2::bigint';
    const params = [branchId, technicianId];

    let dateFilter = '';
    if (period === 'today') {
      dateFilter = 'AND DATE(o.created_at) = CURRENT_DATE';
    } else if (period === 'week') {
      dateFilter = "AND o.created_at >= CURRENT_DATE - INTERVAL '7 days'";
    } else if (period === 'month') {
      dateFilter = "AND o.created_at >= CURRENT_DATE - INTERVAL '30 days'";
    } else if (period === 'quarter') {
      dateFilter = "AND o.created_at >= CURRENT_DATE - INTERVAL '90 days'";
    }

    const doneStatuses =
      "('done_workshop', 'ready_for_pickup', 'completed')";
    const inProgressStatuses =
      "('in_workshop', 'repairing', 'polishing', 'custom_work')";
    const pendingStatuses = "('sent-to-workshop')";

    const baseWhere = `
      WHERE o.branch_id::bigint = $1::bigint
        AND o.order_type::text IN ('service', 'custom')
        AND (${techFilter})
        ${dateFilter}
    `;

    const workStats = await db.query(
      `
      SELECT
        COUNT(*) as total_orders,
        COUNT(CASE WHEN o.status::text IN ${doneStatuses} THEN 1 END) as completed_orders,
        COUNT(CASE WHEN o.status::text IN ${inProgressStatuses} THEN 1 END) as in_progress_orders,
        COUNT(CASE WHEN o.status::text IN ${pendingStatuses} THEN 1 END) as pending_orders,
        AVG(CASE
          WHEN o.status::text IN ${doneStatuses} THEN
            EXTRACT(EPOCH FROM (o.updated_at - o.created_at))/3600
          ELSE NULL
        END) as avg_duration_hours,
        SUM(CASE
          WHEN o.status::text IN ${doneStatuses} THEN
            EXTRACT(EPOCH FROM (o.updated_at - o.created_at))/3600
          ELSE NULL
        END) as total_work_hours
      FROM orders o
      ${baseWhere}
    `,
      params,
    );

    const materialStats = await db.query(
      `
      SELECT
        COALESCE(
          NULLIF(BTRIM(oi.jenis), ''),
          NULLIF(BTRIM(i.material), ''),
          'Unknown'
        ) as material_type,
        SUM(COALESCE(oi.weight, i.weight, 0) * COALESCE(oi.qty, 1)) as total_weight_used,
        SUM(COALESCE(oi.qty, 1)) as usage_count
      FROM orders o
      LEFT JOIN order_items oi ON o.order_id = oi.order_id
      LEFT JOIN items i ON oi.item_id = i.item_id
      ${baseWhere}
        AND o.status::text IN ${doneStatuses}
      GROUP BY 1
      ORDER BY total_weight_used DESC
    `,
      params,
    );

    const dailyStats = await db.query(
      `
      SELECT
        DATE(o.created_at) as work_date,
        COUNT(*) as orders_count,
        COUNT(CASE WHEN o.status::text IN ${doneStatuses} THEN 1 END) as completed_count
      FROM orders o
      ${baseWhere}
      GROUP BY DATE(o.created_at)
      ORDER BY work_date DESC
      LIMIT 30
    `,
      params,
    );

    const workTypeStats = await db.query(
      `
      SELECT
        COALESCE(
          NULLIF(BTRIM(oi.kategori), ''),
          NULLIF(BTRIM(i.kategori), ''),
          'Unknown'
        ) as item_type,
        SUM(COALESCE(oi.qty, 1)) as count,
        AVG(CASE
          WHEN o.status::text IN ${doneStatuses} THEN
            EXTRACT(EPOCH FROM (o.updated_at - o.created_at))/3600
          ELSE NULL
        END) as avg_duration
      FROM orders o
      LEFT JOIN order_items oi ON o.order_id = oi.order_id
      LEFT JOIN items i ON oi.item_id = i.item_id
      ${baseWhere}
      GROUP BY 1
      ORDER BY count DESC
    `,
      params,
    );

    const stats = workStats.rows[0] ?? {};
    const totalOrders = parseInt(stats.total_orders, 10) || 0;
    const completedOrders = parseInt(stats.completed_orders, 10) || 0;
    const efficiency =
      totalOrders > 0 ? (completedOrders / totalOrders) * 100 : 0;
    const onTimeRate = efficiency;

    res.setHeader('X-Vanessa-Technician-Reports', '2026-05-17-v1');
    res.status(200).json({
      period,
      technician_id: String(technicianId),
      work_stats: {
        total_orders: totalOrders,
        completed_orders: completedOrders,
        in_progress_orders: parseInt(stats.in_progress_orders, 10) || 0,
        pending_orders: parseInt(stats.pending_orders, 10) || 0,
        avg_duration_hours: parseFloat(stats.avg_duration_hours) || 0,
        total_work_hours: parseFloat(stats.total_work_hours) || 0,
        efficiency: Math.round(efficiency),
        on_time_rate: Math.round(onTimeRate),
      },
      material_usage: materialStats.rows,
      daily_distribution: dailyStats.rows,
      work_type_distribution: workTypeStats.rows,
    });
  } catch (error) {
    console.error("Error fetching technician reports:", error);
    res.status(500).json({ error: "Internal server error" });
  }
});

  app.use('/api/workshop', workshopApi);

technicianApi.get("/dashboard", async (req, res) => {
  try {
    const branchId = parseInt(String(req.query.branch_id ?? ''), 10);
    if (!Number.isFinite(branchId) || branchId <= 0) {
      return res.status(400).json({ error: 'branch_id wajib berupa angka cabang yang valid' });
    }

    const hasPickupTd = await ordersHasPickupBranchColumn(db);
    const hasMetaTd = await ordersHasMetadataColumn(db);
    const brScopeTd = sqlOrdersVisibleAtWorkshopBranch('o', 1, hasPickupTd, hasMetaTd);

    const userIdTd = parseInt(String(req.query.user_id ?? ''), 10);
    const userIdTdOk = Number.isFinite(userIdTd) && userIdTd > 0;

    const queueStatusesTd = sqlWorkshopTukangQueueStatuses('o');
    const unassTd = sqlWorkshopOrderIsUnassigned('o', hasMetaTd);
    const assTd = sqlWorkshopOrderAssignedToTechnician('o', 2, hasMetaTd);

    let statsResult;
    if (hasMetaTd && userIdTdOk) {
      statsResult = await db.query(
        `
      SELECT
        COUNT(*) FILTER (
          WHERE (${queueStatusesTd}) AND (${unassTd})
        )::int AS pending_work_orders,
        COUNT(*) FILTER (
          WHERE (${queueStatusesTd}) AND (${assTd})
        )::int AS in_progress_work_orders,
        COUNT(*) FILTER (
          WHERE o.status::text IN ('completed', 'delivered', 'done_workshop', 'ready_for_pickup')
        )::int AS completed_work_orders
      FROM orders o
      WHERE ${brScopeTd}
        AND o.order_type::text IN ('service', 'custom')
        AND DATE(o.created_at) = CURRENT_DATE
    `,
        [branchId, userIdTd]
      );
    } else {
      statsResult = await db.query(
        `
      SELECT
        COUNT(CASE WHEN o.status::text IN ('in_workshop', 'repairing', 'polishing', 'custom_work', 'sent-to-workshop') THEN 1 END) as pending_work_orders,
        COUNT(CASE WHEN o.status::text IN ('repairing', 'polishing', 'custom_work') THEN 1 END) as in_progress_work_orders,
        COUNT(CASE WHEN o.status::text IN ('completed', 'delivered', 'done_workshop', 'ready_for_pickup') THEN 1 END) as completed_work_orders
      FROM orders o
      WHERE ${brScopeTd}
        AND o.order_type::text IN ('service', 'custom')
        AND DATE(o.created_at) = CURRENT_DATE
    `,
        [branchId]
      );
    }

    const stats = statsResult.rows[0];

    // Recent assignments — item dari order_items (kolom orders.item_id tidak lagi dipakai).
    const recentAssignmentsResult = await db.query(`
      SELECT
        o.order_id,
        o.order_type,
        o.status,
        o.created_at,
        sub.item_name,
        c.name as customer_name
      FROM orders o
      LEFT JOIN customers c ON o.customer_id = c.customer_id
      LEFT JOIN LATERAL (
        SELECT COALESCE(oi.nama_item, i.name) AS item_name
        FROM order_items oi
        LEFT JOIN items i ON oi.item_id = i.item_id
        WHERE oi.order_id = o.order_id
        LIMIT 1
      ) sub ON true
      WHERE ${brScopeTd}
        AND o.order_type::text IN ('service', 'custom')
        AND o.status::text IN ('in_workshop', 'repairing', 'polishing', 'custom_work', 'sent-to-workshop')
      ORDER BY o.created_at DESC
      LIMIT 5
    `, [branchId]);

    const recentAssignments = recentAssignmentsResult.rows.map((row) => ({
      order_id: row.order_id != null ? String(row.order_id) : null,
      order_type: row.order_type,
      status: row.status,
      created_at: row.created_at,
      item_name: row.item_name,
      customer_name: row.customer_name,
    }));

    const response = {
      pending_work_orders: parseInt(stats.pending_work_orders, 10) || 0,
      in_progress_work_orders: parseInt(stats.in_progress_work_orders, 10) || 0,
      completed_work_orders: parseInt(stats.completed_work_orders, 10) || 0,
      recent_assignments: recentAssignments,
      last_updated: new Date().toISOString(),
    };

    res.status(200).json(response);
  } catch (error) {
    console.error("Error fetching technician dashboard:", error);
    res.status(500).json({ error: "Internal server error" });
  }
});

  app.use('/api/technician', technicianApi);

// Get workshop orders — antrian workshop. Query `unassigned_only=1` (dipakai UI «Antrian pekerjaan»):
// sembunyikan order yang sudah punya tukang di metadata, supaya hanya muncul di Update Progress milik tukang itu.
// scope=all (default): semua order terlihat di cabang workshop; cross_branch / local = sempitkan by cabang asal.
app.get('/workshop-orders', async (req, res) => {
  try {
    const { branch_id, status, scope: scopeRaw } = req.query;
    const queueModeRaw = String(req.query.queue_mode ?? '')
      .trim()
      .toLowerCase();
    const queueModeAntrian = queueModeRaw === 'antrian';
    const scope = String(scopeRaw ?? 'all')
      .trim()
      .toLowerCase();
    if (!['all', 'cross_branch', 'local'].includes(scope)) {
      return res.status(400).json({ error: 'scope harus all, cross_branch, atau local' });
    }

    if (!branch_id) {
      return res.status(400).json({ error: 'branch_id is required' });
    }

    const hasPickupWo = await ordersHasPickupBranchColumn(db);
    const hasMetaWo = await ordersHasMetadataColumnLive(db);
    const brScopeWo = queueModeAntrian
      ? sqlWorkshopAntrianVisibleAtBranch('o', 1, hasMetaWo)
      : sqlOrdersVisibleAtWorkshopBranch('o', 1, hasPickupWo, hasMetaWo);
    const postWorkshopStatuses = `(
          'done_workshop',
          'ready_for_pickup'
        )`;
    let branchCompareSql = '';
    // Antrian pekerjaan: jangan sempitkan scope (Cabang ini / Cabang lain) — cukup filter cabang workshop.
    if (!queueModeAntrian) {
      if (scope === 'local') {
        if (hasMetaWo) {
          branchCompareSql = `AND (
            o.branch_id::bigint = $1::bigint
            OR (
              COALESCE(NULLIF(BTRIM(o.metadata->>'service_workshop_branch_id'), ''), '') <> ''
              AND (o.metadata->>'service_workshop_branch_id')::bigint = $1::bigint
            )
          )`;
        } else {
          branchCompareSql = 'AND o.branch_id::bigint = $1::bigint';
        }
      } else if (scope === 'cross_branch') {
        branchCompareSql = 'AND o.branch_id::bigint <> $1::bigint';
      }
    }

    let innerWhere = `
      WHERE ${brScopeWo}
        ${branchCompareSql}
        AND o.order_type::text IN ('service', 'custom')
    `;

    let params = [branch_id];
    let conditions = [];
    let orderCompletedView = false;

    if (status && status !== 'all') {
      if (status === 'pending') {
        conditions.push(`o.status::text IN ('sent-to-workshop', 'in_workshop')`);
      } else if (status === 'in_progress') {
        // Sedang dikerjakan tukang: progres aktif + in_workshop yang sudah di-assign.
        if (hasMetaWo) {
          conditions.push(`(
            o.status::text IN ('repairing', 'polishing', 'custom_work')
            OR (
              o.status::text = 'in_workshop'
              AND NOT (${sqlWorkshopOrderIsUnassigned('o', hasMetaWo)})
            )
          )`);
        } else {
          conditions.push(`o.status::text IN ('repairing', 'polishing', 'custom_work', 'in_workshop')`);
        }
      } else if (status === 'completed') {
        orderCompletedView = true;
        conditions.push(`o.status::text IN ${postWorkshopStatuses}`);
      } else {
        conditions.push(`o.status::text = $${params.length + 1}`);
        params.push(status);
      }
    } else {
      // Antrian pekerjaan: hanya order yang sudah disetujui workshop (sent-to-workshop+).
      // Menunggu persetujuan (awaiting_warehouse) hanya di menu «Service dari toko».
      conditions.push(sqlWorkshopTukangQueueStatuses('o'));
    }

    if (conditions.length > 0) {
      innerWhere += ' AND ' + conditions.join(' AND ');
    }

    const unassignedOnlyWoRaw = String(req.query.unassigned_only ?? '')
      .trim()
      .toLowerCase();
    const unassignedOnlyWo =
      queueModeAntrian ||
      unassignedOnlyWoRaw === '1' ||
      unassignedOnlyWoRaw === 'true' ||
      unassignedOnlyWoRaw === 'yes';
    if (unassignedOnlyWo) {
      innerWhere += ` AND (${sqlWorkshopOrderIsUnassigned('o', hasMetaWo)})`;
    }

    res.setHeader('X-Vanessa-Workshop-Orders-Rules', '2026-05-17-antrian-v1');

    const innerOrderBy = orderCompletedView
      ? 'o.order_id, o.updated_at DESC, o.created_at DESC, oi.order_item_id ASC NULLS LAST'
      : 'o.order_id, o.created_at ASC, oi.order_item_id ASC NULLS LAST';

    const technicianJoinSql = hasMetaWo
      ? `
        LEFT JOIN users tu ON (
          (o.metadata->>'assigned_technician_id') ~ '^[0-9]+$'
          AND tu.user_id = (NULLIF(BTRIM(o.metadata->>'assigned_technician_id'), ''))::bigint
        )`
      : '';
    const technicianSelectSql = hasMetaWo ? ', tu.username AS technician_name' : '';

    const query = `
      SELECT * FROM (
        SELECT DISTINCT ON (o.order_id)
          o.order_id,
          o.order_number,
          o.order_type,
          o.status,
          o.created_at,
          o.updated_at,
          c.name AS customer_name,
          c.phone,
          COALESCE(oi.nama_item, i.name) AS item_name,
          COALESCE(oi.qty, 1) AS quantity,
          COALESCE(oi.weight, i.weight, 0) AS weight,
          COALESCE(oi.jenis, i.material) AS material
          ${technicianSelectSql}
        FROM orders o
        LEFT JOIN customers c ON o.customer_id = c.customer_id
        LEFT JOIN order_items oi ON o.order_id = oi.order_id
        LEFT JOIN items i ON oi.item_id = i.item_id
        ${technicianJoinSql}
        ${innerWhere}
        ORDER BY ${innerOrderBy}
      ) AS wo_orders
      ${orderCompletedView
        ? 'ORDER BY wo_orders.updated_at DESC, wo_orders.created_at DESC'
        : 'ORDER BY wo_orders.created_at ASC'}
    `;

    const result = await db.query(query, params);

    // Convert BigInt and other data types for JSON serialization
    const processedRows = result.rows.map(row => ({
      order_id: row.order_id.toString(),
      order_number: row.order_number,
      order_type: row.order_type,
      status: row.status,
      created_at: row.created_at,
      updated_at: row.updated_at,
      customer_name: row.customer_name ?? '—',
      phone: row.phone ?? '',
      item_name: row.item_name,
      quantity: parseInt(row.quantity || 1),
      weight: parseFloat(row.weight || 0),
      material: row.material,
      technician_name: row.technician_name ?? null,
    }));

    res.status(200).json(processedRows);
  } catch (error) {
    console.error('Error fetching workshop orders:', error);
    res.status(500).json({ error: 'Internal server error', details: error.message });
  }
});

// Update status order workshop (service/custom) by admin_workshop/admin_toko/tukang
app.put('/workshop-orders/:id/status', async (req, res) => {
  try {
    const orderId = parseInt(req.params.id, 10);
    const nextStatusRaw = (req.body?.status ?? '').toString().trim().toLowerCase();
    const branchId = parseInt(String(req.body?.branch_id ?? req.query?.branch_id ?? ''), 10);
    if (!Number.isFinite(orderId) || orderId <= 0) {
      return res.status(400).json({ error: 'order_id tidak valid' });
    }
    if (!Number.isFinite(branchId) || branchId <= 0) {
      return res.status(400).json({ error: 'branch_id wajib diisi' });
    }

    const role = (req.user?.role ?? '').toString().trim().toLowerCase();
    const allowedRoles = new Set([
      'superadmin',
      'admin_toko',
      'admin_workshop',
      'admin_warehouse',
      'tukang',
      'stockist',
      'manajer',
    ]);
    if (!allowedRoles.has(role)) {
      return res.status(403).json({ error: 'Role tidak diizinkan update status workshop' });
    }

    const hasPickupPut = await ordersHasPickupBranchColumn(db);
    const hasMetaPut = await ordersHasMetadataColumnLive(db);
    const curRes = await db.query(
      `
        SELECT order_id, order_type, branch_id, status
          ${hasPickupPut ? ', pickup_branch_id' : ''}
          ${hasMetaPut ? ', metadata' : ''}
        FROM orders
        WHERE order_id = $1
        LIMIT 1
      `,
      [orderId]
    );
    if (curRes.rows.length === 0) {
      return res.status(404).json({ error: 'Order tidak ditemukan' });
    }
    const order = curRes.rows[0];
    const currentStatus = (order.status ?? '').toString().trim().toLowerCase();
    const receivingFromWarehouse =
      currentStatus === 'awaiting_warehouse' &&
      nextStatusRaw === 'sent-to-workshop' &&
      new Set(['admin_workshop', 'admin_warehouse', 'superadmin', 'manajer']).has(role);
    // Sumber kebenaran sama GET /workshop-orders (SQL), hindari false negative dari parse metadata di Node.
    if (!receivingFromWarehouse) {
      const visiblePut = await orderVisibleForWorkshopStatusPut(
        db,
        orderId,
        branchId,
        hasPickupPut,
        hasMetaPut,
      );
      if (!visiblePut) {
        return res.status(403).json({ error: 'Order tidak untuk cabang workshop ini' });
      }
    }
    const orderType = (order.order_type ?? '').toString().trim().toLowerCase();
    if (orderType !== 'service' && orderType !== 'custom') {
      return res.status(400).json({ error: 'Hanya order service/custom untuk workflow workshop' });
    }

    const allowedByRole = {
      admin_toko: new Set(['awaiting_warehouse', 'ready_for_pickup']),
      admin_workshop: new Set([
        ...ADMIN_WORKSHOP_PUT_ALLOWED_STATUSES,
        'sent-to-workshop',
      ]),
      tukang: new Set([
        'in_workshop',
        'repairing',
        'polishing',
        'done_workshop',
        'custom_work',
        'cancelled',
      ]),
      superadmin: new Set([
        'awaiting_warehouse',
        'sent-to-workshop',
        'in_workshop',
        'repairing',
        'polishing',
        'done_workshop',
        'ready_for_pickup',
        'custom_work',
        'cancelled',
      ]),
      manajer: new Set([
        'awaiting_warehouse',
        'sent-to-workshop',
        'in_workshop',
        'repairing',
        'polishing',
        'done_workshop',
        'ready_for_pickup',
        'custom_work',
        'cancelled',
      ]),
      admin_warehouse: new Set(['sent-to-workshop']),
    };
    const roleAllowedSet = allowedByRole[role] ?? new Set();
    if (!roleAllowedSet.has(nextStatusRaw)) {
      return res.status(400).json({
        error: `Status "${nextStatusRaw}" tidak diizinkan untuk role ${role}`,
      });
    }

    // Guard transitions: toko → awaiting_warehouse → (gudang) sent-to-workshop → workshop …
    const validTransitions = {
      pending: new Set(['awaiting_warehouse']),
      confirmed: new Set(['awaiting_warehouse']),
      awaiting_warehouse: new Set(['sent-to-workshop']),
      'sent-to-workshop': new Set(['in_workshop']),
      in_workshop: new Set(['repairing', 'polishing', 'done_workshop']),
      repairing: new Set(['polishing', 'done_workshop']),
      polishing: new Set(['done_workshop']),
      custom_work: new Set(['done_workshop']),
      'done_workshop': new Set(['ready_for_pickup']),
      'ready_for_pickup': new Set(['completed']),
    };
    if (nextStatusRaw === 'cancelled') {
      const mayCancel =
        (role === 'tukang' || role === 'admin_workshop' || role === 'superadmin') &&
        new Set([
          'pending',
          'confirmed',
          'awaiting_warehouse',
          'sent-to-workshop',
          'in_workshop',
          'repairing',
          'polishing',
          'custom_work',
        ]).has(currentStatus);
      if (!mayCancel) {
        return res.status(400).json({
          error: `Pembatalan tidak diizinkan dari status "${currentStatus}"`,
        });
      }
    } else if (
      validTransitions[currentStatus] &&
      !validTransitions[currentStatus].has(nextStatusRaw) &&
      currentStatus !== nextStatusRaw
    ) {
      return res.status(400).json({
        error: `Transisi status tidak valid (${currentStatus} -> ${nextStatusRaw})`,
      });
    }

    const awaitingToWorkshop =
      currentStatus === 'awaiting_warehouse' &&
      nextStatusRaw === 'sent-to-workshop';
    const bindServiceWorkshopMeta =
      hasMetaPut && awaitingToWorkshop;
    if (bindServiceWorkshopMeta) {
      const originStoreId = order.branch_id;
      const metaBind = {
        service_workshop_branch_id: String(branchId),
        service_origin_branch_id: String(originStoreId),
      };
      if (hasPickupPut) {
        await db.query(
          `
          UPDATE orders
          SET
            status = $1,
            branch_id = $2::bigint,
            pickup_branch_id = COALESCE(pickup_branch_id, $3::bigint),
            updated_at = NOW(),
            metadata = COALESCE(metadata, '{}'::jsonb) || $4::jsonb
          WHERE order_id = $5
        `,
          [
            nextStatusRaw,
            branchId,
            originStoreId,
            JSON.stringify(metaBind),
            orderId,
          ]
        );
      } else {
        await db.query(
          `
          UPDATE orders
          SET
            status = $1,
            branch_id = $2::bigint,
            updated_at = NOW(),
            metadata = COALESCE(metadata, '{}'::jsonb) || $3::jsonb
          WHERE order_id = $4
        `,
          [nextStatusRaw, branchId, JSON.stringify(metaBind), orderId]
        );
      }
    } else if (awaitingToWorkshop && !hasMetaPut) {
      // Tanpa kolom metadata, service_workshop_branch_id tidak tersimpan — order tetap
      // branch_id toko sehingga tidak lolos filter workshop. Pindahkan cabang asal ke workshop yang menerima.
      // Simpan cabang toko asal di pickup_branch_id bila kosong, supaya admin toko masih lolos
      // `orderVisibleForWorkshopStatusPut` / GET saat `branch_id` sudah di workshop.
      const originStoreId = order.branch_id;
      if (hasPickupPut) {
        await db.query(
          `
          UPDATE orders
          SET
            status = $1,
            branch_id = $2::bigint,
            pickup_branch_id = COALESCE(pickup_branch_id, $3::bigint),
            updated_at = NOW()
          WHERE order_id = $4
        `,
          [nextStatusRaw, branchId, originStoreId, orderId]
        );
      } else {
        await db.query(
          `
          UPDATE orders
          SET status = $1, branch_id = $2::bigint, updated_at = NOW()
          WHERE order_id = $3
        `,
          [nextStatusRaw, branchId, orderId]
        );
      }
    } else {
      await db.query(
        `
          UPDATE orders
          SET status = $1, updated_at = NOW()
          WHERE order_id = $2
        `,
        [nextStatusRaw, orderId]
      );
    }

    if (
      nextStatusRaw === 'awaiting_warehouse' &&
      currentStatus !== 'awaiting_warehouse' &&
      role === 'admin_toko'
    ) {
      broadcastWorkshop(
        `Service/custom #${orderId} dari toko menunggu persetujuan workshop`,
        'workshop_assignment',
        {
          branch_id: branchId,
          event: 'workshop_service_pending',
          payload: { order_id: orderId, order_type: orderType, status: 'awaiting_warehouse' },
        }
      );
    }
    if (awaitingToWorkshop) {
      broadcastWorkshop(
        `Order #${orderId} disetujui — masuk antrian pekerjaan workshop`,
        'order_update',
        {
          branch_id: branchId,
          event: 'workshop_approved',
          payload: { order_id: orderId, status: 'sent-to-workshop' },
        }
      );
    }
    if (
      new Set(['in_workshop', 'repairing', 'polishing', 'custom_work']).has(nextStatusRaw) &&
      currentStatus !== nextStatusRaw
    ) {
      broadcastWorkshop(
        `Order #${orderId} sedang dikerjakan tukang (${nextStatusRaw})`,
        'order_update',
        {
          branch_id: branchId,
          event: 'workshop_in_progress',
          payload: { order_id: orderId, status: nextStatusRaw },
        }
      );
    }
    if (
      nextStatusRaw === 'ready_for_pickup' &&
      currentStatus === 'done_workshop'
    ) {
      let storeBranchId = order.branch_id;
      if (hasMetaPut && order.metadata && typeof order.metadata === 'object') {
        const origin = order.metadata.service_origin_branch_id;
        if (origin != null && String(origin).trim() !== '') {
          storeBranchId = origin;
        }
      } else if (hasPickupPut && order.pickup_branch_id != null) {
        storeBranchId = order.pickup_branch_id;
      }
      broadcastWorkshop(
        `Order service/custom #${orderId} dikirim workshop — menunggu terima di toko`,
        'store_assignment',
        {
          branch_id: storeBranchId,
          event: 'workshop_sent_to_store',
          payload: { order_id: orderId, status: 'ready_for_pickup' },
        }
      );
    }

    return res.status(200).json({
      success: true,
      order_id: String(orderId),
      old_status: currentStatus,
      new_status: nextStatusRaw,
    });
  } catch (error) {
    console.error('Error updating workshop order status:', error);
    return res.status(500).json({ error: 'Internal server error' });
  }
});

// Admin workshop: tugaskan order antrian ke tukang (metadata) tanpa alur Mulai oleh tukang.
app.put('/workshop-orders/:id/assign-technician', async (req, res) => {
  try {
    const orderId = parseInt(req.params.id, 10);
    const branchId = parseInt(String(req.body?.branch_id ?? ''), 10);
    const technicianId = parseInt(String(req.body?.technician_id ?? ''), 10);
    const startImmediately =
      req.body?.start_immediately === true ||
      String(req.body?.start_immediately ?? '').toLowerCase() === 'true';

    if (!Number.isFinite(orderId) || orderId <= 0) {
      return res.status(400).json({ error: 'order_id tidak valid' });
    }
    if (!Number.isFinite(branchId) || branchId <= 0) {
      return res.status(400).json({ error: 'branch_id wajib diisi' });
    }
    if (!Number.isFinite(technicianId) || technicianId <= 0) {
      return res.status(400).json({ error: 'technician_id wajib diisi' });
    }

    const role = (req.user?.role ?? '').toString().trim().toLowerCase();
    const allowedRoles = new Set(['admin_workshop', 'superadmin', 'manajer']);
    if (!allowedRoles.has(role)) {
      return res.status(403).json({ error: 'Role tidak diizinkan menugaskan tukang' });
    }

    const techCheck = await db.query(
      `
        SELECT u.user_id, u.username
        FROM users u
        JOIN user_branch_roles ubr ON u.user_id = ubr.user_id
        WHERE u.user_id = $1
          AND ubr.branch_id = $2
          AND ubr.role = 'tukang'
          AND u.status = 'active'
        LIMIT 1
      `,
      [technicianId, branchId]
    );
    if (techCheck.rows.length === 0) {
      return res.status(400).json({
        error: 'Tukang tidak ditemukan atau tidak aktif di cabang ini',
      });
    }
    const techUsername = techCheck.rows[0].username;

    const hasPickupAssign = await ordersHasPickupBranchColumn(db);
    const hasMetaAssign = await ordersHasMetadataColumn(db);
    const curRes = await db.query(
      `
        SELECT order_id, order_type, branch_id, status
          ${hasPickupAssign ? ', pickup_branch_id' : ''}
          ${hasMetaAssign ? ', metadata' : ''}
        FROM orders
        WHERE order_id = $1
        LIMIT 1
      `,
      [orderId]
    );
    if (curRes.rows.length === 0) {
      return res.status(404).json({ error: 'Order tidak ditemukan' });
    }
    const order = curRes.rows[0];
    const visibleAssign = await orderVisibleForWorkshopStatusPut(
      db,
      orderId,
      branchId,
      hasPickupAssign,
      hasMetaAssign
    );
    if (!visibleAssign) {
      return res.status(403).json({ error: 'Order tidak untuk cabang workshop ini' });
    }

    const orderType = (order.order_type ?? '').toString().trim().toLowerCase();
    if (orderType !== 'service' && orderType !== 'custom') {
      return res.status(400).json({
        error: 'Hanya order service/custom yang bisa ditugaskan ke tukang',
      });
    }

    const currentStatus = (order.status ?? '').toString().trim().toLowerCase();
    const assignableStatuses = new Set([
      'sent-to-workshop',
      'in_workshop',
      'repairing',
      'polishing',
      'custom_work',
    ]);
    if (!assignableStatuses.has(currentStatus)) {
      return res.status(400).json({
        error: `Penugasan tidak diizinkan dari status "${currentStatus}"`,
      });
    }

    let nextStatus = currentStatus;
    if (startImmediately) {
      nextStatus = orderType === 'custom' ? 'custom_work' : 'repairing';
    } else if (currentStatus === 'sent-to-workshop') {
      nextStatus = 'in_workshop';
    }

    const metaPatch = {
      assigned_technician_id: String(technicianId),
      assigned_technician: techUsername,
      assigned_by_role: role,
      assigned_at: new Date().toISOString(),
    };
    if (req.user?.user_id != null) {
      metaPatch.assigned_by_user_id = String(req.user.user_id);
    }

    if (hasMetaAssign) {
      await db.query(
        `
          UPDATE orders
          SET status = $1,
              updated_at = NOW(),
              metadata = COALESCE(metadata, '{}'::jsonb) || $2::jsonb
          WHERE order_id = $3
        `,
        [nextStatus, JSON.stringify(metaPatch), orderId]
      );
    } else {
      await db.query(
        `
          UPDATE orders
          SET status = $1,
              updated_at = NOW(),
              user_id = $2::bigint
          WHERE order_id = $3
        `,
        [nextStatus, technicianId, orderId]
      );
    }

    if (
      new Set(['in_workshop', 'repairing', 'polishing', 'custom_work']).has(nextStatus) &&
      currentStatus !== nextStatus
    ) {
      broadcastWorkshop(
        `Order #${orderId} ditugaskan ke ${techUsername} (${nextStatus})`,
        'order_update',
        {
          branch_id: branchId,
          event: 'workshop_in_progress',
          payload: {
            order_id: orderId,
            status: nextStatus,
            technician_id: technicianId,
          },
        }
      );
    } else {
      broadcastWorkshop(
        `Order #${orderId} ditugaskan ke ${techUsername}`,
        'workshop_assignment',
        {
          branch_id: branchId,
          event: 'workshop_assigned',
          payload: {
            order_id: orderId,
            technician_id: technicianId,
            status: nextStatus,
          },
        }
      );
    }

    return res.status(200).json({
      success: true,
      order_id: String(orderId),
      technician_id: String(technicianId),
      technician_username: techUsername,
      old_status: currentStatus,
      new_status: nextStatus,
    });
  } catch (error) {
    console.error('Error assigning workshop technician:', error);
    return res.status(500).json({ error: 'Internal server error' });
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

}

module.exports = { registerWorkshopRoutes };

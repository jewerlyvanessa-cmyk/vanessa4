'use strict';

const {
  ordersHasMetadataColumnLive,
  jsonSafeDbRow,
} = require('../lib/orders_workshop_helpers');


function registerWorkshopMaterialRoutes(workshopApi, { db, broadcastWorkshop }) {
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

}

module.exports = { registerWorkshopMaterialRoutes };

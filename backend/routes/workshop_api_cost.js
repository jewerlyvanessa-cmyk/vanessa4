'use strict';

const {
  ordersHasPickupBranchColumn,
  ordersHasMetadataColumn,
  orderCostBreakdownsTableExists,
  ensureOrderCostBreakdownsSchema,
  orderVisibleAtWorkshopBranchId,
} = require('../lib/orders_workshop_helpers');


function registerWorkshopCostRoutes(workshopApi, { db }) {
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

}

module.exports = { registerWorkshopCostRoutes };

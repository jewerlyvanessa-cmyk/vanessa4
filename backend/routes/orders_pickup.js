'use strict';

const {
  ordersHasMetadataColumn,
  ordersHasPickupBranchColumn,
  orderAllowedForStorePickup,
} = require('../lib/orders_workshop_helpers');
const {
  ordersHasPickedUpAtColumn,
  paymentsHasRevenueBranchColumn,
} = require('../lib/payments_schema_helpers');
const { writeAuditLog } = require('../lib/audit_log');

/** POST /orders/pickup — service/custom order diambil customer. */
function registerOrdersPickupRoutes(app, deps) {
  const { db, notifyClients } = deps;

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
        [whereVal],
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
        [ord.order_id],
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
          [nextStatus, pickedBy, notesText, photoText, ord.order_id],
        );
      } else {
        await client.query(
          `
            UPDATE orders
            SET status = $1,
                updated_at = NOW()
            WHERE order_id = $2
          `,
          [nextStatus, ord.order_id],
        );
      }

      await client.query('COMMIT');
      notifyClients(`Order ${ord.order_id} (${ot}) telah diambil customer, status ${nextStatus}`);

      await writeAuditLog(db, req, {
        action: 'order.pickup',
        entityType: 'order',
        entityId: ord.order_id,
        branchId,
        payload: {
          order_number: ord.order_number,
          order_type: ot,
          next_status: nextStatus,
          remaining_amount: remaining,
        },
      });

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
      } catch (_) {}
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
      } catch (_) {}
    }
  });
}

module.exports = { registerOrdersPickupRoutes };

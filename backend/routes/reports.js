'use strict';

const getOrdersDaily = require('./orders_daily_handler');
const {
  DATE_RE,
  todayYmdWib,
  resolveOwnerDashboardBranchIds,
  fetchOwnerStockTotals,
  fetchOwnerPaymentSummary,
} = require('../lib/owner_dashboard_helpers');

function registerReportsRoutes(app, deps) {
  const { db } = deps;

  /**
   * Dashboard Owner — satu round-trip: ringkasan + order harian lintas cabang.
   * Query: date (yyyy-MM-dd), branch_ids (opsional), scope=global (semua cabang aktif).
   */
  app.get('/reports/owner-dashboard', async (req, res) => {
    try {
      const resolved = await resolveOwnerDashboardBranchIds(req, db);
      if (!resolved.ok) {
        return res.status(resolved.status).json(resolved.body);
      }

      const dateRaw = String(req.query.date ?? '').trim();
      const dateYmd = DATE_RE.test(dateRaw) ? dateRaw : todayYmdWib();
      const branchIds = resolved.branchIds;
      const salesBranchIds = resolved.salesBranchIds ?? [];

      if (branchIds.length === 0 && salesBranchIds.length === 0) {
        return res.status(200).json({
          date: dateYmd,
          summary: {
            sales_amount: 0,
            sales_payment_count: 0,
            buyback_amount: 0,
            buyback_payment_count: 0,
            stock_ready_qty: 0,
            stock_ready_sku: 0,
            order_count: 0,
            branch_count: 0,
            stock_branch_count: 0,
          },
          scope: resolved.scope ?? 'assigned',
          orders: [],
        });
      }

      const orderBranchIds =
        salesBranchIds.length > 0 ? salesBranchIds : branchIds;

      const branchMeta = await db.query(
        `
          SELECT branch_id, name
          FROM branches
          WHERE branch_id = ANY($1::bigint[])
        `,
        [orderBranchIds]
      );
      const nameById = new Map(
        branchMeta.rows.map((r) => [
          String(r.branch_id),
          (r.name ?? `Cabang ${r.branch_id}`).toString(),
        ])
      );

      const [stockTotals, perBranch] = await Promise.all([
        fetchOwnerStockTotals(db, branchIds),
        Promise.all(
          salesBranchIds.map(async (branchId) => {
            const pay = await fetchOwnerPaymentSummary(db, req, branchId, dateYmd);
            const ordersReq = {
              ...req,
              query: { branch_id: String(branchId), date: dateYmd },
            };
            const ordersResult =
              await getOrdersDaily.fetchOrdersDailyPayload(ordersReq);
            const orders =
              ordersResult.ok && Array.isArray(ordersResult.rows)
                ? ordersResult.rows
                : [];
            const branchName = nameById.get(String(branchId)) ?? `Cabang ${branchId}`;
            const tagged = orders.map((row) => ({
              ...row,
              branch_id: String(branchId),
              branch_name: branchName,
            }));
            const orderIds = new Set();
            for (const row of orders) {
              const oid = row?.order_id?.toString?.() ?? row?.order_id;
              if (oid) orderIds.add(String(oid));
            }
            return {
              pay,
              orders: tagged,
              order_count: orderIds.size,
            };
          })
        ),
      ]);

      let salesAmount = 0;
      let salesPaymentCount = 0;
      let buybackAmount = 0;
      let buybackPaymentCount = 0;
      let orderCount = 0;
      const allOrders = [];

      for (const part of perBranch) {
        salesAmount += part.pay.total_amount;
        salesPaymentCount += part.pay.total_payments;
        buybackAmount += part.pay.expense_amount;
        buybackPaymentCount += part.pay.buyback_payments;
        orderCount += part.order_count;
        allOrders.push(...part.orders);
      }

      allOrders.sort((a, b) => {
        const ta = a?.created_at ? new Date(a.created_at).getTime() : 0;
        const tb = b?.created_at ? new Date(b.created_at).getTime() : 0;
        return tb - ta;
      });

      return res.status(200).json({
        date: dateYmd,
        summary: {
          sales_amount: salesAmount,
          sales_payment_count: salesPaymentCount,
          buyback_amount: buybackAmount,
          buyback_payment_count: buybackPaymentCount,
          stock_ready_qty: stockTotals.ready_qty,
          stock_ready_sku: stockTotals.ready_sku,
          order_count: orderCount,
          branch_count: salesBranchIds.length,
          stock_branch_count: branchIds.length,
        },
        scope: resolved.scope ?? 'assigned',
        orders: allOrders,
      });
    } catch (error) {
      console.error('[reports/owner-dashboard]', error);
      return res.status(500).json({
        error: 'Internal server error',
        detail: error.message,
      });
    }
  });

  /** Manajer: daftar order completed hari ini dari semua branch */
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
      const processed = result.rows.map((r) => ({
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
}

module.exports = { registerReportsRoutes };

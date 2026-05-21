'use strict';

const db = require('../db');
const { assertUserCanAccessBranchForOrders } = require('../routes/order_branch_scope');
const { ORDER_CALENDAR_TIMEZONE } = require('./business_timezone');
const {
  timestampOnBusinessDateSql,
  timestampOnBusinessDateBetweenSql,
  paymentActivityDateSql,
  paymentActivityDateBetweenSql,
} = require('./order_calendar_date_sql');
const { paymentsHasPaymentDateColumn } = require('./payments_schema_helpers');
const { resolveCsOrderUserFilterFromReq } = require('./order_scope_helpers');

function orderTodayUserFilterFromJwt(req) {
  return resolveCsOrderUserFilterFromReq(req);
}

/**
 * @returns {Promise<{ ok: true, data: object } | { ok: false, status: number, body: object }>}
 */
async function computeOrderTodayStats(req) {
  try {
    const scope = await assertUserCanAccessBranchForOrders(req, req.query.branch_id);
    if (!scope.ok) {
      return { ok: false, status: scope.status, body: scope.body };
    }
    const branchId = scope.branchId;
    const filterUserId = orderTodayUserFilterFromJwt(req);

    const datePat = /^\d{4}-\d{2}-\d{2}$/;
    const dfClient = String(req.query.date_from ?? '').trim();
    const dtClient = String(req.query.date_to ?? '').trim();
    const useRange = datePat.test(dfClient) && datePat.test(dtClient);
    const MAX_RANGE_DAYS = 93;

    if (useRange && dfClient > dtClient) {
      return { ok: false, status: 400, body: { error: 'date_from harus <= date_to' } };
    }
    if (useRange) {
      const spanMs =
        Date.parse(`${dtClient}T12:00:00`) - Date.parse(`${dfClient}T12:00:00`);
      const spanDays = Math.floor(spanMs / 86400000) + 1;
      if (spanDays > MAX_RANGE_DAYS) {
        return {
          ok: false,
          status: 400,
          body: { error: `Rentang tanggal maksimal ${MAX_RANGE_DAYS} hari` },
        };
      }
    }

    const dateFromClient =
      req.query.date && String(req.query.date).trim().length > 0
        ? String(req.query.date).trim()
        : '';
    const localToday =
      !useRange && dateFromClient && datePat.test(dateFromClient)
        ? dateFromClient
        : !useRange
          ? new Intl.DateTimeFormat('en-CA', {
            timeZone: ORDER_CALENDAR_TIMEZONE,
            year: 'numeric',
            month: '2-digit',
            day: '2-digit',
          }).format(new Date())
          : null;

    const hasPaymentDateCol = await paymentsHasPaymentDateColumn(db);
    const orderCreatedDateEq = (paramRef) =>
      timestampOnBusinessDateSql('o.created_at', paramRef);
    const paymentCreatedDateEq = (paramRef) =>
      paymentActivityDateSql('p', paramRef, hasPaymentDateCol);
    const orderCreatedDateBetween = (fromRef, toRef) =>
      timestampOnBusinessDateBetweenSql('o.created_at', fromRef, toRef);
    const paymentCreatedDateBetween = (fromRef, toRef) =>
      paymentActivityDateBetweenSql('p', fromRef, toRef, hasPaymentDateCol);

    // IN (bukan EXISTS berkorelasi) → sering lebih mudah dioptimalkan planner untuk semi-join.
    const dayMatchSql = useRange
      ? `(
        ${orderCreatedDateBetween('$1', '$2')}
        OR o.order_id IN (
          SELECT p.order_id
          FROM payments p
          WHERE p.status = 'completed'
            AND ${paymentCreatedDateBetween('$1', '$2')}
        )
      )`
      : `(
        ${orderCreatedDateEq('$1')}
        OR o.order_id IN (
          SELECT p.order_id
          FROM payments p
          WHERE p.status = 'completed'
            AND ${paymentCreatedDateEq('$1')}
        )
      )`;
    let whereClause = useRange
      ? `WHERE ${dayMatchSql} AND o.branch_id = $3`
      : `WHERE ${dayMatchSql} AND o.branch_id = $2`;
    let queryParams = useRange
      ? [dfClient, dtClient, branchId]
      : [localToday, branchId];
    let paramIndex = useRange ? 4 : 3;

    if (filterUserId != null) {
      whereClause += ` AND o.user_id = $${paramIndex}`;
      queryParams.push(filterUserId);
      paramIndex++;
    }

    const statsQuery = `
      SELECT
        COUNT(DISTINCT o.order_id) as total_orders,
        COUNT(DISTINCT CASE WHEN lower(trim(coalesce(o.status::text, ''))) IN ('completed', 'sold') THEN o.order_id END) as completed_orders,
        COUNT(DISTINCT CASE WHEN lower(trim(coalesce(o.status::text, ''))) NOT IN ('completed', 'sold', 'cancelled') THEN o.order_id END) as pending_orders,
        COUNT(DISTINCT CASE WHEN o.order_type = 'jual' THEN o.order_id END) as jual_count,
        COUNT(DISTINCT CASE WHEN o.order_type = 'buyback' THEN o.order_id END) as buyback_count,
        COUNT(DISTINCT CASE WHEN o.order_type = 'service' THEN o.order_id END) as service_count,
        COUNT(DISTINCT CASE WHEN o.order_type = 'custom' THEN o.order_id END) as custom_count,
        COUNT(DISTINCT CASE
          WHEN lower(trim(coalesce(o.mode::text, ''))) = 'online' THEN o.order_id
        END) as mode_online_count,
        COUNT(DISTINCT CASE
          WHEN lower(trim(coalesce(o.mode::text, ''))) <> 'online' THEN o.order_id
        END) as mode_toko_count,
        COALESCE(SUM(CASE
          WHEN o.order_type = 'jual'
            AND lower(trim(coalesce(o.status::text, ''))) IN ('completed', 'sold')
            THEN COALESCE(o.total, 0)
          ELSE 0
        END), 0) as revenue_jual_completed,
        COALESCE(SUM(CASE
          WHEN o.order_type = 'buyback'
            AND lower(trim(coalesce(o.status::text, ''))) = 'completed'
            THEN COALESCE(o.total, 0)
          ELSE 0
        END), 0) as expense_buyback_completed
      FROM orders o
      ${whereClause}
    `;

    const statusQuery = `
      SELECT o.status, COUNT(DISTINCT o.order_id) as count
      FROM orders o
      ${whereClause}
      GROUP BY o.status
    `;

    const [statsResult, statusResult] = await Promise.all([
      db.query(statsQuery, queryParams),
      db.query(statusQuery, queryParams),
    ]);
    const stats = statsResult.rows[0];

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
      orders_by_mode: {
        toko: parseInt(stats.mode_toko_count) || 0,
        online: parseInt(stats.mode_online_count) || 0,
      },
      orders_by_status: {
        draft: 0,
        reserved: 0,
        sold: 0,
        buyback: 0,
        'on-service': 0,
        production: 0,
      },
      revenue_by_type_completed: {
        jual: parseFloat(stats.revenue_jual_completed) || 0,
        buyback: -1 * (parseFloat(stats.expense_buyback_completed) || 0),
        service: 0,
        custom: 0,
      },
      revenue_jual_completed: parseFloat(stats.revenue_jual_completed) || 0,
      expense_buyback_completed: parseFloat(stats.expense_buyback_completed) || 0,
      total_revenue:
        (parseFloat(stats.revenue_jual_completed) || 0) -
        (parseFloat(stats.expense_buyback_completed) || 0),
      date: new Date().toISOString(),
    };

    statusResult.rows.forEach((row) => {
      response.orders_by_status[row.status] = parseInt(row.count);
    });

    return { ok: true, data: response };
  } catch (error) {
    console.error('Error fetching order today stats:', error);
    return {
      ok: false,
      status: 500,
      body: {
        error: 'Internal server error',
        detail: error && error.message ? String(error.message) : undefined,
      },
    };
  }
}

module.exports = { computeOrderTodayStats, orderTodayUserFilterFromJwt };

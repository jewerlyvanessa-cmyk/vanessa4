'use strict';

const db = require('../db');
const { assertUserCanAccessBranchForOrders } = require('../routes/order_branch_scope');

const ORDER_CALENDAR_TIMEZONE =
  /^[\w/-]+$/.test(String(process.env.BUSINESS_TIMEZONE || '').trim())
    ? String(process.env.BUSINESS_TIMEZONE).trim()
    : 'Asia/Jakarta';

function orderTodayUserFilterFromJwt(req) {
  const role = (req.user?.role ?? '').toString().trim().toLowerCase();
  if (role !== 'cs') return null;
  const uid = parseInt(String(req.user?.user_id ?? req.user?.id ?? ''), 10);
  if (!Number.isFinite(uid) || uid <= 0) return null;
  return uid;
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

    const orderCreatedDateEq = (paramRef) => `
      (
        o.created_at::date = ${paramRef}::date
        OR (timezone('${ORDER_CALENDAR_TIMEZONE}', o.created_at AT TIME ZONE 'UTC'))::date = ${paramRef}::date
      )
    `;
    const paymentCreatedDateEq = (paramRef) => `
      (
        p.created_at::date = ${paramRef}::date
        OR (timezone('${ORDER_CALENDAR_TIMEZONE}', p.created_at))::date = ${paramRef}::date
        OR (timezone('${ORDER_CALENDAR_TIMEZONE}', p.created_at AT TIME ZONE 'UTC'))::date = ${paramRef}::date
      )
    `;
    const orderCreatedDateBetween = (fromRef, toRef) => `
      (
        o.created_at::date BETWEEN ${fromRef}::date AND ${toRef}::date
        OR (timezone('${ORDER_CALENDAR_TIMEZONE}', o.created_at AT TIME ZONE 'UTC'))::date BETWEEN ${fromRef}::date AND ${toRef}::date
      )
    `;
    const paymentCreatedDateBetween = (fromRef, toRef) => `
      (
        p.created_at::date BETWEEN ${fromRef}::date AND ${toRef}::date
        OR (timezone('${ORDER_CALENDAR_TIMEZONE}', p.created_at))::date BETWEEN ${fromRef}::date AND ${toRef}::date
        OR (timezone('${ORDER_CALENDAR_TIMEZONE}', p.created_at AT TIME ZONE 'UTC'))::date BETWEEN ${fromRef}::date AND ${toRef}::date
      )
    `;

    const dayMatchSql = useRange
      ? `(
        ${orderCreatedDateBetween('$1', '$2')}
        OR EXISTS (
          SELECT 1
          FROM payments p
          WHERE p.order_id = o.order_id
            AND p.status = 'completed'
            AND ${paymentCreatedDateBetween('$1', '$2')}
        )
      )`
      : `(
        ${orderCreatedDateEq('$1')}
        OR EXISTS (
          SELECT 1
          FROM payments p
          WHERE p.order_id = o.order_id
            AND p.status = 'completed'
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
            THEN COALESCE(o.jumlah, o.total, 0)
          ELSE 0
        END), 0) as revenue_jual_completed,
        COALESCE(SUM(CASE
          WHEN o.order_type = 'buyback'
            AND lower(trim(coalesce(o.status::text, ''))) = 'completed'
            THEN COALESCE(o.jumlah, o.total, 0)
          ELSE 0
        END), 0) as expense_buyback_completed
      FROM orders o
      ${whereClause}
    `;

    const statsResult = await db.query(statsQuery, queryParams);
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

    const statusQuery = `
      SELECT o.status, COUNT(DISTINCT o.order_id) as count
      FROM orders o
      ${whereClause}
      GROUP BY o.status
    `;

    const statusResult = await db.query(statusQuery, queryParams);
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

'use strict';

function registerAdminApiRoutes(app, deps) {
  const { db, wsPresence, orderCalendarTimezone, requireRoles, authRequired } = deps;
  const ORDER_CALENDAR_TIMEZONE = orderCalendarTimezone;
  app.get('/api/whoami', authRequired, (req, res) => {
    res.json({ user: req.user ?? null });
  });
  
  // Debug helper: sanity-check "Order Today" counts on server.
  // Safe: requires auth; returns aggregate counts only.
  app.get('/api/debug/order-today-sanity', authRequired, async (req, res) => {
    try {
      const tz = ORDER_CALENDAR_TIMEZONE;
      const bidRaw = String(req.query.branch_id ?? '').trim();
      const branchId = parseInt(bidRaw, 10);
      if (!Number.isFinite(branchId) || branchId <= 0) {
        return res.status(400).json({ error: 'branch_id is required' });
      }
      const datePat = /^\\d{4}-\\d{2}-\\d{2}$/;
      const dateKey = datePat.test(String(req.query.date ?? '').trim())
        ? String(req.query.date).trim()
        : new Intl.DateTimeFormat('en-CA', {
          timeZone: tz,
          year: 'numeric',
          month: '2-digit',
          day: '2-digit',
        }).format(new Date());
  
      const userId = parseInt(
        String(req.user?.user_id ?? req.user?.id ?? ''),
        10,
      );
      const role = String(req.user?.role ?? '').trim().toLowerCase();
  
      const q = `
        SELECT
          COUNT(*) FILTER (
            WHERE o.branch_id = $1
              AND (timezone('${tz}', o.created_at))::date = $2::date
          ) AS orders_created_today,
          COUNT(*) FILTER (
            WHERE o.branch_id = $1
              AND EXISTS (
                SELECT 1
                FROM payments p
                WHERE p.order_id = o.order_id
                  AND p.status = 'completed'
                  AND (timezone('${tz}', p.created_at))::date = $2::date
              )
          ) AS orders_paid_today,
          COUNT(*) FILTER (
            WHERE o.branch_id = $1
              AND (
                (timezone('${tz}', o.created_at))::date = $2::date
                OR EXISTS (
                  SELECT 1
                  FROM payments p
                  WHERE p.order_id = o.order_id
                    AND p.status = 'completed'
                    AND (timezone('${tz}', p.created_at))::date = $2::date
                )
              )
          ) AS orders_today_union,
          COUNT(*) FILTER (
            WHERE o.branch_id = $1
              AND (
                (timezone('${tz}', o.created_at))::date = $2::date
                OR EXISTS (
                  SELECT 1
                  FROM payments p
                  WHERE p.order_id = o.order_id
                    AND p.status = 'completed'
                    AND (timezone('${tz}', p.created_at))::date = $2::date
                )
              )
              AND o.user_id = $3
          ) AS orders_today_by_user,
          COUNT(*) FILTER (
            WHERE o.branch_id = $1
              AND (
                (timezone('${tz}', o.created_at))::date = $2::date
                OR EXISTS (
                  SELECT 1
                  FROM payments p
                  WHERE p.order_id = o.order_id
                    AND p.status = 'completed'
                    AND (timezone('${tz}', p.created_at))::date = $2::date
                )
              )
              AND o.user_id IS NULL
          ) AS orders_today_user_null,
          MIN(o.created_at) FILTER (WHERE o.branch_id = $1) AS min_created_at_branch,
          MAX(o.created_at) FILTER (WHERE o.branch_id = $1) AS max_created_at_branch
        FROM orders o
      `;
  
      const r = await db.query(q, [
        branchId,
        dateKey,
        Number.isFinite(userId) ? userId : -1,
      ]);
  
      res.json({
        ok: true,
        tz,
        dateKey,
        branchId,
        auth: { role, userId: Number.isFinite(userId) ? userId : null },
        counts: r.rows?.[0] ?? null,
      });
    } catch (e) {
      console.error('debug/order-today-sanity error:', e);
      res.status(500).json({ error: 'Internal server error' });
    }
  });
  
  app.get('/api/admin/active-sessions', requireRoles('superadmin'), (req, res) => {
    res.json(wsPresence.getActivePresenceSnapshot());
  });
  
  // Superadmin: logout paksa semua koneksi Live (WebSocket) milik user — klien menerima force_logout.
  app.post('/api/admin/active-sessions/:userId/kick', requireRoles('superadmin'), (req, res) => {
    try {
      const targetId = parseInt(String(req.params.userId), 10);
      if (!Number.isFinite(targetId)) {
        return res.status(400).json({ error: 'userId tidak valid' });
      }
      const adminId = parseInt(String(req.user?.user_id ?? req.user?.id ?? ''), 10);
      if (Number.isFinite(adminId) && adminId === targetId) {
        return res.status(400).json({
          error: 'Tidak dapat melogoutkan diri sendiri dari panel ini (gunakan logout).',
        });
      }
      const reasonRaw = req.body && req.body.reason != null ? String(req.body.reason) : '';
      const reason = reasonRaw.trim().slice(0, 500) || undefined;
      const { closed } = wsPresence.disconnectPresenceSessionsForUser(targetId, reason);
      res.json({ ok: true, closed, user_id: String(targetId) });
    } catch (error) {
      console.error('Error kicking active sessions:', error);
      res.status(500).json({ error: 'Internal server error' });
    }
  });
}

module.exports = { registerAdminApiRoutes };

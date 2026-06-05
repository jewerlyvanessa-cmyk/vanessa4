'use strict';

const fs = require('fs');

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
  
  async function enrichActivePresenceSnapshot(snapshot) {
    const users = Array.isArray(snapshot?.users) ? snapshot.users : [];
    const globalRoles = new Set(['superadmin', 'owner', 'manajer']);
    const branchIdNums = new Set();
    for (const u of users) {
      const role = String(u.role_active ?? '').trim().toLowerCase();
      if (globalRoles.has(role)) continue;
      for (const raw of u.branch_ids || []) {
        const n = parseInt(String(raw), 10);
        if (Number.isFinite(n) && n > 0) branchIdNums.add(n);
      }
    }
    const nameById = new Map();
    if (branchIdNums.size > 0) {
      try {
        const r = await db.query(
          `
            SELECT branch_id, name, alias
            FROM branches
            WHERE branch_id = ANY($1::bigint[])
          `,
          [[...branchIdNums]],
        );
        for (const row of r.rows) {
          const id = String(row.branch_id);
          const alias = (row.alias ?? '').toString().trim();
          const name = (row.name ?? '').toString().trim();
          nameById.set(id, alias || name || id);
        }
      } catch (e) {
        console.warn('[active-sessions] enrich branches:', e.message);
      }
    }
    for (const u of users) {
      const role = String(u.role_active ?? '').trim().toLowerCase();
      if (globalRoles.has(role)) {
        u.branch_display = 'Lintas cabang';
        u.branch_id = '';
        continue;
      }
      const labels = (u.branch_ids || [])
        .map((id) => nameById.get(String(id)) || String(id))
        .filter((s) => s.trim() !== '');
      u.branch_display = labels.length ? labels.join(', ') : '—';
      u.branch_id = u.branch_ids?.[0] != null ? String(u.branch_ids[0]) : '';
    }
    return snapshot;
  }

  app.get('/api/admin/active-sessions', requireRoles('superadmin'), async (req, res) => {
    try {
      const snapshot = wsPresence.getActivePresenceSnapshot();
      await enrichActivePresenceSnapshot(snapshot);
      res.json(snapshot);
    } catch (error) {
      console.error('Error fetching active sessions:', error);
      res.status(500).json({ error: 'Internal server error' });
    }
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

  app.get(
    '/api/admin/backup/google-drive/status',
    requireRoles('superadmin'),
    (req, res) => {
      try {
        const { getGoogleDriveBackupStatus } = require('../lib/google_drive_backup');
        res.json(getGoogleDriveBackupStatus());
      } catch (error) {
        console.error('[backup/google-drive/status]', error);
        res.status(500).json({ error: 'Internal server error' });
      }
    },
  );

  app.post(
    '/api/admin/backup/local',
    requireRoles('superadmin'),
    async (req, res) => {
      let dump;
      try {
        const { createPgDumpTempFile } = require('../lib/db_pg_dump');
        dump = await createPgDumpTempFile();
        const stat = fs.statSync(dump.filePath);
        res.setHeader('Content-Type', 'application/sql; charset=utf-8');
        res.setHeader(
          'Content-Disposition',
          `attachment; filename="${dump.fileName}"`,
        );
        res.setHeader('Content-Length', String(stat.size));

        const stream = fs.createReadStream(dump.filePath);
        const cleanup = () => {
          try {
            dump.cleanup();
          } catch (_) {
            /* ignore */
          }
        };
        stream.on('error', (err) => {
          cleanup();
          if (!res.headersSent) {
            res.status(500).json({
              error: err.message || 'Gagal membaca file backup',
            });
          } else {
            res.end();
          }
        });
        res.on('close', cleanup);
        stream.on('end', cleanup);
        stream.pipe(res);
      } catch (error) {
        if (dump) {
          try {
            dump.cleanup();
          } catch (_) {
            /* ignore */
          }
        }
        console.error('[backup/local]', error);
        if (!res.headersSent) {
          const msg = error.message || 'Gagal backup lokal';
          const hint =
            msg.includes('pg_dump') || msg.includes('ENOENT')
              ? 'Pastikan pg_dump terpasang di server dan PATH benar.'
              : undefined;
          res.status(500).json({
            error: msg,
            hint,
          });
        }
      }
    },
  );

  app.post(
    '/api/admin/backup/google-drive',
    requireRoles('superadmin'),
    async (req, res) => {
      try {
        const { runDatabaseBackupToGoogleDrive } = require('../lib/google_drive_backup');
        const result = await runDatabaseBackupToGoogleDrive();
        res.json(result);
      } catch (error) {
        if (error.code === 'NOT_CONFIGURED' || error.code === 'MODULE_NOT_FOUND') {
          let status = {};
          try {
            status = require('../lib/google_drive_backup').getGoogleDriveBackupStatus();
          } catch (_) {
            /* ignore */
          }
          return res.status(503).json({
            error: error.message,
            ...status,
          });
        }
        console.error('[backup/google-drive]', error);
        res.status(500).json({
          error: error.message || 'Gagal backup ke Google Drive',
        });
      }
    },
  );
}

module.exports = { registerAdminApiRoutes };

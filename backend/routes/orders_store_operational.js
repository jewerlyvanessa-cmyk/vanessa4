'use strict';

const { ORDER_CALENDAR_TIMEZONE } = require('../lib/business_timezone');
const {
  timestampOnBusinessDateSql,
  timestampOnBusinessDateBetweenSql,
} = require('../lib/order_calendar_date_sql');
const { writeAuditLog } = require('../lib/audit_log');

function registerOrdersStoreOperationalRoutes(app, deps) {
  const { db } = deps;

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
    if (
      role === 'kasir' ||
      role === 'manajer' ||
      role === 'admin_warehouse' ||
      role === 'admin_workshop' ||
      role === 'superadmin' ||
      role === 'owner'
    ) {
      return true;
    }
    res.status(403).json({
      error: 'Tidak punya akses mengelola kategori',
    });
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

  app.delete('/store-operational/categories/:category_id', async (req, res) => {
    try {
      if (!assertStoreOperationalCategoryManager(req, res)) return;

      const categoryIdRaw = (req.params.category_id ?? '').toString().trim();
      const categoryId = parseInt(categoryIdRaw, 10);
      if (!Number.isFinite(categoryId) || categoryId <= 0) {
        return res.status(400).json({ error: 'category_id tidak valid' });
      }

      const upd = await db.query(
        `
          UPDATE store_operational_categories
          SET is_active = FALSE, updated_at = NOW()
          WHERE category_id = $1 AND is_active = TRUE
          RETURNING category_id, name, entry_kind, sort_order, is_active
        `,
        [categoryId]
      );
      if (upd.rows.length === 0) {
        return res.status(404).json({ error: 'Kategori tidak ditemukan' });
      }
      return res.status(200).json({
        message: 'Kategori dihapus',
        category: mapStoreOperationalCategoryRow(upd.rows[0]),
      });
    } catch (e) {
      console.error('Error deleting store-operational category:', e);
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
      await writeAuditLog(db, req, {
        action: 'store_operational.create',
        entityType: 'store_operational_entry',
        entityId: r.entry_id != null ? String(r.entry_id) : null,
        branchId,
        payload: {
          amount: amt,
          category: cat,
          entry_kind: entryKind,
        },
      });
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

}

module.exports = { registerOrdersStoreOperationalRoutes };

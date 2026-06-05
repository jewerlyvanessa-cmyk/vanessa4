'use strict';

const { getItemsColumnFlags, itemsHasCreatedByColumn } = require('../lib/items_schema_helpers');
const { parseQueryLimit } = require('../lib/query_limits');
const { writeAuditLog } = require('../lib/audit_log');
const { assertUserCanAccessBranchForOrders } = require('./order_branch_scope');

function registerItemsRoutes(app, deps) {
  const { db } = deps;
  app.get('/item-conditions', async (req, res) => {
    try {
      const { item_id, order_id, branch_id } = req.query;
  
      let query = `
        SELECT
          ic.condition_id,
          ic.item_id,
          ic.order_id,
          ic.kondisi_fisik,
          ic.penyesuaian_berat,
          ic.nilai_resale,
          ic.harga_per_gram,
          ic.potongan_kondisi,
          ic.untung_rugi,
          ic.nilai_untung_rugi,
          ic.catatan_kondisi,
          ic.foto_kondisi,
          ic.created_at,
          ic.updated_at,
          i.name as item_name,
          i.kode_produk,
          i.weight as item_weight,
          i.material,
          i.purity,
          o.order_number,
          o.order_type,
          c.name as customer_name
        FROM item_conditions ic
        JOIN items i ON ic.item_id = i.item_id
        JOIN orders o ON ic.order_id = o.order_id
        JOIN customers c ON o.customer_id = c.customer_id
      `;
  
      let params = [];
      let conditions = [];
  
      if (item_id) {
        conditions.push(`ic.item_id = $${params.length + 1}`);
        params.push(item_id);
      }
  
      if (order_id) {
        conditions.push(`ic.order_id = $${params.length + 1}`);
        params.push(order_id);
      }
  
      if (branch_id) {
        conditions.push(`o.branch_id = $${params.length + 1}`);
        params.push(branch_id);
      }
  
      if (conditions.length > 0) {
        query += ' WHERE ' + conditions.join(' AND ');
      }
  
      query += ' ORDER BY ic.created_at DESC';
  
      const result = await db.query(query, params);
  
      // Convert BigInt and other data types for JSON serialization
      const processedRows = result.rows.map(row => ({
        condition_id: row.condition_id.toString(),
        item_id: row.item_id.toString(),
        order_id: row.order_id.toString(),
        kondisi_fisik: row.kondisi_fisik,
        kerusakan: [],
        penyesuaian_berat: row.penyesuaian_berat,
        nilai_resale: parseInt(row.nilai_resale || 0),
        harga_per_gram: parseFloat(row.harga_per_gram || 0),
        potongan_kondisi: parseFloat(row.potongan_kondisi || 0),
        untung_rugi: row.untung_rugi,
        nilai_untung_rugi: parseFloat(row.nilai_untung_rugi || 0),
        catatan_kondisi: row.catatan_kondisi,
        foto_kondisi: row.foto_kondisi || [],
        created_at: row.created_at,
        updated_at: row.updated_at,
        item_name: row.item_name,
        kode_produk: row.kode_produk,
        item_weight: parseFloat(row.item_weight || 0),
        material: row.material,
        purity: row.purity,
        order_number: row.order_number,
        order_type: row.order_type,
        customer_name: row.customer_name,
      }));
  
      res.status(200).json(processedRows);
    } catch (error) {
      console.error('Error fetching item conditions:', error);
      res.status(500).json({ error: 'Internal server error', details: error.message });
    }
  });
  app.get('/items', async (req, res) => {
    try {
      const {
        branch_id,
        item_code,
        stock_type: _stock_type,
        status,
        is_quick_registered,
        search,
        limit,
        sellable_only,
        in_stock_only,
        created_by,
        mine,
        start_date,
        end_date,
        source,
      } = req.query;
      const roleNorm = String(req.user?.role ?? '')
        .trim()
        .toLowerCase();
      const hasCreatorCol = await itemsHasCreatedByColumn(db);
      const fromSql = hasCreatorCol
        ? 'items i LEFT JOIN users icu ON i.created_by = icu.user_id'
        : 'items i';
      const selectSql = hasCreatorCol
        ? 'i.*, icu.username AS item_created_by_name'
        : 'i.*';
      let query = `SELECT ${selectSql} FROM ${fromSql}`;
      let params = [];
      let conditions = [];
  
      const branchScopedRoles = new Set([
        'admin_warehouse',
        'stockist',
        'cs',
        'kasir',
        'admin_toko',
        'admin_workshop',
      ]);
      let effectiveBranchId =
        branch_id != null ? String(branch_id).trim() : '';
  
      if (branchScopedRoles.has(roleNorm)) {
        const scope = await assertUserCanAccessBranchForOrders(
          req,
          effectiveBranchId || req.user?.branch_id
        );
        if (!scope.ok) {
          return res.status(scope.status).json(scope.body);
        }
        effectiveBranchId = String(scope.branchId);
      }
  
      if (effectiveBranchId) {
        conditions.push(`i.branch_id = $${params.length + 1}`);
        params.push(effectiveBranchId);
      } else if (branch_id) {
        conditions.push(`i.branch_id = $${params.length + 1}`);
        params.push(branch_id);
      }
  
      if (item_code) {
        // Backward compatible: DB schema uses kode_produk
        conditions.push(`(i.kode_produk = $${params.length + 1})`);
        params.push(item_code);
      }
  
      const itemsColFlagsList = await getItemsColumnFlags(db);
      if (_stock_type) {
        if (itemsColFlagsList.stockType) {
          conditions.push(`i.stock_type = $${params.length + 1}`);
          params.push(String(_stock_type).trim());
        }
      }
  
      const inStockOnly =
        in_stock_only === 'true' ||
        in_stock_only === '1' ||
        req.query.quantity_gt === '0';
      if (inStockOnly) {
        conditions.push('COALESCE(i.quantity, 0) > 0');
      }
  
      if (status) {
        conditions.push(`i.status = $${params.length + 1}`);
        params.push(status);
      } else if (sellable_only === 'true' || sellable_only === '1') {
        // Stok yang boleh dipakai untuk penjualan etalase (exclude buyback, service, custom, sold, …)
        conditions.push(
          `LOWER(TRIM(COALESCE(i.status, ''))) IN ('ready', 'available', 'reserved')`
        );
      }
  
      if (is_quick_registered !== undefined) {
        conditions.push(`i.is_quick_registered = $${params.length + 1}`);
        params.push(is_quick_registered === 'true');
      }
  
      if (search) {
        conditions.push(
          `(CAST(i.item_id AS TEXT) ILIKE $${params.length + 1} OR i.kode_produk ILIKE $${params.length + 1} OR i.name ILIKE $${params.length + 1})`
        );
        params.push(`%${search}%`);
      }
  
      const jwtUserId = parseInt(
        String(req.user?.user_id ?? req.user?.id ?? '').trim(),
        10
      );
      const mineOnly =
        mine === 'true' || mine === '1' || mine === true;
      const createdByFilter = parseInt(String(created_by ?? '').trim(), 10);
      const canFilterAnyUser = ['superadmin', 'manajer', 'owner'].includes(roleNorm);
  
      if (mineOnly) {
        if (!hasCreatorCol) {
          return res.status(503).json({
            error:
              'Kolom items.created_by belum tersedia. Jalankan migrasi database terbaru.',
          });
        }
        if (!Number.isFinite(jwtUserId) || jwtUserId <= 0) {
          return res.status(401).json({
            error: 'User login tidak dikenali untuk filter laporan input',
          });
        }
        conditions.push(`i.created_by = $${params.length + 1}`);
        params.push(jwtUserId);
      } else if (hasCreatorCol) {
        if (Number.isFinite(createdByFilter) && createdByFilter > 0) {
          if (!canFilterAnyUser && jwtUserId !== createdByFilter) {
            return res.status(403).json({
              error: 'Tidak boleh melihat input stok pengguna lain',
            });
          }
          conditions.push(`i.created_by = $${params.length + 1}`);
          params.push(createdByFilter);
        }
      }
  
      const startDateTrim =
        start_date != null ? String(start_date).trim() : '';
      const endDateTrim = end_date != null ? String(end_date).trim() : '';
      if (startDateTrim) {
        conditions.push(`DATE(i.created_at) >= $${params.length + 1}`);
        params.push(startDateTrim);
      }
      if (endDateTrim) {
        conditions.push(`DATE(i.created_at) <= $${params.length + 1}`);
        params.push(endDateTrim);
      }
  
      const sourceTrim = source != null ? String(source).trim() : '';
      if (sourceTrim) {
        conditions.push(`i.source = $${params.length + 1}`);
        params.push(sourceTrim);
      }
  
      if (conditions.length > 0) {
        query += ' WHERE ' + conditions.join(' AND ');
      }
  
      query += ' ORDER BY i.created_at DESC';

      const effectiveLimit = parseQueryLimit(limit, {
        defaultLimit: 500,
        maxLimit: 2000,
      });
      query += ` LIMIT $${params.length + 1}`;
      params.push(effectiveLimit);

      const result = await db.query(query, params);
      res.status(200).json(result.rows);
    } catch (error) {
      console.error('Error fetching items:', error);
      res.status(500).json({ error: 'Internal server error' });
    }
  });
  
  // Riwayat perubahan status item (dari tabel stock_history, untuk pelengkap mutasi fisik).
  app.get('/items/:id/status-history', async (req, res) => {
    try {
      const id = parseInt(String(req.params.id ?? '').trim(), 10);
      if (!Number.isFinite(id) || id <= 0) {
        return res.status(400).json({ error: 'Invalid item id' });
      }
      const result = await db.query(
        `
          SELECT
            sh.history_id,
            sh.item_id,
            sh.old_status,
            sh.new_status,
            sh.notes,
            sh.created_at,
            sh.changed_by,
            u.username AS changed_by_name
          FROM stock_history sh
          LEFT JOIN users u ON sh.changed_by = u.user_id
          WHERE sh.item_id = $1
          ORDER BY sh.created_at DESC NULLS LAST, sh.history_id DESC
          LIMIT 200
        `,
        [id]
      );
      return res.status(200).json(result.rows);
    } catch (error) {
      console.error('Error fetching item status history:', error);
      return res.status(500).json({ error: 'Internal server error' });
    }
  });
  
  app.post('/items', async (req, res) => {
    try {
      const {
        name,
        quantity = 1,
        weight,
        material,
        purity,
        kategori,
        jenis,
        tipe,
        status,
        branch_id,
        source = 'manual',
        metadata,
        // Legacy support
        kode_produk,
        // Accept newer clients sending item_code
        item_code,
      } = req.body;
  
      // Handle legacy kode_produk field
      const final_item_code = item_code || kode_produk;
  
      if (!branch_id || !name || !final_item_code || !status || weight == null) {
        return res.status(400).json({
          error:
            'branch_id, name, item_code/kode_produk, status, dan weight wajib diisi',
        });
      }
      if (!material || !purity) {
        return res.status(400).json({
          error: 'material dan purity wajib diisi',
        });
      }
  
      const creatorId = parseInt(String(req.user?.user_id ?? req.user?.id ?? ''), 10);
      const creatorOk = Number.isFinite(creatorId) && creatorId > 0;
      const hasCb = await itemsHasCreatedByColumn(db);
      const qtyParsed = parseInt(String(quantity), 10);
      const qtyForMutation = Number.isFinite(qtyParsed) && qtyParsed > 0 ? qtyParsed : 1;
  
      const client = await db.getClient();
      let result;
      try {
        await client.query('BEGIN');
        if (hasCb) {
          result = await client.query(
            `INSERT INTO items (
              branch_id, kode_produk, kategori, jenis, tipe, name, material, purity, weight, quantity,
              status, source, metadata, created_by, created_at, updated_at
            ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, NOW(), NOW())
            RETURNING *`,
            [
              branch_id,
              final_item_code,
              kategori,
              jenis,
              tipe,
              name,
              material,
              purity,
              weight,
              quantity,
              status,
              source,
              metadata,
              creatorOk ? creatorId : null,
            ]
          );
        } else {
          result = await client.query(
            `INSERT INTO items (
              branch_id, kode_produk, kategori, jenis, tipe, name, material, purity, weight, quantity,
              status, source, metadata, created_at, updated_at
            ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, NOW(), NOW())
            RETURNING *`,
            [
              branch_id,
              final_item_code,
              kategori,
              jenis,
              tipe,
              name,
              material,
              purity,
              weight,
              quantity,
              status,
              source,
              metadata,
            ]
          );
        }
  
        const row = result.rows[0];
        let metaForNotes = metadata;
        if (typeof metaForNotes === 'string') {
          try {
            metaForNotes = JSON.parse(metaForNotes);
          } catch {
            metaForNotes = {};
          }
        }
        if (!metaForNotes || typeof metaForNotes !== 'object') {
          metaForNotes = {};
        }
        const srcNorm = String(source ?? '').trim();
        let mutationNotes = 'Pembuatan / input stok baru';
        if (srcNorm === 'supplier_receipt') {
          const sup = String(metaForNotes.supplier ?? '').trim() || '—';
          const inv = String(metaForNotes.invoice_number ?? '').trim();
          mutationNotes = inv
            ? `Terima dari supplier: ${sup} (Inv: ${inv})`
            : `Terima dari supplier: ${sup}`;
        }
        await client.query(
          `
            INSERT INTO stock_mutations (
              item_id, branch_id, type, quantity, previous_stock, current_stock,
              notes, reference_id, reference_type, created_by
            )
            VALUES ($1, $2, 'in', $3, 0, $3, $4, NULL, 'item_create', $5)
          `,
          [
            row.item_id,
            branch_id,
            qtyForMutation,
            mutationNotes,
            creatorOk ? creatorId : null,
          ]
        );
  
        await client.query('COMMIT');
        res.status(201).json(row);
      } catch (txErr) {
        await client.query('ROLLBACK');
        throw txErr;
      } finally {
        client.release();
      }
    } catch (error) {
      console.error('Error creating item:', error);
      // Provide safer, actionable errors to the client
      // Common PG codes:
      // - 23505 unique_violation
      // - 23502 not_null_violation
      // - 23503 foreign_key_violation
      // - 22P02 invalid_text_representation
      const pgCode = error?.code;
      const detail = error?.detail || null;
      const message = error?.message || 'Unknown error';
  
      if (pgCode === '23505') {
        return res.status(400).json({
          error: 'Duplicate item_code/kode_produk',
          detail,
          code: pgCode,
        });
      }
  
      if (pgCode === '23502' || pgCode === '23503' || pgCode === '22P02') {
        return res.status(400).json({
          error: 'Invalid item payload',
          detail,
          code: pgCode,
        });
      }
  
      return res.status(500).json({
        error: 'Internal server error',
        detail,
        code: pgCode || null,
        message: process.env.NODE_ENV === 'production' ? undefined : message,
      });
    }
  });
  
  app.put('/items/:id', async (req, res) => {
    try {
      const id = parseInt(req.params.id, 10);
      if (!Number.isFinite(id) || id <= 0) {
        return res.status(400).json({ error: 'Invalid item id' });
      }
      const {
        name,
        weight,
        material,
        purity,
        kategori,
        jenis,
        tipe,
        status,
        branch_id,
        source,
        metadata,
        // Legacy support
        kode_produk,
        // Accept newer clients sending item_code
        item_code,
      } = req.body;
  
      // Handle legacy kode_produk field
      const final_item_code = item_code || kode_produk;
  
      if (!branch_id || !name || !final_item_code || !status || weight == null) {
        return res.status(400).json({
          error:
            'branch_id, name, item_code/kode_produk, status, dan weight wajib diisi',
        });
      }
      if (!material || !purity) {
        return res.status(400).json({
          error: 'material dan purity wajib diisi',
        });
      }
  
      const newStatusStr = String(status);
      const editorId = parseInt(
        String(req.user?.user_id ?? req.user?.id ?? ''),
        10
      );
      const editorOk = Number.isFinite(editorId) && editorId > 0;
  
      const client = await db.getClient();
      try {
        await client.query('BEGIN');
  
        const prevRes = await client.query(
          `SELECT status FROM items WHERE item_id = $1 FOR UPDATE`,
          [id]
        );
        if (prevRes.rows.length === 0) {
          await client.query('ROLLBACK');
          return res.status(404).json({ error: 'Item not found' });
        }
        const oldStatus = String(prevRes.rows[0].status ?? '');
  
        const result = await client.query(
          `UPDATE items SET
          branch_id = $1,
          kode_produk = $2,
          kategori = $3,
          jenis = $4,
          tipe = $5,
          name = $6,
          material = $7,
          purity = $8,
          weight = $9,
          status = $10,
          source = $11,
          metadata = $12,
          updated_at = NOW()
        WHERE item_id = $13
        RETURNING *`,
          [
            branch_id,
            final_item_code,
            kategori,
            jenis,
            tipe,
            name,
            material,
            purity,
            weight,
            status,
            source,
            metadata,
            id,
          ]
        );
  
        if (result.rows.length === 0) {
          await client.query('ROLLBACK');
          return res.status(404).json({ error: 'Item not found' });
        }
  
        if (oldStatus !== newStatusStr) {
          await client.query(
            `INSERT INTO stock_history (item_id, old_status, new_status, changed_by, notes)
             VALUES ($1, $2, $3, $4, $5)`,
            [
              id,
              oldStatus,
              newStatusStr,
              editorOk ? editorId : null,
              'Perubahan status / edit data item (toko atau admin)',
            ]
          );
        }
  
        await client.query('COMMIT');

        await writeAuditLog(db, req, {
          action: 'item.update',
          entityType: 'item',
          entityId: id,
          branchId: branch_id,
          payload: {
            item_code: final_item_code,
            old_status: oldStatus,
            new_status: newStatusStr,
            status_changed: oldStatus !== newStatusStr,
          },
        });

        return res.json(result.rows[0]);
      } catch (txErr) {
        await client.query('ROLLBACK');
        throw txErr;
      } finally {
        client.release();
      }
    } catch (error) {
      console.error('Error updating item:', error);
      res.status(500).json({ error: 'Internal server error' });
    }
  });
  
  // Restock: increment item quantity safely
  app.post('/items/:id/restock', async (req, res) => {
    try {
      const id = parseInt(req.params.id, 10);
      const { delta_quantity, branch_id } = req.body || {};
  
      const delta = parseInt(delta_quantity, 10);
      if (!Number.isFinite(delta) || delta <= 0) {
        return res
          .status(400)
          .json({ error: 'delta_quantity wajib diisi dan harus > 0' });
      }
  
      const creatorId = parseInt(String(req.user?.user_id ?? req.user?.id ?? ''), 10);
      const creatorOk = Number.isFinite(creatorId) && creatorId > 0;
  
      const client = await db.getClient();
      try {
        await client.query('BEGIN');
  
        const selParams = [id];
        let selSql = `SELECT item_id, branch_id, COALESCE(quantity, 0) AS quantity FROM items WHERE item_id = $1`;
        if (branch_id != null && String(branch_id).trim() !== '') {
          selSql += ` AND branch_id = $2`;
          selParams.push(branch_id);
        }
        const prevRes = await client.query(selSql, selParams);
        if (prevRes.rows.length === 0) {
          await client.query('ROLLBACK');
          return res.status(404).json({ error: 'Item not found' });
        }
        const prevQty = parseInt(prevRes.rows[0].quantity, 10) || 0;
        const itemBranchId = prevRes.rows[0].branch_id;
  
        const updParams = [delta, id];
        let updSql = `
        UPDATE items
        SET quantity = COALESCE(quantity, 0) + $1,
            status = CASE
              WHEN (COALESCE(quantity, 0) + $1) > 0
                AND LOWER(TRIM(COALESCE(status, ''))) = 'missing'
              THEN 'ready'
              ELSE status
            END,
            updated_at = NOW()
        WHERE item_id = $2
      `;
        if (branch_id != null && String(branch_id).trim() !== '') {
          updSql += ` AND branch_id = $3`;
          updParams.push(branch_id);
        }
        updSql += ` RETURNING *`;
        const result = await client.query(updSql, updParams);
        if (result.rows.length === 0) {
          await client.query('ROLLBACK');
          return res.status(404).json({ error: 'Item not found' });
        }
        const row = result.rows[0];
        const nextQty = parseInt(row.quantity, 10) || 0;
  
        await client.query(
          `
            INSERT INTO stock_mutations (
              item_id, branch_id, type, quantity, previous_stock, current_stock,
              notes, reference_id, reference_type, created_by
            )
            VALUES ($1, $2, 'in', $3, $4, $5, $6, NULL, 'restock', $7)
          `,
          [
            id,
            itemBranchId,
            delta,
            prevQty,
            nextQty,
            'Restok penambahan quantity',
            creatorOk ? creatorId : null,
          ]
        );
  
        await client.query('COMMIT');

        await writeAuditLog(db, req, {
          action: 'item.restock',
          entityType: 'item',
          entityId: id,
          branchId: itemBranchId,
          payload: {
            delta_quantity: delta,
            previous_quantity: prevQty,
            current_quantity: nextQty,
          },
        });

        return res.status(200).json(row);
      } catch (txErr) {
        await client.query('ROLLBACK');
        throw txErr;
      } finally {
        client.release();
      }
    } catch (error) {
      console.error('Error restocking item:', error);
      return res.status(500).json({ error: 'Internal server error' });
    }
  });
  
  // Stok opname: sesuaikan quantity sistem dengan hasil hitung fisik
  // Path di bawah /items agar ter-cover middleware authRequired di server.js
  app.post('/items/stock-opname', async (req, res) => {
    try {
      if (req.user?.user_id == null && req.user?.id == null) {
        return res.status(401).json({ error: 'Unauthorized' });
      }

      const roleNorm = String(req.user?.role ?? '')
        .trim()
        .toLowerCase();
      const opnameRoles = new Set([
        'admin_toko',
        'admin_warehouse',
        'admin_workshop',
        'manajer',
        'superadmin',
        'owner',
        'stockist',
      ]);
      if (!opnameRoles.has(roleNorm)) {
        return res.status(403).json({
          error: 'Role tidak diizinkan melakukan stok opname',
          details: roleNorm.isEmpty
              ? 'Role tidak ditemukan di token. Coba logout/login atau ganti cabang/role.'
              : `Role saat ini: ${roleNorm}`,
        });
      }

      const { branch_id: branchIdRaw, lines, notes: sessionNotes } = req.body || {};
      const scope = await assertUserCanAccessBranchForOrders(req, branchIdRaw);
      if (!scope.ok) {
        return res.status(scope.status).json(scope.body);
      }
      const branchId = scope.branchId;

      if (!Array.isArray(lines) || lines.length === 0) {
        return res.status(400).json({ error: 'lines wajib berisi minimal satu item' });
      }

      const creatorId = parseInt(String(req.user?.user_id ?? req.user?.id ?? ''), 10);
      const creatorOk = Number.isFinite(creatorId) && creatorId > 0;
      const sessionNote =
        sessionNotes != null ? String(sessionNotes).trim() : '';

      const client = await db.getClient();
      const applied = [];
      const skipped = [];

      try {
        await client.query('BEGIN');

        for (const rawLine of lines) {
          const itemId = parseInt(String(rawLine?.item_id ?? ''), 10);
          const counted = parseInt(String(rawLine?.counted_quantity ?? ''), 10);
          const lineNote =
            rawLine?.notes != null ? String(rawLine.notes).trim() : '';

          if (!Number.isFinite(itemId) || itemId <= 0) {
            await client.query('ROLLBACK');
            return res.status(400).json({ error: 'item_id tidak valid pada lines' });
          }
          if (!Number.isFinite(counted) || counted < 0) {
            await client.query('ROLLBACK');
            return res
              .status(400)
              .json({ error: `counted_quantity harus bilangan bulat >= 0 (item ${itemId})` });
          }

          const selRes = await client.query(
            `
              SELECT item_id, branch_id, COALESCE(quantity, 0) AS quantity, name
              FROM items
              WHERE item_id = $1 AND branch_id = $2
              FOR UPDATE
            `,
            [itemId, branchId]
          );
          if (selRes.rows.length === 0) {
            await client.query('ROLLBACK');
            return res.status(404).json({ error: `Item ${itemId} tidak ditemukan di cabang ini` });
          }

          const row = selRes.rows[0];
          const prevQty = parseInt(row.quantity, 10) || 0;
          const isVerify =
            rawLine?.verified === true ||
            String(rawLine?.verified ?? '').trim().toLowerCase() === 'true';

          if (prevQty === counted) {
            if (isVerify) {
              const verifyNoteParts = [
                `Stok opname: terverifikasi ada (qty ${prevQty} tidak berubah)`,
              ];
              if (lineNote) verifyNoteParts.push(lineNote);
              if (sessionNote) verifyNoteParts.push(sessionNote);

              await client.query(
                `
                  INSERT INTO stock_mutations (
                    item_id, branch_id, type, quantity, previous_stock, current_stock,
                    notes, reference_id, reference_type, created_by
                  )
                  VALUES ($1, $2, 'adjustment', 0, $3, $3, $4, NULL, 'opname', $5)
                `,
                [
                  itemId,
                  branchId,
                  prevQty,
                  verifyNoteParts.join(' · '),
                  creatorOk ? creatorId : null,
                ]
              );

              applied.push({
                item_id: itemId,
                name: row.name,
                action: 'verified',
                previous_quantity: prevQty,
                counted_quantity: counted,
                delta: 0,
              });
            } else {
              skipped.push({ item_id: itemId, reason: 'unchanged' });
            }
            continue;
          }

          const delta = counted - prevQty;
          const updRes = await client.query(
            `
              UPDATE items
              SET quantity = $1,
                  status = CASE
                    WHEN $1 <= 0 THEN 'missing'
                    ELSE status
                  END,
                  updated_at = NOW()
              WHERE item_id = $2 AND branch_id = $3
              RETURNING item_id, quantity, name, status
            `,
            [counted, itemId, branchId]
          );
          const updated = updRes.rows[0];
          const nextQty = parseInt(updated.quantity, 10) || 0;

          const noteParts = [
            `Stok opname: ${prevQty} → ${counted} (selisih ${delta >= 0 ? '+' : ''}${delta}) · status missing`,
          ];
          if (lineNote) noteParts.push(lineNote);
          if (sessionNote) noteParts.push(sessionNote);

          await client.query(
            `
              INSERT INTO stock_mutations (
                item_id, branch_id, type, quantity, previous_stock, current_stock,
                notes, reference_id, reference_type, created_by
              )
              VALUES ($1, $2, 'adjustment', $3, $4, $5, $6, NULL, 'opname', $7)
            `,
            [
              itemId,
              branchId,
              delta,
              prevQty,
              nextQty,
              noteParts.join(' · '),
              creatorOk ? creatorId : null,
            ]
          );

          applied.push({
            item_id: itemId,
            name: updated.name,
            action: 'missing',
            previous_quantity: prevQty,
            counted_quantity: counted,
            delta,
          });
        }

        await client.query('COMMIT');

        await writeAuditLog(db, req, {
          action: 'stock.opname',
          entityType: 'branch',
          entityId: branchId,
          branchId,
          payload: {
            applied_count: applied.length,
            skipped_count: skipped.length,
            applied,
            skipped,
            session_notes: sessionNote || null,
          },
        });

        return res.status(200).json({
          branch_id: branchId,
          applied_count: applied.length,
          skipped_count: skipped.length,
          applied,
          skipped,
        });
      } catch (txErr) {
        await client.query('ROLLBACK');
        throw txErr;
      } finally {
        client.release();
      }
    } catch (error) {
      console.error('Error stock opname:', error);
      return res.status(500).json({ error: 'Internal server error' });
    }
  });
}

module.exports = { registerItemsRoutes };

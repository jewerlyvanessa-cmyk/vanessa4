'use strict';

const {
  parseKodeProdukFromTransferItemLabel,
  extractKurirFromTransferNotes,
  extractTransferSourceTypeFromNotes,
} = require('../lib/transfer_helpers');

/** GET/POST/PUT /transfers */
function registerTransfersRoutes(app, deps) {
  const { db } = deps;

app.get('/transfers', async (req, res) => {
  try {
    const { branch_id, status, type, purpose } = req.query;

    // Backward-compatible: columns may not exist yet.
    async function hasTransfersColumn(columnName) {
      try {
        const r = await db.query(
          `
            SELECT 1
            FROM information_schema.columns
            WHERE table_schema = 'public'
              AND table_name = 'transfers'
              AND column_name = $1
            LIMIT 1
          `,
          [columnName]
        );
        return r.rows.length > 0;
      } catch (_) {
        return false;
      }
    }

    const [hasSourceTypeCol, hasCourierCol] = await Promise.all([
      hasTransfersColumn('source_type'),
      hasTransfersColumn('courier'),
    ]);

    let query = `
      SELECT
        t.transfer_id,
        t.from_branch_id,
        t.to_branch_id,
        t.item_name,
        t.quantity,
        ${hasSourceTypeCol ? 't.source_type' : "'stok'"} as source_type,
        ${hasCourierCol ? 't.courier' : 'NULL'} as courier,
        t.notes,
        t.order_id,
        t.created_by,
        t.approved_by,
        t.status,
        t.created_at,
        t.updated_at,
        fb.name as from_branch_name,
        tb.name as to_branch_name,
        u.username as created_by_name,
        uap.username as approved_by_name
      FROM transfers t
      LEFT JOIN branches fb ON t.from_branch_id = fb.branch_id
      LEFT JOIN branches tb ON t.to_branch_id = tb.branch_id
      LEFT JOIN users u ON t.created_by = u.user_id
      LEFT JOIN users uap ON t.approved_by = uap.user_id
      WHERE 1=1
    `;

    const params = [];
    let paramIndex = 1;

    if (branch_id) {
      query += ` AND (t.from_branch_id = $${paramIndex} OR t.to_branch_id = $${paramIndex})`;
      params.push(branch_id);
      paramIndex++;
    }

    if (status) {
      query += ` AND t.status = $${paramIndex}`;
      params.push(status);
      paramIndex++;
    }

    if (type) {
      if (type === 'incoming') {
        query += ` AND t.to_branch_id = $${paramIndex}`;
        params.push(branch_id);
        paramIndex++;
      } else if (type === 'outgoing') {
        query += ` AND t.from_branch_id = $${paramIndex}`;
        params.push(branch_id);
        paramIndex++;
      }
    }

    // Store-initiated "request stock from warehouse" rows use this marker in `notes`.
    if (String(purpose || '').trim().toLowerCase() === 'stock_request') {
      query += ` AND COALESCE(t.notes, '') ILIKE $${paramIndex}`;
      params.push('%[PERMINTAAN_STOK]%');
      paramIndex++;
    }

    query += ` ORDER BY t.created_at DESC`;

    const result = await db.query(query, params);
    // Prevent "Do not know how to serialize a BigInt" when sending JSON
    const processedRows = result.rows.map(row => {
      const rawC = row.courier;
      let displayCourier = rawC;
      if (displayCourier == null || (typeof displayCourier === 'string' && displayCourier.trim() === '')) {
        const fromNotes = extractKurirFromTransferNotes(row.notes);
        if (fromNotes) displayCourier = fromNotes;
      }
      return {
        ...row,
        courier: displayCourier,
        transfer_id: row.transfer_id?.toString?.() ?? row.transfer_id,
        from_branch_id: row.from_branch_id?.toString?.() ?? row.from_branch_id,
        to_branch_id: row.to_branch_id?.toString?.() ?? row.to_branch_id,
        order_id: row.order_id?.toString?.() ?? row.order_id,
        created_by: row.created_by?.toString?.() ?? row.created_by,
        approved_by: row.approved_by?.toString?.() ?? row.approved_by,
        quantity: row.quantity == null ? null : parseInt(row.quantity, 10),
      };
    });

    res.status(200).json(processedRows);
  } catch (error) {
    console.error('Error fetching transfers:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// Endpoint untuk membuat transfer barang baru
app.post('/transfers', async (req, res) => {
  try {
    const {
      from_branch_id,
      to_branch_id,
      item_name,
      quantity,
      notes: bodyNotes,
      order_id,
      created_by,
      source_type,
      courier: bodyCourier,
    } = req.body;

    if (!from_branch_id || !to_branch_id || !item_name || !quantity) {
      return res.status(400).json({ error: 'from_branch_id, to_branch_id, item_name, and quantity are required' });
    }

    const sourceTypeNormalized = (source_type ?? '').toString().trim().toLowerCase();
    const normalizedSourceType = ['stok', 'buyback', 'service', 'custom'].includes(sourceTypeNormalized)
      ? sourceTypeNormalized
      : 'stok';

    async function hasTransfersColumn(columnName) {
      try {
        const r = await db.query(
          `
            SELECT 1
            FROM information_schema.columns
            WHERE table_schema = 'public'
              AND table_name = 'transfers'
              AND column_name = $1
            LIMIT 1
          `,
          [columnName]
        );
        return r.rows.length > 0;
      } catch (_) {
        return false;
      }
    }

    const [hasSourceTypeCol, hasCourierCol] = await Promise.all([
      hasTransfersColumn('source_type'),
      hasTransfersColumn('courier'),
    ]);

    const trimmedCourier =
      bodyCourier == null || String(bodyCourier).trim() === ''
        ? ''
        : String(bodyCourier).trim();
    // No `courier` column yet: persist kurir in notes (common when source_type migration ran but courier did not)
    let notes = bodyNotes;
    if (!hasCourierCol && trimmedCourier) {
      const n = bodyNotes == null || String(bodyNotes).trim() === '' ? '' : String(bodyNotes);
      notes = n ? `Kurir: ${trimmedCourier}\n${n}` : `Kurir: ${trimmedCourier}`;
    }

    let insertQuery;
    let params;

    if (hasSourceTypeCol && hasCourierCol) {
      insertQuery = `
        INSERT INTO transfers (
          from_branch_id, to_branch_id, item_name, quantity,
          source_type, courier, notes, order_id, created_by, status
        )
        VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, 'pending')
        RETURNING *
      `;
      params = [
        from_branch_id,
        to_branch_id,
        item_name,
        quantity,
        normalizedSourceType,
        trimmedCourier || null,
        notes,
        order_id,
        created_by,
      ];
    } else if (hasSourceTypeCol && !hasCourierCol) {
      insertQuery = `
        INSERT INTO transfers (
          from_branch_id, to_branch_id, item_name, quantity,
          source_type, notes, order_id, created_by, status
        )
        VALUES ($1, $2, $3, $4, $5, $6, $7, $8, 'pending')
        RETURNING *
      `;
      params = [
        from_branch_id,
        to_branch_id,
        item_name,
        quantity,
        normalizedSourceType,
        notes,
        order_id,
        created_by,
      ];
    } else if (!hasSourceTypeCol && hasCourierCol) {
      insertQuery = `
        INSERT INTO transfers (
          from_branch_id, to_branch_id, item_name, quantity,
          courier, notes, order_id, created_by, status
        )
        VALUES ($1, $2, $3, $4, $5, $6, $7, $8, 'pending')
        RETURNING *
      `;
      params = [
        from_branch_id,
        to_branch_id,
        item_name,
        quantity,
        trimmedCourier || null,
        notes,
        order_id,
        created_by,
      ];
    } else {
      insertQuery = `
        INSERT INTO transfers (
          from_branch_id, to_branch_id, item_name, quantity,
          notes, order_id, created_by, status
        )
        VALUES ($1, $2, $3, $4, $5, $6, $7, 'pending')
        RETURNING *
      `;
      params = [
        from_branch_id,
        to_branch_id,
        item_name,
        quantity,
        notes,
        order_id,
        created_by,
      ];
    }

    let result;
    try {
      result = await db.query(insertQuery, params);
    } catch (err) {
      const isSourceTypeConstraintError =
        err?.code === '23514' &&
        String(err?.constraint ?? '') === 'transfers_source_type_check';
      if (!isSourceTypeConstraintError || !hasSourceTypeCol) {
        throw err;
      }

      // Backward compatibility: some DBs still enforce older source_type values.
      // Fallback to "stok" so transfer still succeeds, while preserving original source in notes.
      const fallbackParams = [...params];
      const sourceTypeParamIndex = 4; // source_type is always the 5th bound param when present
      if (fallbackParams[sourceTypeParamIndex] !== 'stok') {
        const notesParamIndex = hasCourierCol ? 6 : 5;
        const oldNotes =
          fallbackParams[notesParamIndex] == null
            ? ''
            : String(fallbackParams[notesParamIndex]);
        const fallbackPrefix = `Sumber asli: ${fallbackParams[sourceTypeParamIndex]}`;
        fallbackParams[notesParamIndex] = oldNotes.trim() === ''
          ? fallbackPrefix
          : `${fallbackPrefix}\n${oldNotes}`;
        fallbackParams[sourceTypeParamIndex] = 'stok';
      }
      result = await db.query(insertQuery, fallbackParams);
    }

    res.status(201).json(result.rows[0]);
  } catch (error) {
    console.error('Error creating transfer:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// Endpoint untuk update status transfer
app.put('/transfers/:id', async (req, res) => {
  try {
    const { id } = req.params;
    const { status, approved_by } = req.body;

    if (!status) {
      return res.status(400).json({ error: 'status is required' });
    }

    const approverUserId =
      approved_by ??
      (req.user?.user_id ? parseInt(req.user.user_id, 10) : null);

    const client = await db.getClient();
    try {
      await client.query('BEGIN');

      const transferRes = await client.query(
        `
          SELECT *
          FROM transfers
          WHERE transfer_id = $1
          FOR UPDATE
        `,
        [id]
      );

      if (transferRes.rows.length === 0) {
        await client.query('ROLLBACK');
        return res.status(404).json({ error: 'Transfer not found' });
      }

      const transfer = transferRes.rows[0];
      const prevStatus = transfer.status;

      // Update transfer status first (idempotent friendly)
      const updateRes = await client.query(
        `
          UPDATE transfers
          SET status = $1, approved_by = $2, updated_at = CURRENT_TIMESTAMP
          WHERE transfer_id = $3
          RETURNING *
        `,
        [status, approverUserId, id]
      );

      // Apply stock movement only once when transitioning into "completed"
      if (status === 'completed' && prevStatus !== 'completed') {
        const fromBranchId = transfer.from_branch_id;
        const toBranchId = transfer.to_branch_id;
        const qty = parseInt(transfer.quantity, 10);
        const itemName = String(transfer.item_name ?? '').trim();
        const sourceTypeFromColumn =
          (transfer.source_type ?? '').toString().trim().toLowerCase();
        const sourceTypeFromNotes = extractTransferSourceTypeFromNotes(transfer.notes);
        const sourceTypeRaw =
          sourceTypeFromColumn === 'stok' && sourceTypeFromNotes
            ? sourceTypeFromNotes
            : (sourceTypeFromColumn || sourceTypeFromNotes || 'stok');
        const transferSourceType = ['stok', 'buyback', 'service', 'custom'].includes(sourceTypeRaw)
          ? sourceTypeRaw
          : 'stok';
        const sourceStatusCandidatesByType = {
          stok: ['ready'],
          buyback: ['buyback'],
          service: ['on-service'],
          custom: ['on-custom'],
        };
        const sourceStatusCandidates =
          sourceStatusCandidatesByType[transferSourceType] || [];
        const destinationStatusByType = {
          stok: 'ready',
          buyback: 'buyback',
          service: 'on-service',
          custom: 'on-custom',
        };
        const destinationStatus =
          destinationStatusByType[transferSourceType] || 'ready';

        // Find source item: exact `name` first, then "KODE - label" by kode_produk (see parseKodeProdukFromTransferItemLabel).
        let sourceItemRes;
        if (sourceStatusCandidates.length > 0) {
          sourceItemRes = await client.query(
            `
              SELECT *
              FROM items
              WHERE branch_id = $1
                AND name = $2
                AND status = ANY($3::text[])
              ORDER BY updated_at DESC
              LIMIT 1
              FOR UPDATE
            `,
            [fromBranchId, itemName, sourceStatusCandidates]
          );
        } else {
          sourceItemRes = await client.query(
            `
              SELECT *
              FROM items
              WHERE branch_id = $1 AND name = $2
              ORDER BY updated_at DESC
              LIMIT 1
              FOR UPDATE
            `,
            [fromBranchId, itemName]
          );
        }

        if (sourceItemRes.rows.length === 0) {
          const kode = parseKodeProdukFromTransferItemLabel(itemName);
          if (kode) {
            if (sourceStatusCandidates.length > 0) {
              sourceItemRes = await client.query(
                `
                  SELECT *
                  FROM items
                  WHERE branch_id = $1
                    AND kode_produk = $2
                    AND status = ANY($3::text[])
                  ORDER BY updated_at DESC
                  LIMIT 1
                  FOR UPDATE
                `,
                [fromBranchId, kode, sourceStatusCandidates]
              );
            } else {
              sourceItemRes = await client.query(
                `
                  SELECT *
                  FROM items
                  WHERE branch_id = $1 AND kode_produk = $2
                  ORDER BY updated_at DESC
                  LIMIT 1
                  FOR UPDATE
                `,
                [fromBranchId, kode]
              );
            }
          }
        }

        // Fallback for legacy/dirty rows: retry without status restriction
        if (sourceItemRes.rows.length === 0 && sourceStatusCandidates.length > 0) {
          sourceItemRes = await client.query(
            `
              SELECT *
              FROM items
              WHERE branch_id = $1 AND name = $2
              ORDER BY updated_at DESC
              LIMIT 1
              FOR UPDATE
            `,
            [fromBranchId, itemName]
          );
          if (sourceItemRes.rows.length === 0) {
            const kode = parseKodeProdukFromTransferItemLabel(itemName);
            if (kode) {
              sourceItemRes = await client.query(
                `
                  SELECT *
                  FROM items
                  WHERE branch_id = $1 AND kode_produk = $2
                  ORDER BY updated_at DESC
                  LIMIT 1
                  FOR UPDATE
                `,
                [fromBranchId, kode]
              );
            }
          }
        }

        if (sourceItemRes.rows.length === 0) {
          throw new Error(
            `Source item not found in branch ${fromBranchId} for name "${itemName}"`
          );
        }

        const sourceItem = sourceItemRes.rows[0];
        const sourcePrevStock = parseInt(sourceItem.quantity, 10);
        const sourceNextStock = sourcePrevStock - qty;

        if (sourceNextStock < 0) {
          return res.status(400).json({
            error: 'Insufficient stock in source branch',
            detail: `Stock ${sourcePrevStock} < transfer quantity ${qty}`,
          });
        }

        // Decrease stock in source branch
        await client.query(
          `
            UPDATE items
            SET quantity = $1, updated_at = CURRENT_TIMESTAMP
            WHERE item_id = $2
          `,
          [sourceNextStock, sourceItem.item_id]
        );

        // Upsert destination WITHOUT relying on a unique constraint.
        // Update by (branch_id, kode_produk) to handle potential duplicates.
        let destItemId;
        let destPrevStock;
        let destCurrentStock;

        const preDest = await client.query(
          `
            SELECT item_id, status, quantity
            FROM items
            WHERE branch_id = $1 AND kode_produk = $2
            ORDER BY updated_at DESC
          `,
          [toBranchId, sourceItem.kode_produk]
        );

        const destUpdateRes = await client.query(
          `
            UPDATE items
            SET quantity = quantity + $1,
                status = $4,
                ownership = COALESCE($5, ownership),
                stock_type = COALESCE($6, stock_type),
                updated_at = CURRENT_TIMESTAMP
            WHERE branch_id = $2 AND kode_produk = $3
            RETURNING item_id, quantity
          `,
          [
            qty,
            toBranchId,
            sourceItem.kode_produk,
            destinationStatus,
            sourceItem.ownership ?? null,
            sourceItem.stock_type ?? null,
          ]
        );

        if (destUpdateRes.rows.length > 0) {
          // If duplicates exist, we just pick the first returned row for mutation logging.
          // All matching rows already had status forced to destination status.
          destItemId = destUpdateRes.rows[0].item_id;
          destCurrentStock = parseInt(destUpdateRes.rows[0].quantity, 10);
          destPrevStock = destCurrentStock - qty;

          const destRowCount = destUpdateRes.rows.length;
          const singleUnambiguous =
            preDest.rows.length === 1 &&
            destRowCount === 1 &&
            String(preDest.rows[0].item_id) === String(destItemId);
          if (singleUnambiguous) {
            const oldDestStatus = String(preDest.rows[0].status ?? '');
            if (oldDestStatus !== destinationStatus) {
              await client.query(
                `
                  INSERT INTO stock_history (item_id, old_status, new_status, changed_by, notes)
                  VALUES ($1, $2, $3, $4, $5)
                `,
                [
                  destItemId,
                  oldDestStatus,
                  destinationStatus,
                  approverUserId,
                  `Transfer masuk selesai (#${transfer.transfer_id})`,
                ]
              );
            }
          }
        } else {
          destPrevStock = 0;
          destCurrentStock = qty;

          const destInsertRes = await client.query(
            `
              INSERT INTO items (
                branch_id,
                kode_produk,
                kategori,
                jenis,
                tipe,
                name,
                material,
                purity,
                weight,
                quantity,
                status,
                ownership,
                stock_type,
                source,
                metadata,
                created_at,
                updated_at
              )
              VALUES (
                $1, $2, $3, $4, $5,
                $6, $7, $8, $9,
                $10, $11, $12, $13, $14, $15,
                CURRENT_TIMESTAMP, CURRENT_TIMESTAMP
              )
              RETURNING item_id
            `,
            [
              toBranchId,
              sourceItem.kode_produk,
              sourceItem.kategori,
              sourceItem.jenis,
              sourceItem.tipe,
              sourceItem.name,
              sourceItem.material,
              sourceItem.purity,
              sourceItem.weight,
              qty,
              destinationStatus,
              sourceItem.ownership ?? 'toko',
              sourceItem.stock_type ?? (destinationStatus === 'ready' ? 'inventory' : 'non_inventory'),
              'transfer',
              sourceItem.metadata,
            ]
          );

          destItemId = destInsertRes.rows[0].item_id;
        }

        // Record stock mutation for source (out)
        await client.query(
          `
            INSERT INTO stock_mutations (
              item_id, branch_id, type, quantity, previous_stock, current_stock,
              notes, reference_id, reference_type, created_by
            )
            VALUES ($1, $2, 'transfer', $3, $4, $5, $6, $7, 'transfer', $8)
          `,
          [
            sourceItem.item_id,
            fromBranchId,
            -qty,
            sourcePrevStock,
            sourceNextStock,
            `Transfer keluar ke branch ${toBranchId}`,
            transfer.transfer_id,
            approverUserId,
          ]
        );

        // Record stock mutation for destination (in)
        await client.query(
          `
            INSERT INTO stock_mutations (
              item_id, branch_id, type, quantity, previous_stock, current_stock,
              notes, reference_id, reference_type, created_by
            )
            VALUES ($1, $2, 'transfer', $3, $4, $5, $6, $7, 'transfer', $8)
          `,
          [
            destItemId,
            toBranchId,
            qty,
            destPrevStock,
            destCurrentStock,
            `Transfer masuk dari branch ${fromBranchId}`,
            transfer.transfer_id,
            approverUserId,
          ]
        );
      }

      await client.query('COMMIT');
      res.status(200).json(updateRes.rows[0]);
    } catch (txError) {
      await client.query('ROLLBACK');
      console.error('Error updating transfer (tx):', txError);
      res.status(500).json({ error: 'Internal server error', detail: txError.message });
    } finally {
      client.release();
    }
  } catch (error) {
    console.error('Error updating transfer:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

}

module.exports = { registerTransfersRoutes };

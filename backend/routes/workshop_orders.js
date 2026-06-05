'use strict';

const {
  ordersHasPickupBranchColumn,
  ordersHasMetadataColumn,
  sqlOrdersVisibleAtWorkshopBranch,
  orderVisibleForWorkshopStatusPut,
  sqlWorkshopTukangQueueStatuses,
  sqlWorkshopOrderIsUnassigned,
  sqlWorkshopAntrianVisibleAtBranch,
  ordersHasMetadataColumnLive,
} = require('../lib/orders_workshop_helpers');

const { ADMIN_WORKSHOP_PUT_ALLOWED_STATUSES } = require('./workshop_shared');

function registerWorkshopOrdersRoutes(app, { db, broadcastWorkshop }) {
app.get('/workshop-orders', async (req, res) => {
  try {
    const { branch_id, status, scope: scopeRaw } = req.query;
    const queueModeRaw = String(req.query.queue_mode ?? '')
      .trim()
      .toLowerCase();
    const queueModeAntrian = queueModeRaw === 'antrian';
    const scope = String(scopeRaw ?? 'all')
      .trim()
      .toLowerCase();
    if (!['all', 'cross_branch', 'local'].includes(scope)) {
      return res.status(400).json({ error: 'scope harus all, cross_branch, atau local' });
    }

    if (!branch_id) {
      return res.status(400).json({ error: 'branch_id is required' });
    }

    const hasPickupWo = await ordersHasPickupBranchColumn(db);
    const hasMetaWo = await ordersHasMetadataColumnLive(db);
    const brScopeWo = queueModeAntrian
      ? sqlWorkshopAntrianVisibleAtBranch('o', 1, hasMetaWo)
      : sqlOrdersVisibleAtWorkshopBranch('o', 1, hasPickupWo, hasMetaWo);
    const postWorkshopStatuses = `(
          'done_workshop',
          'ready_for_pickup'
        )`;
    let branchCompareSql = '';
    // Antrian pekerjaan: jangan sempitkan scope (Cabang ini / Cabang lain) — cukup filter cabang workshop.
    if (!queueModeAntrian) {
      if (scope === 'local') {
        if (hasMetaWo) {
          branchCompareSql = `AND (
            o.branch_id::bigint = $1::bigint
            OR (
              COALESCE(NULLIF(BTRIM(o.metadata->>'service_workshop_branch_id'), ''), '') <> ''
              AND (o.metadata->>'service_workshop_branch_id')::bigint = $1::bigint
            )
          )`;
        } else {
          branchCompareSql = 'AND o.branch_id::bigint = $1::bigint';
        }
      } else if (scope === 'cross_branch') {
        branchCompareSql = 'AND o.branch_id::bigint <> $1::bigint';
      }
    }

    let innerWhere = `
      WHERE ${brScopeWo}
        ${branchCompareSql}
        AND o.order_type::text IN ('service', 'custom')
    `;

    let params = [branch_id];
    let conditions = [];
    let orderCompletedView = false;

    if (status && status !== 'all') {
      if (status === 'pending') {
        conditions.push(`o.status::text IN ('sent-to-workshop', 'in_workshop')`);
      } else if (status === 'in_progress') {
        // Sedang dikerjakan tukang: progres aktif + in_workshop yang sudah di-assign.
        if (hasMetaWo) {
          conditions.push(`(
            o.status::text IN ('repairing', 'polishing', 'custom_work')
            OR (
              o.status::text = 'in_workshop'
              AND NOT (${sqlWorkshopOrderIsUnassigned('o', hasMetaWo)})
            )
          )`);
        } else {
          conditions.push(`o.status::text IN ('repairing', 'polishing', 'custom_work', 'in_workshop')`);
        }
      } else if (status === 'completed') {
        orderCompletedView = true;
        conditions.push(`o.status::text IN ${postWorkshopStatuses}`);
      } else {
        conditions.push(`o.status::text = $${params.length + 1}`);
        params.push(status);
      }
    } else {
      // Antrian pekerjaan: hanya order yang sudah disetujui workshop (sent-to-workshop+).
      // Menunggu persetujuan (awaiting_warehouse) hanya di menu «Service dari toko».
      conditions.push(sqlWorkshopTukangQueueStatuses('o'));
    }

    if (conditions.length > 0) {
      innerWhere += ' AND ' + conditions.join(' AND ');
    }

    const unassignedOnlyWoRaw = String(req.query.unassigned_only ?? '')
      .trim()
      .toLowerCase();
    const unassignedOnlyWo =
      queueModeAntrian ||
      unassignedOnlyWoRaw === '1' ||
      unassignedOnlyWoRaw === 'true' ||
      unassignedOnlyWoRaw === 'yes';
    if (unassignedOnlyWo) {
      innerWhere += ` AND (${sqlWorkshopOrderIsUnassigned('o', hasMetaWo)})`;
    }

    res.setHeader('X-Vanessa-Workshop-Orders-Rules', '2026-05-17-antrian-v1');

    const innerOrderBy = orderCompletedView
      ? 'o.order_id, o.updated_at DESC, o.created_at DESC, oi.order_item_id ASC NULLS LAST'
      : 'o.order_id, o.created_at ASC, oi.order_item_id ASC NULLS LAST';

    const technicianJoinSql = hasMetaWo
      ? `
        LEFT JOIN users tu ON (
          (o.metadata->>'assigned_technician_id') ~ '^[0-9]+$'
          AND tu.user_id = (NULLIF(BTRIM(o.metadata->>'assigned_technician_id'), ''))::bigint
        )`
      : '';
    const technicianSelectSql = hasMetaWo ? ', tu.username AS technician_name' : '';

    const query = `
      SELECT * FROM (
        SELECT DISTINCT ON (o.order_id)
          o.order_id,
          o.order_number,
          o.order_type,
          o.status,
          o.created_at,
          o.updated_at,
          c.name AS customer_name,
          c.phone,
          COALESCE(oi.nama_item, i.name) AS item_name,
          COALESCE(oi.qty, 1) AS quantity,
          COALESCE(oi.weight, i.weight, 0) AS weight,
          COALESCE(oi.jenis, i.material) AS material
          ${technicianSelectSql}
        FROM orders o
        LEFT JOIN customers c ON o.customer_id = c.customer_id
        LEFT JOIN order_items oi ON o.order_id = oi.order_id
        LEFT JOIN items i ON oi.item_id = i.item_id
        ${technicianJoinSql}
        ${innerWhere}
        ORDER BY ${innerOrderBy}
      ) AS wo_orders
      ${orderCompletedView
        ? 'ORDER BY wo_orders.updated_at DESC, wo_orders.created_at DESC'
        : 'ORDER BY wo_orders.created_at ASC'}
    `;

    const result = await db.query(query, params);

    // Convert BigInt and other data types for JSON serialization
    const processedRows = result.rows.map(row => ({
      order_id: row.order_id.toString(),
      order_number: row.order_number,
      order_type: row.order_type,
      status: row.status,
      created_at: row.created_at,
      updated_at: row.updated_at,
      customer_name: row.customer_name ?? '—',
      phone: row.phone ?? '',
      item_name: row.item_name,
      quantity: parseInt(row.quantity || 1),
      weight: parseFloat(row.weight || 0),
      material: row.material,
      technician_name: row.technician_name ?? null,
    }));

    res.status(200).json(processedRows);
  } catch (error) {
    console.error('Error fetching workshop orders:', error);
    res.status(500).json({ error: 'Internal server error', details: error.message });
  }
});

// Update status order workshop (service/custom) by admin_workshop/admin_toko/tukang
app.put('/workshop-orders/:id/status', async (req, res) => {
  try {
    const orderId = parseInt(req.params.id, 10);
    const nextStatusRaw = (req.body?.status ?? '').toString().trim().toLowerCase();
    const branchId = parseInt(String(req.body?.branch_id ?? req.query?.branch_id ?? ''), 10);
    if (!Number.isFinite(orderId) || orderId <= 0) {
      return res.status(400).json({ error: 'order_id tidak valid' });
    }
    if (!Number.isFinite(branchId) || branchId <= 0) {
      return res.status(400).json({ error: 'branch_id wajib diisi' });
    }

    const role = (req.user?.role ?? '').toString().trim().toLowerCase();
    const allowedRoles = new Set([
      'superadmin',
      'admin_toko',
      'admin_workshop',
      'admin_warehouse',
      'tukang',
      'stockist',
      'manajer',
    ]);
    if (!allowedRoles.has(role)) {
      return res.status(403).json({ error: 'Role tidak diizinkan update status workshop' });
    }

    const hasPickupPut = await ordersHasPickupBranchColumn(db);
    const hasMetaPut = await ordersHasMetadataColumnLive(db);
    const curRes = await db.query(
      `
        SELECT order_id, order_type, branch_id, status
          ${hasPickupPut ? ', pickup_branch_id' : ''}
          ${hasMetaPut ? ', metadata' : ''}
        FROM orders
        WHERE order_id = $1
        LIMIT 1
      `,
      [orderId]
    );
    if (curRes.rows.length === 0) {
      return res.status(404).json({ error: 'Order tidak ditemukan' });
    }
    const order = curRes.rows[0];
    const currentStatus = (order.status ?? '').toString().trim().toLowerCase();
    const receivingFromWarehouse =
      currentStatus === 'awaiting_warehouse' &&
      nextStatusRaw === 'sent-to-workshop' &&
      new Set(['admin_workshop', 'admin_warehouse', 'superadmin', 'manajer']).has(role);
    // Sumber kebenaran sama GET /workshop-orders (SQL), hindari false negative dari parse metadata di Node.
    if (!receivingFromWarehouse) {
      const visiblePut = await orderVisibleForWorkshopStatusPut(
        db,
        orderId,
        branchId,
        hasPickupPut,
        hasMetaPut,
      );
      if (!visiblePut) {
        return res.status(403).json({ error: 'Order tidak untuk cabang workshop ini' });
      }
    }
    const orderType = (order.order_type ?? '').toString().trim().toLowerCase();
    if (orderType !== 'service' && orderType !== 'custom') {
      return res.status(400).json({ error: 'Hanya order service/custom untuk workflow workshop' });
    }

    const allowedByRole = {
      admin_toko: new Set(['awaiting_warehouse', 'ready_for_pickup']),
      admin_workshop: new Set([
        ...ADMIN_WORKSHOP_PUT_ALLOWED_STATUSES,
        'sent-to-workshop',
      ]),
      tukang: new Set([
        'in_workshop',
        'repairing',
        'polishing',
        'done_workshop',
        'custom_work',
        'cancelled',
      ]),
      superadmin: new Set([
        'awaiting_warehouse',
        'sent-to-workshop',
        'in_workshop',
        'repairing',
        'polishing',
        'done_workshop',
        'ready_for_pickup',
        'custom_work',
        'cancelled',
      ]),
      manajer: new Set([
        'awaiting_warehouse',
        'sent-to-workshop',
        'in_workshop',
        'repairing',
        'polishing',
        'done_workshop',
        'ready_for_pickup',
        'custom_work',
        'cancelled',
      ]),
      admin_warehouse: new Set(['sent-to-workshop']),
    };
    const roleAllowedSet = allowedByRole[role] ?? new Set();
    if (!roleAllowedSet.has(nextStatusRaw)) {
      return res.status(400).json({
        error: `Status "${nextStatusRaw}" tidak diizinkan untuk role ${role}`,
      });
    }

    // Guard transitions: toko → awaiting_warehouse → (gudang) sent-to-workshop → workshop …
    const validTransitions = {
      pending: new Set(['awaiting_warehouse']),
      confirmed: new Set(['awaiting_warehouse']),
      awaiting_warehouse: new Set(['sent-to-workshop']),
      'sent-to-workshop': new Set(['in_workshop']),
      in_workshop: new Set(['repairing', 'polishing', 'done_workshop']),
      repairing: new Set(['polishing', 'done_workshop']),
      polishing: new Set(['done_workshop']),
      custom_work: new Set(['done_workshop']),
      'done_workshop': new Set(['ready_for_pickup']),
      'ready_for_pickup': new Set(['completed']),
    };
    if (nextStatusRaw === 'cancelled') {
      const mayCancel =
        (role === 'tukang' || role === 'admin_workshop' || role === 'superadmin') &&
        new Set([
          'pending',
          'confirmed',
          'awaiting_warehouse',
          'sent-to-workshop',
          'in_workshop',
          'repairing',
          'polishing',
          'custom_work',
        ]).has(currentStatus);
      if (!mayCancel) {
        return res.status(400).json({
          error: `Pembatalan tidak diizinkan dari status "${currentStatus}"`,
        });
      }
    } else if (
      validTransitions[currentStatus] &&
      !validTransitions[currentStatus].has(nextStatusRaw) &&
      currentStatus !== nextStatusRaw
    ) {
      return res.status(400).json({
        error: `Transisi status tidak valid (${currentStatus} -> ${nextStatusRaw})`,
      });
    }

    const awaitingToWorkshop =
      currentStatus === 'awaiting_warehouse' &&
      nextStatusRaw === 'sent-to-workshop';
    const bindServiceWorkshopMeta =
      hasMetaPut && awaitingToWorkshop;
    if (bindServiceWorkshopMeta) {
      const originStoreId = order.branch_id;
      const metaBind = {
        service_workshop_branch_id: String(branchId),
        service_origin_branch_id: String(originStoreId),
      };
      if (hasPickupPut) {
        await db.query(
          `
          UPDATE orders
          SET
            status = $1,
            branch_id = $2::bigint,
            pickup_branch_id = COALESCE(pickup_branch_id, $3::bigint),
            updated_at = NOW(),
            metadata = COALESCE(metadata, '{}'::jsonb) || $4::jsonb
          WHERE order_id = $5
        `,
          [
            nextStatusRaw,
            branchId,
            originStoreId,
            JSON.stringify(metaBind),
            orderId,
          ]
        );
      } else {
        await db.query(
          `
          UPDATE orders
          SET
            status = $1,
            branch_id = $2::bigint,
            updated_at = NOW(),
            metadata = COALESCE(metadata, '{}'::jsonb) || $3::jsonb
          WHERE order_id = $4
        `,
          [nextStatusRaw, branchId, JSON.stringify(metaBind), orderId]
        );
      }
    } else if (awaitingToWorkshop && !hasMetaPut) {
      // Tanpa kolom metadata, service_workshop_branch_id tidak tersimpan — order tetap
      // branch_id toko sehingga tidak lolos filter workshop. Pindahkan cabang asal ke workshop yang menerima.
      // Simpan cabang toko asal di pickup_branch_id bila kosong, supaya admin toko masih lolos
      // `orderVisibleForWorkshopStatusPut` / GET saat `branch_id` sudah di workshop.
      const originStoreId = order.branch_id;
      if (hasPickupPut) {
        await db.query(
          `
          UPDATE orders
          SET
            status = $1,
            branch_id = $2::bigint,
            pickup_branch_id = COALESCE(pickup_branch_id, $3::bigint),
            updated_at = NOW()
          WHERE order_id = $4
        `,
          [nextStatusRaw, branchId, originStoreId, orderId]
        );
      } else {
        await db.query(
          `
          UPDATE orders
          SET status = $1, branch_id = $2::bigint, updated_at = NOW()
          WHERE order_id = $3
        `,
          [nextStatusRaw, branchId, orderId]
        );
      }
    } else {
      await db.query(
        `
          UPDATE orders
          SET status = $1, updated_at = NOW()
          WHERE order_id = $2
        `,
        [nextStatusRaw, orderId]
      );
    }

    if (
      nextStatusRaw === 'awaiting_warehouse' &&
      currentStatus !== 'awaiting_warehouse' &&
      role === 'admin_toko'
    ) {
      broadcastWorkshop(
        `Service/custom #${orderId} dari toko menunggu persetujuan workshop`,
        'workshop_assignment',
        {
          branch_id: branchId,
          event: 'workshop_service_pending',
          payload: { order_id: orderId, order_type: orderType, status: 'awaiting_warehouse' },
        }
      );
    }
    if (awaitingToWorkshop) {
      broadcastWorkshop(
        `Order #${orderId} disetujui — masuk antrian pekerjaan workshop`,
        'order_update',
        {
          branch_id: branchId,
          event: 'workshop_approved',
          payload: { order_id: orderId, status: 'sent-to-workshop' },
        }
      );
    }
    if (
      new Set(['in_workshop', 'repairing', 'polishing', 'custom_work']).has(nextStatusRaw) &&
      currentStatus !== nextStatusRaw
    ) {
      broadcastWorkshop(
        `Order #${orderId} sedang dikerjakan tukang (${nextStatusRaw})`,
        'order_update',
        {
          branch_id: branchId,
          event: 'workshop_in_progress',
          payload: { order_id: orderId, status: nextStatusRaw },
        }
      );
    }
    if (
      nextStatusRaw === 'ready_for_pickup' &&
      currentStatus === 'done_workshop'
    ) {
      let storeBranchId = order.branch_id;
      if (hasMetaPut && order.metadata && typeof order.metadata === 'object') {
        const origin = order.metadata.service_origin_branch_id;
        if (origin != null && String(origin).trim() !== '') {
          storeBranchId = origin;
        }
      } else if (hasPickupPut && order.pickup_branch_id != null) {
        storeBranchId = order.pickup_branch_id;
      }
      broadcastWorkshop(
        `Order service/custom #${orderId} dikirim workshop — menunggu terima di toko`,
        'store_assignment',
        {
          branch_id: storeBranchId,
          event: 'workshop_sent_to_store',
          payload: { order_id: orderId, status: 'ready_for_pickup' },
        }
      );
    }

    return res.status(200).json({
      success: true,
      order_id: String(orderId),
      old_status: currentStatus,
      new_status: nextStatusRaw,
    });
  } catch (error) {
    console.error('Error updating workshop order status:', error);
    return res.status(500).json({ error: 'Internal server error' });
  }
});

// Admin workshop: tugaskan order antrian ke tukang (metadata) tanpa alur Mulai oleh tukang.
app.put('/workshop-orders/:id/assign-technician', async (req, res) => {
  try {
    const orderId = parseInt(req.params.id, 10);
    const branchId = parseInt(String(req.body?.branch_id ?? ''), 10);
    const technicianId = parseInt(String(req.body?.technician_id ?? ''), 10);
    const startImmediately =
      req.body?.start_immediately === true ||
      String(req.body?.start_immediately ?? '').toLowerCase() === 'true';

    if (!Number.isFinite(orderId) || orderId <= 0) {
      return res.status(400).json({ error: 'order_id tidak valid' });
    }
    if (!Number.isFinite(branchId) || branchId <= 0) {
      return res.status(400).json({ error: 'branch_id wajib diisi' });
    }
    if (!Number.isFinite(technicianId) || technicianId <= 0) {
      return res.status(400).json({ error: 'technician_id wajib diisi' });
    }

    const role = (req.user?.role ?? '').toString().trim().toLowerCase();
    const allowedRoles = new Set(['admin_workshop', 'superadmin', 'manajer']);
    if (!allowedRoles.has(role)) {
      return res.status(403).json({ error: 'Role tidak diizinkan menugaskan tukang' });
    }

    const techCheck = await db.query(
      `
        SELECT u.user_id, u.username
        FROM users u
        JOIN user_branch_roles ubr ON u.user_id = ubr.user_id
        WHERE u.user_id = $1
          AND ubr.branch_id = $2
          AND ubr.role = 'tukang'
          AND u.status = 'active'
        LIMIT 1
      `,
      [technicianId, branchId]
    );
    if (techCheck.rows.length === 0) {
      return res.status(400).json({
        error: 'Tukang tidak ditemukan atau tidak aktif di cabang ini',
      });
    }
    const techUsername = techCheck.rows[0].username;

    const hasPickupAssign = await ordersHasPickupBranchColumn(db);
    const hasMetaAssign = await ordersHasMetadataColumn(db);
    const curRes = await db.query(
      `
        SELECT order_id, order_type, branch_id, status
          ${hasPickupAssign ? ', pickup_branch_id' : ''}
          ${hasMetaAssign ? ', metadata' : ''}
        FROM orders
        WHERE order_id = $1
        LIMIT 1
      `,
      [orderId]
    );
    if (curRes.rows.length === 0) {
      return res.status(404).json({ error: 'Order tidak ditemukan' });
    }
    const order = curRes.rows[0];
    const visibleAssign = await orderVisibleForWorkshopStatusPut(
      db,
      orderId,
      branchId,
      hasPickupAssign,
      hasMetaAssign
    );
    if (!visibleAssign) {
      return res.status(403).json({ error: 'Order tidak untuk cabang workshop ini' });
    }

    const orderType = (order.order_type ?? '').toString().trim().toLowerCase();
    if (orderType !== 'service' && orderType !== 'custom') {
      return res.status(400).json({
        error: 'Hanya order service/custom yang bisa ditugaskan ke tukang',
      });
    }

    const currentStatus = (order.status ?? '').toString().trim().toLowerCase();
    const assignableStatuses = new Set([
      'sent-to-workshop',
      'in_workshop',
      'repairing',
      'polishing',
      'custom_work',
    ]);
    if (!assignableStatuses.has(currentStatus)) {
      return res.status(400).json({
        error: `Penugasan tidak diizinkan dari status "${currentStatus}"`,
      });
    }

    let nextStatus = currentStatus;
    if (startImmediately) {
      nextStatus = orderType === 'custom' ? 'custom_work' : 'repairing';
    } else if (currentStatus === 'sent-to-workshop') {
      nextStatus = 'in_workshop';
    }

    const metaPatch = {
      assigned_technician_id: String(technicianId),
      assigned_technician: techUsername,
      assigned_by_role: role,
      assigned_at: new Date().toISOString(),
    };
    if (req.user?.user_id != null) {
      metaPatch.assigned_by_user_id = String(req.user.user_id);
    }

    if (hasMetaAssign) {
      await db.query(
        `
          UPDATE orders
          SET status = $1,
              updated_at = NOW(),
              metadata = COALESCE(metadata, '{}'::jsonb) || $2::jsonb
          WHERE order_id = $3
        `,
        [nextStatus, JSON.stringify(metaPatch), orderId]
      );
    } else {
      await db.query(
        `
          UPDATE orders
          SET status = $1,
              updated_at = NOW(),
              user_id = $2::bigint
          WHERE order_id = $3
        `,
        [nextStatus, technicianId, orderId]
      );
    }

    if (
      new Set(['in_workshop', 'repairing', 'polishing', 'custom_work']).has(nextStatus) &&
      currentStatus !== nextStatus
    ) {
      broadcastWorkshop(
        `Order #${orderId} ditugaskan ke ${techUsername} (${nextStatus})`,
        'order_update',
        {
          branch_id: branchId,
          event: 'workshop_in_progress',
          payload: {
            order_id: orderId,
            status: nextStatus,
            technician_id: technicianId,
          },
        }
      );
    } else {
      broadcastWorkshop(
        `Order #${orderId} ditugaskan ke ${techUsername}`,
        'workshop_assignment',
        {
          branch_id: branchId,
          event: 'workshop_assigned',
          payload: {
            order_id: orderId,
            technician_id: technicianId,
            status: nextStatus,
          },
        }
      );
    }

    return res.status(200).json({
      success: true,
      order_id: String(orderId),
      technician_id: String(technicianId),
      technician_username: techUsername,
      old_status: currentStatus,
      new_status: nextStatus,
    });
  } catch (error) {
    console.error('Error assigning workshop technician:', error);
    return res.status(500).json({ error: 'Internal server error' });
  }
});

// Get technicians for admin workshop
app.get('/technicians', async (req, res) => {
  try {
    const { branch_id } = req.query;

    if (!branch_id) {
      return res.status(400).json({ error: 'branch_id is required' });
    }

    const result = await db.query(`
      SELECT
        u.user_id,
        u.username,
        u.status,
        u.created_at,
        u.updated_at,
        ubr.role,
        COUNT(o.order_id) as active_orders,
        COUNT(CASE WHEN o.status IN ('completed', 'delivered') THEN 1 END) as completed_orders_today
      FROM users u
      JOIN user_branch_roles ubr ON u.user_id = ubr.user_id
      LEFT JOIN orders o ON o.user_id = u.user_id
        AND o.branch_id = ubr.branch_id
        AND DATE(o.updated_at) = CURRENT_DATE
        AND o.status IN ('in_workshop', 'repairing', 'polishing', 'custom_work')
      WHERE ubr.branch_id = $1
        AND ubr.role = 'tukang'
        AND u.status = 'active'
      GROUP BY u.user_id, u.username, u.status, u.created_at, u.updated_at, ubr.role
      ORDER BY u.username
    `, [branch_id]);

    // Convert BigInt and other data types for JSON serialization
    const processedRows = result.rows.map(row => ({
      user_id: row.user_id.toString(),
      username: row.username,
      status: row.status,
      created_at: row.created_at,
      updated_at: row.updated_at,
      role: row.role,
      active_orders: parseInt(row.active_orders || 0),
      completed_orders_today: parseInt(row.completed_orders_today || 0)
    }));

    res.status(200).json(processedRows);
  } catch (error) {
    console.error('Error fetching technicians:', error);
    res.status(500).json({ error: 'Internal server error', details: error.message });
  }
});
}

module.exports = { registerWorkshopOrdersRoutes };

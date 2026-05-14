'use strict';

const {
  paymentsHasProofUrlColumn,
  paymentsHasValidatedByColumn,
  ordersHasPickedUpAtColumn,
  paymentsHasRevenueBranchColumn,
} = require('../lib/payments_schema_helpers');

const {
  ordersHasPickupBranchColumn,
  ordersSupportsWorkshopStatuses,
} = require('../lib/orders_workshop_helpers');
const { ORDER_CALENDAR_TIMEZONE } = require('../lib/business_timezone');

/** POST /payments, GET /payments */
function registerPaymentsCoreRoutes(app, deps) {
  const { db, notifyClients } = deps;

app.post('/payments', async (req, res) => {
  const client = await db.getClient();
  try {
    const { order_id, amount, method, status, notes, proof_url } = req.body;

    if (!order_id || amount === undefined || amount === null || !method) {
      return res.status(400).json({ error: 'order_id, amount, dan method wajib diisi' });
    }

    const amountNum = Number(amount);
    if (!Number.isFinite(amountNum) || amountNum < 0) {
      return res.status(400).json({ error: 'amount harus angka valid dan tidak negatif' });
    }

    const parsedOrderId = parseInt(order_id, 10);
    if (isNaN(parsedOrderId)) {
      return res.status(400).json({ error: 'order_id harus berupa angka' });
    }

    // Validasi method pembayaran
    const validMethods = ['cash', 'transfer', 'qris', 'e-wallet'];
    if (!validMethods.includes(method)) {
      return res.status(400).json({ error: 'Method pembayaran tidak valid' });
    }

    // For non-cash methods, payment proof photo is required
    const requiresProof = method === 'transfer' || method === 'qris' || method === 'e-wallet';
    if (requiresProof) {
      const proof = (proof_url ?? '').toString().trim();
      if (!proof) {
        return res.status(400).json({
          error: 'Bukti pembayaran (proof_url) wajib untuk metode transfer/qris/e-wallet',
        });
      }
    }

    // Validasi status
    const validStatuses = ['pending', 'completed', 'failed', 'cancelled'];
    const paymentStatus = status || 'completed';
    if (!validStatuses.includes(paymentStatus)) {
      return res.status(400).json({ error: 'Status pembayaran tidak valid' });
    }

    // Cek apakah order ada dan ambil order_type + branch_id (untuk stock mutation buyback)
    const hasPickedUpAtCol = await ordersHasPickedUpAtColumn(client);
    const pickedUpSelect = hasPickedUpAtCol ? 'picked_up_at' : 'NULL::timestamp AS picked_up_at';
    const hasPickupColPay = await ordersHasPickupBranchColumn(client);
    const pickupSelect = hasPickupColPay
      ? 'pickup_branch_id'
      : 'NULL::bigint AS pickup_branch_id';
    const orderCheck = await client.query(
      `SELECT order_id, order_type, branch_id, status, ${pickedUpSelect}, ${pickupSelect} FROM orders WHERE order_id = $1`,
      [parsedOrderId]
    );
    if (orderCheck.rows.length === 0) {
      return res.status(404).json({ error: 'Order tidak ditemukan' });
    }

    const orderType = orderCheck.rows[0].order_type;
    const orderBranchId = orderCheck.rows[0].branch_id;
    const orderRowPay = orderCheck.rows[0];
    const lowerOrderTypePay = (orderType ?? '').toString().trim().toLowerCase();
    const allowMultiCompletedPay =
      lowerOrderTypePay === 'service' || lowerOrderTypePay === 'custom';

    // Cek apakah order sudah pernah dibayar (completed payment) — service/custom boleh DP + pelunasan.
    const existingPayment = await client.query(
      'SELECT payment_id FROM payments WHERE order_id = $1 AND status = $2',
      [parsedOrderId, 'completed']
    );
    const hasPriorCompletedPay = existingPayment.rows.length > 0;
    if (!allowMultiCompletedPay && hasPriorCompletedPay) {
      return res.status(400).json({ error: 'Order ini sudah dibayar. Tidak dapat melakukan pembayaran ganda.' });
    }

    const hasRevColPay = await paymentsHasRevenueBranchColumn(client);
    /** @type {number | null} */
    let revenueBranchIdParam = null;
    if (hasRevColPay) {
      const orderBidPay = parseInt(String(orderBranchId), 10);
      if (lowerOrderTypePay === 'service' || lowerOrderTypePay === 'custom') {
        const pkRaw = (req.body.payment_kind ?? '').toString().trim().toLowerCase();
        let kind = pkRaw;
        if (!kind) {
          kind = hasPriorCompletedPay ? 'settlement' : 'dp';
        }
        const isSettlementKind =
          kind === 'settlement' ||
          kind === 'pelunasan' ||
          kind === 'pickup' ||
          kind === 'final' ||
          kind === 'lunas';
        const pickupRaw = orderRowPay.pickup_branch_id;
        const pickupBid =
          pickupRaw != null ? parseInt(String(pickupRaw), 10) : NaN;
        const effectivePickup =
          Number.isFinite(pickupBid) && pickupBid > 0 ? pickupBid : orderBidPay;
        revenueBranchIdParam = isSettlementKind
          ? (Number.isFinite(effectivePickup) ? effectivePickup : orderBidPay)
          : (Number.isFinite(orderBidPay) ? orderBidPay : null);
      } else {
        revenueBranchIdParam = Number.isFinite(orderBidPay) ? orderBidPay : null;
      }
    }

    const hasProofCol = await paymentsHasProofUrlColumn(client);
    const hasValidatedByCol = await paymentsHasValidatedByColumn(client);
    let finalNotes = notes;
    const proofTrimmed = (proof_url ?? '').toString().trim();
    if (!hasProofCol && proofTrimmed) {
      const n = (finalNotes ?? '').toString().trim();
      finalNotes = n ? `${n}\nBukti: ${proofTrimmed}` : `Bukti: ${proofTrimmed}`;
    }

    await client.query('BEGIN');

    // Insert pembayaran ke database (backward-compatible with older DBs)
    const validatedByRaw = req.user?.user_id ?? req.user?.id ?? null;
    const validatedByParsed = validatedByRaw != null ? parseInt(String(validatedByRaw), 10) : NaN;
    const validatedBy = Number.isFinite(validatedByParsed) ? validatedByParsed : null;
    const cols = ['order_id', 'amount', 'method', 'status', 'notes'];
    const values = ['$1', '$2', '$3', '$4', '$5'];
    const params = [parsedOrderId, amountNum, method, paymentStatus, finalNotes];
    let idx = params.length;

    if (hasProofCol) {
      cols.push('proof_url');
      values.push(`$${++idx}`);
      params.push(proof_url || null);
    }

    if (hasValidatedByCol) {
      cols.push('validated_by');
      values.push(`$${++idx}`);
      params.push(validatedBy);
    }

    if (hasRevColPay) {
      cols.push('revenue_branch_id');
      values.push(`$${++idx}`);
      params.push(revenueBranchIdParam);
    }

    cols.push('payment_date');
    values.push('CURRENT_TIMESTAMP');

    const insertQuery = `
      INSERT INTO payments (${cols.join(', ')})
      VALUES (${values.join(', ')})
      RETURNING *
    `;

    const result = await client.query(insertQuery, params);

    // Update status order jika pembayaran completed
    if (paymentStatus === 'completed') {
      const orderStatus = (orderCheck.rows[0].status ?? '').toString().trim().toLowerCase();
      const pickedUpAt = orderCheck.rows[0].picked_up_at;
      let nextOrderStatus = 'completed';
      const lowerOrderType = lowerOrderTypePay;
      if (lowerOrderType === 'service' || lowerOrderType === 'custom') {
        const supportsWorkshopStatuses = await ordersSupportsWorkshopStatuses(client);
        const postDpCabangStatus = supportsWorkshopStatuses ? 'confirmed' : 'pending';
        // Service/custom: DP / pembayaran pertama di kasir => menunggu admin toko kirim ke bengkel (confirmed).
        // Pelunasan setelah pickup => completed. Jangan loncat ke workshop dari kasir.
        nextOrderStatus = pickedUpAt ? 'completed' : postDpCabangStatus;
        // Jika sudah berada di fase workshop, jangan mundur status.
        if (
          ['awaiting_warehouse', 'sent-to-workshop', 'in_workshop', 'repairing', 'polishing', 'done_workshop', 'ready_for_pickup'].includes(orderStatus)
        ) {
          nextOrderStatus = orderStatus;
        }
      }
      await client.query(
        'UPDATE orders SET status = $1, updated_at = CURRENT_TIMESTAMP WHERE order_id = $2',
        [nextOrderStatus, parsedOrderId]
      );

      // BUYBACK: stock in happens ONLY when paid by kasir (completed)
      // Stock in but NOT ready for sale: items.status stays 'buyback' (not in allowed sale statuses).
      if ((orderType ?? '').toString().trim().toLowerCase() === 'buyback') {
        const itemsRes = await client.query(
          `
            SELECT oi.item_id, oi.qty
            FROM order_items oi
            WHERE oi.order_id = $1
              AND oi.item_id IS NOT NULL
          `,
          [parsedOrderId]
        );

        for (const row of itemsRes.rows) {
          const itemId = parseInt(row.item_id, 10);
          const qtyVal = parseInt(row.qty, 10) || 1;
          if (!Number.isFinite(itemId) || qtyVal <= 0) continue;

          // Lock item row to avoid race conditions on quantity
          const prev = await client.query(
            `SELECT COALESCE(quantity, 0) AS quantity, status
             FROM items
             WHERE item_id = $1
             FOR UPDATE`,
            [itemId]
          );
          const prevQty = prev.rows.length > 0 ? parseInt(prev.rows[0].quantity, 10) : 0;
          const prevStatus = prev.rows.length > 0 ? (prev.rows[0].status ?? 'unknown').toString() : 'unknown';

          const upd = await client.query(
            `
              UPDATE items
              SET quantity = COALESCE(quantity, 0) + $1,
                  status = 'buyback',
                  ownership = 'toko',
                  stock_type = 'inventory',
                  updated_at = NOW()
              WHERE item_id = $2
              RETURNING COALESCE(quantity, 0) AS quantity
            `,
            [qtyVal, itemId]
          );
          const nextQty = upd.rows.length > 0 ? parseInt(upd.rows[0].quantity, 10) : prevQty + qtyVal;

          await client.query(
            `INSERT INTO stock_history (item_id, old_status, new_status, changed_by, notes)
             VALUES ($1, $2, $3, $4, $5)`,
            [
              itemId,
              prevStatus,
              'buyback',
              validatedBy,
              `Order buyback paid (order_id ${parsedOrderId})`,
            ]
          );

          await client.query(
            `
              INSERT INTO stock_mutations (
                item_id, branch_id, type, quantity, previous_stock, current_stock,
                notes, reference_id, reference_type, created_by
              )
              VALUES ($1, $2, 'in', $3, $4, $5, $6, $7, 'order', $8)
            `,
            [
              itemId,
              orderBranchId,
              qtyVal,
              prevQty,
              nextQty,
              `Order buyback completed (order_id ${parsedOrderId})`,
              parsedOrderId,
              validatedBy,
            ]
          );
        }
      }
    }

    const payment = result.rows[0];
    console.log('Pembayaran dicatat:', payment);
    await client.query('COMMIT');

    // Setelah commit: broadcast tidak boleh menggagalkan pembayaran.
    if (paymentStatus === 'completed') {
      try {
        notifyClients(
          `Order ${parsedOrderId} (${orderType}) telah dibayar dan status diperbarui`
        );
      } catch (notifyErr) {
        console.error('Payment OK but notification failed:', notifyErr);
      }
    }

    res.status(201).json({ message: 'Pembayaran berhasil dicatat', payment });
  } catch (error) {
    try {
      await client.query('ROLLBACK');
    } catch (_) { }
    console.error('Error creating payment:', error);
    const code = error?.code;
    const detail = (error?.detail || error?.message || '').toString();
    if (code === '23514') {
      return res.status(400).json({
        error: 'Update order/status ditolak oleh aturan database. Pastikan migrasi status order terbaru sudah dijalankan.',
        details: detail,
      });
    }
    res.status(500).json({
      error: 'Internal server error',
      details: process.env.NODE_ENV === 'production' ? undefined : detail,
    });
  } finally {
    try {
      client.release?.();
    } catch (_) { }
  }
});

app.get('/payments', async (req, res) => {
  try {
    const { branch_id, order_id, status, method, limit = 50, offset = 0 } = req.query;

    let query = `
      SELECT
        p.*,
        COALESCE(STRING_AGG(oi.nama_item, ', '), 'Unknown Item') as nama_item,
        o.total as order_total,
        c.name as customer_name,
        b.name as branch_name
      FROM payments p
      JOIN orders o ON p.order_id = o.order_id
      LEFT JOIN customers c ON o.customer_id = c.customer_id
      LEFT JOIN branches b ON o.branch_id = b.branch_id
      LEFT JOIN order_items oi ON o.order_id = oi.order_id
      WHERE 1=1
    `;

    const params = [];
    let paramIndex = 1;

    if (branch_id) {
      query += ` AND o.branch_id = $${paramIndex}`;
      params.push(branch_id);
      paramIndex++;
    }

    if (order_id) {
      query += ` AND p.order_id = $${paramIndex}`;
      params.push(order_id);
      paramIndex++;
    }

    if (status) {
      query += ` AND p.status = $${paramIndex}`;
      params.push(status);
      paramIndex++;
    }

    if (method) {
      query += ` AND p.method = $${paramIndex}`;
      params.push(method);
      paramIndex++;
    }

    query += ` GROUP BY p.payment_id, p.order_id, p.amount, p.method, p.status, p.created_at, p.updated_at, o.total, c.name, b.name ORDER BY p.created_at DESC LIMIT $${paramIndex} OFFSET $${paramIndex + 1}`;
    params.push(limit, offset);

    const result = await db.query(query, params);
    res.status(200).json(result.rows);
  } catch (error) {
    console.error('Error fetching payments:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// Get daily payments for kasir and admin toko
app.get('/payments/daily-summary', async (req, res) => {
  try {
    const { branch_id, date, user_id } = req.query;

    const role = (req.user?.role ?? '').toString().trim().toLowerCase();
    const jwtBranchRaw = String(req.user?.branch_id ?? '').trim();
    const queryBranchRaw = String(branch_id ?? '').trim();
    // Kasir: utamakan cabang di JWT (sinkron dengan switch-context), hindari branch_id query yang stale.
    const effectiveBranchRaw =
      role === 'kasir' && jwtBranchRaw.length > 0 ? jwtBranchRaw : queryBranchRaw;
    if (!effectiveBranchRaw) {
      return res.status(400).json({ error: 'branch_id is required' });
    }
    const parsedBranchId = parseInt(effectiveBranchRaw, 10);
    if (!Number.isFinite(parsedBranchId) || parsedBranchId <= 0) {
      return res.status(400).json({ error: 'branch_id must be a positive number' });
    }

    const bizTz = ORDER_CALENDAR_TIMEZONE;

    const datePat = /^\d{4}-\d{2}-\d{2}$/;
    const dfRaw = String(req.query.date_from ?? '').trim();
    const dtRaw = String(req.query.date_to ?? '').trim();
    const MAX_PAYMENT_RANGE_DAYS = 93;

    // Hari transaksi: cocokkan created_at ATAU payment_date (zona bisnis), selaras perilaku /payments/daily
    // dan menangkap row yang tanggal keduanya tidak selaras karena timezone / migrasi.
    /** @type {string} */
    let paymentDateSql;
    /** @type {string[]} */
    let dateArgs;
    if (datePat.test(dfRaw) && datePat.test(dtRaw)) {
      if (dfRaw > dtRaw) {
        return res.status(400).json({ error: 'date_from harus <= date_to' });
      }
      const spanMs =
        Date.parse(`${dtRaw}T12:00:00`) - Date.parse(`${dfRaw}T12:00:00`);
      const spanDays = Math.floor(spanMs / 86400000) + 1;
      if (spanDays > MAX_PAYMENT_RANGE_DAYS) {
        return res.status(400).json({
          error: `Rentang tanggal maksimal ${MAX_PAYMENT_RANGE_DAYS} hari`,
        });
      }
      dateArgs = [dfRaw, dtRaw];
      paymentDateSql = `(
        (timezone('${bizTz}', p.created_at))::date BETWEEN $2::date AND $3::date
        OR (
          p.payment_date IS NOT NULL AND (
            (timezone('${bizTz}', p.payment_date))::date BETWEEN $2::date AND $3::date
            OR (timezone('${bizTz}', p.payment_date AT TIME ZONE 'UTC'))::date BETWEEN $2::date AND $3::date
            OR p.payment_date::date BETWEEN $2::date AND $3::date
          )
        )
      )`;
    } else {
      const single = String(date ?? '').trim();
      const targetDate = datePat.test(single)
        ? single
        : new Intl.DateTimeFormat('en-CA', {
          timeZone: bizTz,
          year: 'numeric',
          month: '2-digit',
          day: '2-digit',
        }).format(new Date());
      dateArgs = [targetDate];
      paymentDateSql = `(
        (timezone('${bizTz}', p.created_at))::date = $2::date
        OR (
          p.payment_date IS NOT NULL AND (
            (timezone('${bizTz}', p.payment_date))::date = $2::date
            OR (timezone('${bizTz}', p.payment_date AT TIME ZONE 'UTC'))::date = $2::date
            OR p.payment_date::date = $2::date
          )
        )
      )`;
    }

    const hasProofCol = await paymentsHasProofUrlColumn(db);
    const hasValidatedByCol = await paymentsHasValidatedByColumn(db);
    const hasRevBranchColSummary = await paymentsHasRevenueBranchColumn(db);
    // Jangan hanya COALESCE(revenue, order): pelunasan service/custom bisa mengisi
    // revenue_branch_id = cabang pickup sementara order.branch_id = cabang toko.
    // Kasir di cabang toko harus tetap melihat "Bayar Today" untuk pembayaran yang ia proses.
    const branchScopeSqlSummary = hasRevBranchColSummary
      ? `(o.branch_id::bigint = $1::bigint OR (p.revenue_branch_id IS NOT NULL AND p.revenue_branch_id::bigint = $1::bigint))`
      : `o.branch_id::bigint = $1::bigint`;

    const validatedOnlyRaw = (req.query.validated_by_only ?? '').toString().trim().toLowerCase();
    const validatedOffExplicit =
      validatedOnlyRaw === '0' || validatedOnlyRaw === 'false' || validatedOnlyRaw === 'no';
    const validatedOnlyFromQuery =
      validatedOnlyRaw === '1' || validatedOnlyRaw === 'true' || validatedOnlyRaw === 'yes';
    // Kasir: default hanya pembayaran yang divalidasi user login (Bayar Today).
    // Kirim validated_by_only=0 untuk semua pembayaran completed di cabang (mis. admin ringkas).
    const validatedOnly =
      role === 'kasir'
        ? !validatedOffExplicit && (validatedOnlyFromQuery || validatedOnlyRaw === '')
        : validatedOnlyFromQuery;

    const orderTypeRaw = (req.query.order_type ?? '').toString().trim().toLowerCase();
    const allowedOrderTypes = new Set(['jual', 'buyback', 'service', 'custom']);
    const orderTypeFilter =
      orderTypeRaw && allowedOrderTypes.has(orderTypeRaw) ? orderTypeRaw : null;

    const userIdFilterRaw = (user_id ?? '').toString().trim();
    let userIdFromQuery =
      userIdFilterRaw.length > 0 ? parseInt(userIdFilterRaw, 10) : null;
    if (userIdFilterRaw.length > 0 && (userIdFromQuery == null || Number.isNaN(userIdFromQuery))) {
      return res.status(400).json({ error: 'user_id must be a number' });
    }

    let userIdFilter = null;
    if (validatedOnly) {
      if (!hasValidatedByCol) {
        return res.status(400).json({
          error: 'Kolom payments.validated_by belum tersedia',
          details:
            'Jalankan migration backend/migrations/20260502_000006_add_payments_validated_by.sql agar filter pembayaran per kasir bisa dipakai.',
        });
      }
      const tokenUserId = req.user?.user_id ?? req.user?.id;
      const parsedTokenUserId =
        tokenUserId != null ? parseInt(String(tokenUserId), 10) : NaN;
      if (tokenUserId == null || Number.isNaN(parsedTokenUserId)) {
        return res.status(401).json({
          error: 'Unauthorized',
          details: 'Token tidak berisi user_id; silakan login ulang.',
        });
      }
      userIdFilter = parsedTokenUserId;
    } else if (userIdFromQuery != null) {
      if (!hasValidatedByCol) {
        console.warn(
          '[payments/daily-summary] Ignoring user_id query filter: payments.validated_by column missing.',
        );
      } else {
        userIdFilter = userIdFromQuery;
      }
    }

    const listParams = [parsedBranchId, ...dateArgs];
    let listExtraWhere = '';
    listExtraWhere += ` AND p.status = 'completed'`;
    if (userIdFilter != null) {
      const pIdx = listParams.length + 1;
      // Kasir + filter default: tampilkan juga pembayaran lama tanpa validated_by (NULL).
      if (role === 'kasir' && validatedOnly) {
        listExtraWhere += ` AND (p.validated_by = $${pIdx} OR p.validated_by IS NULL)`;
      } else {
        listExtraWhere += ` AND p.validated_by = $${pIdx}`;
      }
      listParams.push(userIdFilter);
    }
    if (orderTypeFilter) {
      listExtraWhere += ` AND o.order_type = $${listParams.length + 1}`;
      listParams.push(orderTypeFilter);
    }

    // Get payments for the day (or date range)
    const paymentsResult = await db.query(`
      SELECT
        p.payment_id,
        p.order_id,
        p.amount,
        p.method as payment_method,
        p.status,
        ${hasProofCol ? 'p.proof_url' : 'NULL'} as proof_url,
        ${hasValidatedByCol ? 'p.validated_by' : 'NULL'} as validated_by,
        p.notes,
        p.created_at,
        p.updated_at,
        o.order_number,
        o.order_type,
        c.name as customer_name,
        c.phone
      FROM payments p
      JOIN orders o ON p.order_id = o.order_id
      JOIN customers c ON o.customer_id = c.customer_id
      WHERE ${branchScopeSqlSummary}
        AND ${paymentDateSql}
        ${listExtraWhere}
      ORDER BY p.created_at DESC
    `, listParams);

    const summaryParams = [parsedBranchId, ...dateArgs];
    let summaryExtraWhere = '';
    if (userIdFilter != null) {
      const pIdx = summaryParams.length + 1;
      if (role === 'kasir' && validatedOnly) {
        summaryExtraWhere += ` AND (p.validated_by = $${pIdx} OR p.validated_by IS NULL)`;
      } else {
        summaryExtraWhere += ` AND p.validated_by = $${pIdx}`;
      }
      summaryParams.push(userIdFilter);
    }
    if (orderTypeFilter) {
      summaryExtraWhere += ` AND o.order_type = $${summaryParams.length + 1}`;
      summaryParams.push(orderTypeFilter);
    }

    // Get summary
    // Business rule:
    // - jual/service/custom = pendapatan (uang masuk)
    // - buyback = pengeluaran (uang keluar)
    const summaryResult = await db.query(
      `
        SELECT
          COUNT(*) as total_payments,
          SUM(amount) as total_amount,
          COALESCE(SUM(CASE WHEN lower(trim(o.order_type::text)) IN ('jual', 'service', 'custom') THEN amount ELSE 0 END), 0) as income_amount,
          COALESCE(SUM(CASE WHEN lower(trim(o.order_type::text)) = 'buyback' THEN amount ELSE 0 END), 0) as expense_amount,
          COUNT(CASE WHEN method = 'cash' THEN 1 END) as cash_payments,
          COUNT(CASE WHEN method = 'transfer' THEN 1 END) as transfer_payments,
          COUNT(CASE WHEN method = 'qris' THEN 1 END) as qris_payments,
          COUNT(CASE WHEN method = 'e-wallet' THEN 1 END) as ewallet_payments,
          COALESCE(SUM(CASE WHEN method = 'cash' THEN amount ELSE 0 END), 0) as cash_amount,
          COALESCE(SUM(CASE WHEN method = 'transfer' THEN amount ELSE 0 END), 0) as transfer_amount,
          COALESCE(SUM(CASE WHEN method = 'qris' THEN amount ELSE 0 END), 0) as qris_amount,
          COALESCE(SUM(CASE WHEN method = 'e-wallet' THEN amount ELSE 0 END), 0) as ewallet_amount
        FROM payments p
        JOIN orders o ON p.order_id = o.order_id
        WHERE ${branchScopeSqlSummary}
          AND ${paymentDateSql}
          AND p.status = 'completed'
          ${summaryExtraWhere}
      `,
      summaryParams,
    );

    const summary = summaryResult.rows[0] || {
      total_payments: 0,
      total_amount: 0,
      cash_payments: 0,
      transfer_payments: 0,
      qris_payments: 0,
      ewallet_payments: 0,
      cash_amount: 0,
      transfer_amount: 0,
      qris_amount: 0,
      ewallet_amount: 0,
    };

    // Convert BigInt and other data types for JSON serialization
    const processedPayments = paymentsResult.rows.map(row => ({
      payment_id: row.payment_id.toString(),
      order_id: row.order_id.toString(),
      amount: parseFloat(row.amount || 0),
      payment_method: row.payment_method,
      status: row.status,
      proof_url: row.proof_url,
      validated_by: row.validated_by,
      notes: row.notes,
      created_at: row.created_at,
      updated_at: row.updated_at,
      order_number: row.order_number,
      order_type: row.order_type,
      customer_name: row.customer_name,
      phone: row.phone
    }));

    const processedSummary = {
      total_payments: parseInt(summary.total_payments || 0),
      // Backward-compatible:
      // - total_amount: total nominal semua pembayaran completed (income + expense)
      // - income_amount: nominal masuk (jual/service/custom)
      // - expense_amount: nominal keluar (buyback)
      // - net_amount: income - expense
      total_amount: parseFloat(summary.total_amount || 0),
      income_amount: parseFloat(summary.income_amount || 0),
      expense_amount: parseFloat(summary.expense_amount || 0),
      net_amount:
        (parseFloat(summary.income_amount || 0) || 0) -
        (parseFloat(summary.expense_amount || 0) || 0),
      cash_payments: parseInt(summary.cash_payments || 0),
      transfer_payments: parseInt(summary.transfer_payments || 0),
      qris_payments: parseInt(summary.qris_payments || 0),
      ewallet_payments: parseInt(summary.ewallet_payments || 0),
      cash_amount: parseFloat(summary.cash_amount || 0),
      transfer_amount: parseFloat(summary.transfer_amount || 0),
      qris_amount: parseFloat(summary.qris_amount || 0),
      ewallet_amount: parseFloat(summary.ewallet_amount || 0),
    };

    res.status(200).json({
      transactions: processedPayments,
      summary: processedSummary
    });
  } catch (error) {
    console.error('Error fetching daily payments:', error);
    res.status(500).json({ error: 'Internal server error', details: error.message });
  }
});
app.get('/payments/daily', async (req, res) => {
  try {
    const { date, branch_id } = req.query;

    if (!date) {
      return res.status(400).json({ error: 'date and branch_id are required' });
    }

    const role = (req.user?.role ?? '').toString().trim().toLowerCase();
    const jwtBranchRawDaily = String(req.user?.branch_id ?? '').trim();
    const queryBranchRawDaily = String(branch_id ?? '').trim();
    const effectiveBranchDaily =
      role === 'kasir' && jwtBranchRawDaily.length > 0
        ? jwtBranchRawDaily
        : queryBranchRawDaily;
    if (!effectiveBranchDaily) {
      return res.status(400).json({ error: 'date and branch_id are required' });
    }
    const parsedBranchDaily = parseInt(effectiveBranchDaily, 10);
    if (!Number.isFinite(parsedBranchDaily) || parsedBranchDaily <= 0) {
      return res.status(400).json({ error: 'branch_id must be a positive number' });
    }
    const tokenUserIdRaw = req.user?.user_id ?? req.user?.id;
    const tokenUserId =
      tokenUserIdRaw != null ? parseInt(String(tokenUserIdRaw), 10) : NaN;

    // IMPORTANT:
    // Jangan pakai `new Date('yyyy-MM-dd')` + toISOString() untuk filter harian.
    // JS akan menganggap string itu UTC midnight → bergeser jika bisnis pakai zona GMT+7 (ORDER_CALENDAR_TIMEZONE)
    // dan kolom DB bertipe TIMESTAMP tanpa timezone / tersimpan "waktu lokal".
    const BUSINESS_TZ = ORDER_CALENDAR_TIMEZONE;

    const targetDate = String(date).trim();
    if (!/^\d{4}-\d{2}-\d{2}$/.test(targetDate)) {
      return res
        .status(400)
        .json({ error: 'date must be in format yyyy-MM-dd' });
    }

    // Match tanggal secara robust untuk TIMESTAMP (tanpa timezone) dan TIMESTAMPTZ.
    // Kita cocokkan baik interpretasi "naive local", maupun "naive sebenarnya UTC".
    const paymentDateMatch = (paramRef) => `
      (
        (timezone('${BUSINESS_TZ}', p.payment_date))::date = ${paramRef}::date
        OR (timezone('${BUSINESS_TZ}', p.payment_date AT TIME ZONE 'UTC'))::date = ${paramRef}::date
        OR p.payment_date::date = ${paramRef}::date
      )
    `;

    const hasValidatedByCol = await paymentsHasValidatedByColumn(db);
    const hasRevBranchColDaily = await paymentsHasRevenueBranchColumn(db);
    const branchScopeSqlDaily = hasRevBranchColDaily
      ? `(o.branch_id::bigint = $1::bigint OR (p.revenue_branch_id IS NOT NULL AND p.revenue_branch_id::bigint = $1::bigint))`
      : `o.branch_id::bigint = $1::bigint`;
    const kasirScope =
      role === 'kasir' &&
      hasValidatedByCol &&
      Number.isFinite(tokenUserId) &&
      tokenUserId > 0;

    // Query untuk summary pembayaran harian
    const summaryQuery = `
      SELECT
        COUNT(*) as total_transactions,
        SUM(amount) as total_amount,
        method,
        COUNT(*) as method_count
      FROM payments p
      JOIN orders o ON p.order_id = o.order_id
      WHERE ${branchScopeSqlDaily}
        AND ${paymentDateMatch('$2')}
        AND p.status = 'completed'
        ${kasirScope ? 'AND (p.validated_by = $3 OR p.validated_by IS NULL)' : ''}
      GROUP BY method
      ORDER BY total_amount DESC
    `;

    const summaryParams = kasirScope
      ? [parsedBranchDaily, targetDate, tokenUserId]
      : [parsedBranchDaily, targetDate];
    const summaryResult = await db.query(summaryQuery, summaryParams);

    // Query untuk detail transaksi
    const detailQuery = `
      SELECT
        p.payment_id,
        p.order_id,
        p.amount,
        p.method,
        p.payment_date,
        COALESCE(STRING_AGG(oi.nama_item, ', '), 'Unknown Item') as nama_item,
        c.name as customer_name
      FROM payments p
      JOIN orders o ON p.order_id = o.order_id
      LEFT JOIN customers c ON o.customer_id = c.customer_id
      LEFT JOIN order_items oi ON o.order_id = oi.order_id
      WHERE ${branchScopeSqlDaily}
        AND ${paymentDateMatch('$2')}
        AND p.status = 'completed'
        ${kasirScope ? 'AND (p.validated_by = $3 OR p.validated_by IS NULL)' : ''}
      GROUP BY p.payment_id, p.order_id, p.amount, p.method, p.payment_date, c.name
      ORDER BY p.payment_date DESC
    `;

    const detailParams = kasirScope
      ? [parsedBranchDaily, targetDate, tokenUserId]
      : [parsedBranchDaily, targetDate];
    const detailResult = await db.query(detailQuery, detailParams);

    // Hitung total keseluruhan
    const totalAmount = summaryResult.rows.reduce((sum, row) => sum + parseFloat(row.total_amount || 0), 0);
    const totalTransactions = summaryResult.rows.reduce((sum, row) => sum + parseInt(row.total_transactions || 0), 0);

    // Format payment methods sebagai object
    const paymentMethods = {};
    summaryResult.rows.forEach(row => {
      paymentMethods[row.method] = parseFloat(row.total_amount || 0);
    });

    res.status(200).json({
      summary: {
        total_amount: totalAmount,
        total_transactions: totalTransactions,
        payment_methods: paymentMethods,
        by_method: summaryResult.rows.map(row => ({
          method: row.method,
          total_amount: parseFloat(row.total_amount || 0),
          method_count: parseInt(row.method_count || 0),
        })),
      },
      transactions: detailResult.rows.map(row => ({
        ...row,
        timestamp: row.payment_date, // backward compatibility for clients expecting `timestamp`
      })),
    });
  } catch (error) {
    console.error('Error fetching daily payments:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

}

module.exports = { registerPaymentsCoreRoutes };

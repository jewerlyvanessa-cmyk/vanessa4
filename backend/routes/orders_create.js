'use strict';

const {
  ordersHasMetadataColumn,
  ordersHasPickupBranchColumn,
  ordersEstimateColumns,
} = require('../lib/orders_workshop_helpers');
const {
  getItemsColumnFlags,
  itemSelectStockFields,
  insertManualOrderItem,
  formatDbErrorForClient,
  updateItemStatusAndStock,
  defaultItemsPhotoColumnName,
} = require('../lib/items_schema_helpers');
const {
  roundUpToNearest5000,
  getItemsPhotoColumn,
  getOrderItemsPhotoColumn,
  getItemConditionsColumns,
  getOrdersJumlahColumnMode,
} = require('../lib/orders_http_helpers');
const { resolveNotaOrder } = require('../lib/order_nota_helpers');
const {
  replayIdempotentIfExists,
  storeIdempotentResponse,
} = require('../lib/idempotency_helpers');
function registerOrdersCreateRoutes(app, deps) {
  const { db, upload } = deps;

  app.post('/orders', upload.single('photo'), async (req, res) => {
    if (await replayIdempotentIfExists(db, req, res, '/orders')) {
      return;
    }

    const client = await db.getClient();
  
    try {
      // Parse order_data from multipart field
      let orderData;
      if (req.body.order_data) {
        orderData = JSON.parse(req.body.order_data);
      } else {
        orderData = req.body; // fallback for non-multipart
      }
  
      // Handle uploaded photo
      let uploadedPhotoPath = null;
      if (req.file) {
        // Store a URL path (so clients can render it directly)
        uploadedPhotoPath = `/uploads/${req.file.filename}`;
      }
  
      const toObject = (raw) => {
        if (raw && typeof raw === 'object' && !Array.isArray(raw)) return raw;
        if (typeof raw === 'string') {
          const s = raw.trim();
          if (!s) return {};
          try {
            const parsed = JSON.parse(s);
            return parsed && typeof parsed === 'object' && !Array.isArray(parsed)
              ? parsed
              : {};
          } catch (_) {
            return {};
          }
        }
        return {};
      };
  
      const toNumberLoose = (raw) => {
        if (typeof raw === 'number') return Number.isFinite(raw) ? raw : NaN;
        const s0 = String(raw ?? '').trim();
        if (!s0) return NaN;
        const s = s0.replace(/\s+/g, '');
        if (/^-?\d+$/.test(s)) return Number(s);
        let normalized = s;
        if (s.includes(',') && s.includes('.')) {
          if (s.lastIndexOf(',') > s.lastIndexOf('.')) {
            // 1.234,56 -> 1234.56
            normalized = s.replace(/\./g, '').replace(',', '.');
          } else {
            // 1,234.56 -> 1234.56
            normalized = s.replace(/,/g, '');
          }
        } else if (s.includes(',')) {
          // 1234,56 or 1.234,56
          normalized = s.replace(/\./g, '').replace(',', '.');
        } else {
          // 1.234.567 (thousands) vs 1234.56 (decimal)
          const dotCount = (s.match(/\./g) || []).length;
          if (dotCount > 1) normalized = s.replace(/\./g, '');
        }
        const n = Number(normalized);
        return Number.isFinite(n) ? n : NaN;
      };
  
      const firstFiniteNumber = (...vals) => {
        for (const v of vals) {
          const n = toNumberLoose(v);
          if (Number.isFinite(n)) return n;
        }
        return 0;
      };
  
      // Order jual dari stok: hanya status yang boleh di etalase (bukan buyback / servis / custom / sold).
      // Buyback harus lewat gudang (transfer) sampai status layak jual di cabang tujuan.
      {
        const ot = orderData.order_type;
        const ois = orderData.order_items;
        if (ot === 'jual' && Array.isArray(ois)) {
          const itemIds = [];
          for (const row of ois) {
            if (!row || row.item_id == null || row.item_id === '') continue;
            const n = parseInt(row.item_id, 10);
            if (Number.isFinite(n)) itemIds.push(n);
          }
          const uniqueIds = [...new Set(itemIds)];
          if (uniqueIds.length > 0) {
            const vr = await db.query(
              `SELECT item_id, status, kode_produk, name FROM items WHERE item_id = ANY($1::bigint[])`,
              [uniqueIds]
            );
            const found = new Set(vr.rows.map((r) => parseInt(r.item_id, 10)));
            for (const id of uniqueIds) {
              if (!found.has(id)) {
                return res.status(400).json({
                  error: 'item_id tidak ditemukan',
                  detail: String(id),
                });
              }
            }
            const allowed = new Set(['ready', 'available', 'reserved']);
            for (const row of vr.rows) {
              const st = (row.status ?? '').toString().trim().toLowerCase();
              if (!allowed.has(st)) {
                return res.status(400).json({
                  error: 'Item tidak boleh dijual dalam status ini',
                  detail: `item_id ${row.item_id} (${row.kode_produk || row.name || ''}) memiliki status "${row.status}". Barang buyback atau yang belum siap etalase harus diproses/ditransfer ke warehouse dulu.`,
                });
              }
            }
          }
        }
      }
  
      // Backward-compatible: DB may have items.photo_url (old) or items.photo_produk (new)
      const itemsPhotoCol = await getItemsPhotoColumn(client);
      const itemsColFlags = await getItemsColumnFlags(client);
      const itemStockSelect = itemSelectStockFields(itemsColFlags);
  
      const {
        order_type,
        order_number,
        branch_id,
        user_id,
        mode,
        customer_id,
        diskon = 0,
        order_items,
        status: requestedStatus,
        service_estimated_total,
        service_dp_amount: _service_dp_amount,
        // For backward compatibility
        item_id: _item_id,
        item_data: _item_data,
      } = orderData;
  
      const resolvedOrderUserId = (() => {
        const fromBody = parseInt(String(user_id ?? ''), 10);
        if (Number.isFinite(fromBody) && fromBody > 0) return fromBody;
        const fromJwt = parseInt(
          String(req.user?.user_id ?? req.user?.id ?? ''),
          10
        );
        if (Number.isFinite(fromJwt) && fromJwt > 0) return fromJwt;
        return null;
      })();
  
      const refOrderNumberRaw = String(
        orderData.reference_order_number ??
        orderData.nota_lama ??
        ''
      ).trim();
      const estimateAmountRaw = parseFloat(
        orderData.estimate_amount ??
        service_estimated_total ??
        orderData.custom_estimated_total ??
        0
      );
      const estimateAmount = Number.isFinite(estimateAmountRaw) && estimateAmountRaw > 0
        ? estimateAmountRaw
        : null;
      const estimateDueCandidate = String(
        orderData.estimate_due_at ??
        orderData.estimasi_selesai ??
        orderData.estimated_finish_at ??
        orderData.estimated_completion_date ??
        ''
      ).trim();
      let estimateDueAtIso = null;
      if (estimateDueCandidate) {
        const parsedDue = new Date(estimateDueCandidate);
        if (!Number.isNaN(parsedDue.getTime())) {
          estimateDueAtIso = parsedDue.toISOString();
        }
      }
      const estimateDurationText = String(
        orderData.estimate_duration_text ??
        orderData.estimasi_waktu ??
        ''
      ).trim() || null;
      const estimateNotes = String(
        orderData.estimate_notes ??
        orderData.keterangan ??
        orderData.catatan_service ??
        ''
      ).trim() || null;
  
      // Validate order_type
      const validOrderTypes = ['jual', 'buyback', 'service', 'custom'];
      if (!validOrderTypes.includes(order_type)) {
        return res.status(400).json({ error: 'Invalid order_type' });
      }
  
      // Validate required fields
      if (!customer_id || !branch_id || resolvedOrderUserId == null) {
        return res.status(400).json({
          error: 'Missing required fields: customer_id, branch_id, user_id',
        });
      }
  
      if (!order_items || !Array.isArray(order_items) || order_items.length === 0) {
        return res.status(400).json({ error: 'Order must have at least one item' });
      }
  
      await client.query('BEGIN');
  
      const itemsPhotoColName = defaultItemsPhotoColumnName(itemsPhotoCol);
      const orderItemsPhotoCol = await getOrderItemsPhotoColumn(client);
      const orderItemsPhotoColName = orderItemsPhotoCol || 'photo_produk';
  
      // Persist upload metadata (safe: filename is server-generated)
      let _uploadId = null;
      if (req.file) {
        const uploaderUserId = req.user?.user_id ? parseInt(req.user.user_id, 10) : null;
        const urlPath = `/uploads/${req.file.filename}`;
  
        await client.query('SAVEPOINT uploads_insert');
        try {
          const upRes = await client.query(
            `INSERT INTO uploads (storage_key, original_name, mime_type, size_bytes, url_path, uploaded_by_user_id)
           VALUES ($1, $2, $3, $4, $5, $6)
           RETURNING upload_id`,
            [
              req.file.filename,
              req.file.originalname || null,
              req.file.mimetype || null,
              typeof req.file.size === 'number' ? req.file.size : null,
              urlPath,
              Number.isFinite(uploaderUserId) ? uploaderUserId : null,
            ]
          );
          _uploadId = upRes.rows[0]?.upload_id ?? null;
          await client.query('RELEASE SAVEPOINT uploads_insert');
        } catch (_) {
          _uploadId = null;
          await client.query('ROLLBACK TO SAVEPOINT uploads_insert');
          await client.query('RELEASE SAVEPOINT uploads_insert');
        }
      }
  
      let nota_order = await resolveNotaOrder(client, {
        branch_id,
        order_type,
        order_number,
      });
  
      // Create order
      const rawRequestedStatus = (requestedStatus ?? '')
        .toString()
        .trim()
        .toLowerCase();
      let initialStatus = 'pending';
      if (order_type === 'service' || order_type === 'custom') {
        // Cabang toko: pending (DP → kasir; non-DP → admin toko). Workshop hanya setelah gudang setuju.
        initialStatus = 'pending';
        if (rawRequestedStatus === 'pending') {
          initialStatus = 'pending';
        } else if (rawRequestedStatus === 'sent-to-workshop') {
          initialStatus = 'pending';
        }
      } else if (rawRequestedStatus) {
        initialStatus = rawRequestedStatus;
      }
  
      const orderResult = await client.query(
        `INSERT INTO orders (
          order_type, customer_id, status, order_number, branch_id, user_id, diskon, mode, total
        ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)
        RETURNING *`,
        [
          order_type,
          customer_id,
          initialStatus,
          nota_order,
          branch_id,
          resolvedOrderUserId,
          diskon,
          mode,
          0,
        ] // total will be calculated later
      );
  
      const order = orderResult.rows[0];
  
      // Persist estimate fields to dedicated order columns when available.
      if (
        (estimateAmount !== null || estimateDueAtIso || estimateDurationText || estimateNotes) &&
        order?.order_id
      ) {
        const estCols = await ordersEstimateColumns(client);
        const setClauses = [];
        const values = [];
        if (estCols.estimate_amount) {
          setClauses.push(`estimate_amount = $${values.length + 1}`);
          values.push(estimateAmount);
        }
        if (estCols.estimate_due_at) {
          setClauses.push(`estimate_due_at = $${values.length + 1}`);
          values.push(estimateDueAtIso);
        }
        if (estCols.estimate_duration_text) {
          setClauses.push(`estimate_duration_text = $${values.length + 1}`);
          values.push(estimateDurationText);
        }
        if (estCols.estimate_notes) {
          setClauses.push(`estimate_notes = $${values.length + 1}`);
          values.push(estimateNotes);
        }
        if (setClauses.length > 0) {
          values.push(order.order_id);
          await client.query(
            `
              UPDATE orders
              SET ${setClauses.join(', ')}, updated_at = NOW()
              WHERE order_id = $${values.length}
            `,
            values
          );
        }
      }
  
      // Cabang pengambilan (service/custom): NULL = sama dengan cabang order.
      if ((order_type === 'service' || order_type === 'custom') && order?.order_id) {
        const hasPickupColOrd = await ordersHasPickupBranchColumn(client);
        if (hasPickupColOrd) {
          const pickupRaw =
            orderData.pickup_branch_id ?? orderData.pickupBranchId ?? null;
          const pickupBid =
            pickupRaw != null ? parseInt(String(pickupRaw), 10) : NaN;
          const orderBid = parseInt(String(branch_id), 10);
          if (
            Number.isFinite(pickupBid) &&
            pickupBid > 0 &&
            Number.isFinite(orderBid) &&
            pickupBid !== orderBid
          ) {
            await client.query(
              `UPDATE orders SET pickup_branch_id = $1, updated_at = NOW() WHERE order_id = $2`,
              [pickupBid, order.order_id]
            );
          }
        }
      }
  
      // Persist reference order number (nota lama) for future reprints.
      if ((order_type === 'buyback' || order_type === 'service') && refOrderNumberRaw) {
        const hasOrdersMetadata = await ordersHasMetadataColumn(client);
        if (hasOrdersMetadata) {
          await client.query(
            `
              UPDATE orders
              SET metadata = COALESCE(metadata, '{}'::jsonb) || $1::jsonb
              WHERE order_id = $2
            `,
            [
              JSON.stringify({
                reference_order_number: refOrderNumberRaw,
                nota_lama: refOrderNumberRaw,
                nota_jual: refOrderNumberRaw,
              }),
              order.order_id,
            ]
          );
        }
      }
  
      // Service/custom: simpan field form ke metadata agar cetak ulang / GET order sinkron dengan faktur.
      if ((order_type === 'service' || order_type === 'custom') && order?.order_id) {
        const hasSvcMeta = await ordersHasMetadataColumn(client);
        if (hasSvcMeta) {
          const firstReqItem =
            Array.isArray(order_items) && order_items.length > 0 ? order_items[0] : {};
          const kelengkapan = String(orderData.kelengkapan ?? '').trim();
          const keterangan = String(
            orderData.keterangan ?? orderData.estimate_notes ?? '',
          ).trim();
          const jenisService = String(
            firstReqItem.tipe ?? orderData.jenis_service ?? '',
          ).trim();
          const estimasiSelesaiRaw = String(orderData.estimasi_selesai ?? '').trim();
          const estimasiWaktuRaw = String(orderData.estimasi_waktu ?? '').trim();
          const metaPatch = {};
          if (kelengkapan) metaPatch.kelengkapan = kelengkapan;
          if (keterangan) metaPatch.keterangan = keterangan;
          if (jenisService) metaPatch.jenis_service = jenisService;
          if (estimasiWaktuRaw) metaPatch.estimasi_waktu = estimasiWaktuRaw;
          if (estimasiSelesaiRaw) {
            metaPatch.estimasi_selesai = estimasiSelesaiRaw;
            if (!estimateDueAtIso) metaPatch.estimasi_selesai_text = estimasiSelesaiRaw;
          } else if (
            order_type === 'custom' &&
            estimasiWaktuRaw &&
            !estimateDueAtIso
          ) {
            // Form custom: field "estimasi waktu" dipakai sebagai teks estimasi selesai bila tidak ada tanggal ter-parse.
            metaPatch.estimasi_selesai = estimasiWaktuRaw;
            metaPatch.estimasi_selesai_text = estimasiWaktuRaw;
          }
          if (estimateAmount !== null && estimateAmount > 0) {
            metaPatch.service_estimated_total = estimateAmount;
          }
          if (order_type === 'custom') {
            const spek = String(orderData.spesifikasi ?? '').trim();
            if (spek) metaPatch.spesifikasi = spek;
          }
          const serviceDpPersist = firstFiniteNumber(
            orderData.service_dp_amount,
            orderData.serviceDpAmount,
            _service_dp_amount,
            0,
          );
          if (serviceDpPersist > 0) {
            metaPatch.service_dp_amount = serviceDpPersist;
          }
          if (Object.keys(metaPatch).length > 0) {
            await client.query(
              `
                UPDATE orders
                SET metadata = COALESCE(metadata, '{}'::jsonb) || $1::jsonb, updated_at = NOW()
                WHERE order_id = $2
              `,
              [JSON.stringify(metaPatch), order.order_id],
            );
          }
        }
      }
  
      // Process order items
      let computedOrderItemsTotal = 0;
      for (const itemData of order_items) {
        // Assign uploaded photo to item if available
        if (uploadedPhotoPath && !itemData.photo_produk) {
          itemData.photo_produk = uploadedPhotoPath;
        }
  
        let final_item_id = itemData.item_id;
        let itemDetails = itemData; // Default to data from request
  
        // If item_id exists, this is from stock - get item details from database
        if (final_item_id) {
          const existingItem = await client.query(
            `SELECT
               name, kode_produk, weight, material, purity, kategori, jenis, tipe, ${itemsPhotoColName} as photo_produk,
               quantity, status${itemStockSelect}
             FROM items WHERE item_id = $1`,
            [final_item_id]
          );
          if (existingItem.rows.length > 0) {
            const dbItem = existingItem.rows[0];
            itemDetails = {
              ...itemData, // Keep request data for price, qty, etc.
              nama_item: dbItem.name,
              kode_produk: dbItem.kode_produk,
              weight: dbItem.weight,
              // Keep material/kadar from request (order_items) if provided; fallback to items table.
              material:
                (itemData.material != null && String(itemData.material).trim().length > 0)
                  ? itemData.material
                  : dbItem.material,
              purity:
                (itemData.purity != null && String(itemData.purity).trim().length > 0)
                  ? itemData.purity
                  : dbItem.purity,
              kategori: dbItem.kategori,
              jenis: dbItem.jenis,
              tipe: dbItem.tipe,
              photo_produk: itemData.photo_produk || dbItem.photo_produk,
              // Stock fields (used for quantity decrement / status decisions)
              item_quantity: dbItem.quantity,
              item_status: dbItem.status,
              item_ownership: dbItem.ownership ?? null,
              item_stock_type: dbItem.stock_type ?? null,
            };
          }
        }
  
        // Update item photo if new photo is provided for existing stock items
        if (final_item_id && itemData.photo_produk && itemData.photo_produk !== itemDetails.photo_produk) {
          await client.query(
            `UPDATE items SET ${itemsPhotoColName} = $1, updated_at = NOW() WHERE item_id = $2`,
            [itemData.photo_produk, final_item_id]
          );
        }
  
        // Handle item creation if item_data is provided (for unregistered items)
        if (!final_item_id && itemData.nama_item) {
          // Create new item
          // Try inserting item; if kode_produk already exists, reuse existing item
          try {
            // Buyback stock should be added only when payment is completed.
            // Start from 0 to avoid double count (default DB quantity is 1).
            const initialItemQty = order_type === 'buyback'
              ? 0
              : (parseInt(itemData.quantity, 10) || 1);
            final_item_id = await insertManualOrderItem(
              client,
              itemsColFlags,
              itemsPhotoColName,
              {
                nama_item: itemData.nama_item,
                kode_produk: itemData.kode_produk,
                weight: itemData.weight,
                material: itemData.material,
                purity: itemData.purity,
                kategori: itemData.kategori,
                jenis: itemData.jenis,
                tipe: itemData.tipe,
                ownership: itemData.ownership || 'unknown',
                stock_type: itemData.stock_type || 'non_inventory',
                status: itemData.status || 'unregistered',
                is_quick_registered: itemData.is_quick_registered || false,
                branch_id,
                initialItemQty,
                photo_produk: itemData.photo_produk,
              }
            );
          } catch (e) {
            // Handle unique constraint on kode_produk: find existing item
            if (e && e.code === '23505') {
              const existing = await client.query(
                `SELECT item_id FROM items WHERE kode_produk = $1 AND branch_id = $2 LIMIT 1`,
                [itemData.kode_produk, branch_id]
              );
              if (existing.rows.length > 0) {
                final_item_id = existing.rows[0].item_id;
              } else {
                throw e; // rethrow if unexpected
              }
            } else {
              throw e;
            }
          }
  
          // Update item status based on order type
          let newItemStatus;
          let newOwnership;
          let newStockType;
  
          switch (order_type) {
            case 'jual':
              if (itemData.is_quick_registered) {
                // QSR flow: reserved -> sold
                newItemStatus = 'sold';
                newOwnership = 'toko';
                newStockType = 'inventory';
              } else {
                // Normal sale: ready -> sold
                newItemStatus = 'sold';
                newOwnership = 'pelanggan';
                newStockType = 'non_inventory';
              }
              break;
            case 'buyback':
              newItemStatus = 'buyback';
              newOwnership = 'toko';
              newStockType = 'inventory';
              break;
            case 'service':
              newItemStatus = 'on-service';
              newOwnership = 'toko';
              newStockType = 'non_inventory';
              break;
            case 'custom':
              newItemStatus = 'on-custom';
              newOwnership = 'toko';
              newStockType = 'non_inventory';
              break;
          }
  
          const statusBeforeOrderUpdate = (
            itemData.status || 'unregistered'
          ).toString();
  
          await updateItemStatusAndStock(client, itemsColFlags, {
            itemId: final_item_id,
            status: newItemStatus,
            ownership: newOwnership,
            stockType: newStockType,
          });
  
          // Riwayat status: dari status baris setelah INSERT (bukan placeholder 'unknown')
          await client.query(
            `INSERT INTO stock_history (item_id, old_status, new_status, changed_by, notes)
             VALUES ($1, $2, $3, $4, $5)`,
            [
              final_item_id,
              statusBeforeOrderUpdate,
              newItemStatus,
              user_id,
              `Order ${order_type} created`,
            ]
          );
  
        }
  
        // Save item condition for buyback orders (works for existing and new items)
        if (order_type === 'buyback' && final_item_id) {
          const kondisiBarang = toObject(itemData.kondisi_barang ?? itemData.kondisiBarang);
          const itemRefOrderNumber = String(
            kondisiBarang.nota_jual ??
            refOrderNumberRaw ??
            ''
          ).trim();
          const catatanRaw = String(
            kondisiBarang.catatan_kondisi ??
            itemData.catatan_kondisi ??
            itemData.catatanKondisi ??
            ''
          ).trim();
          const catatanWithReference = (() => {
            if (!itemRefOrderNumber) return catatanRaw;
            if (/nota_jual_ref\s*:/i.test(catatanRaw)) return catatanRaw;
            return catatanRaw
              ? `${catatanRaw}\nnota_jual_ref: ${itemRefOrderNumber}`
              : `nota_jual_ref: ${itemRefOrderNumber}`;
          })();
          const itemConditionCols = await getItemConditionsColumns(client);
          const insertCols = ['item_id', 'order_id'];
          const insertParams = [final_item_id, order.order_id];
          const tipeBarang = String(
            kondisiBarang.tipe ??
            itemData.tipe ??
            itemDetails.tipe ??
            ''
          )
            .trim()
            .toLowerCase();
          const penyesuaianBerat = firstFiniteNumber(
            kondisiBarang.penyesuaian_berat,
            itemData.penyesuaian_berat,
            0
          );
          const hargaPerGramBuyback = firstFiniteNumber(
            kondisiBarang.harga_per_gram,
            itemData.harga_per_gram,
            itemDetails.harga_per_gram,
            0
          );
          const potonganKondisi = firstFiniteNumber(
            kondisiBarang.potongan_kondisi,
            itemData.potongan_kondisi,
            0
          );
          const untungRugiNormalized = String(
            kondisiBarang.untung_rugi ??
            itemData.untung_rugi ??
            itemData.untungRugi ??
            'UNTUNG'
          )
            .trim()
            .toUpperCase();
          let nilaiUntungRugiFormula = NaN;
          const coef =
            tipeBarang === 'biasa' ? 10000 :
              tipeBarang === 'gress' ? 12000 :
                0;
          if (coef > 0) {
            if (untungRugiNormalized === 'UNTUNG') {
              nilaiUntungRugiFormula = coef * penyesuaianBerat;
            } else if (untungRugiNormalized === 'RUGI') {
              nilaiUntungRugiFormula = -coef * penyesuaianBerat;
            } else {
              nilaiUntungRugiFormula = 0;
            }
          }
          const nilaiUntungRugiFinal = Number.isFinite(nilaiUntungRugiFormula)
            ? nilaiUntungRugiFormula
            : firstFiniteNumber(
              kondisiBarang.nilai_untung_rugi,
              itemData.nilai_untung_rugi,
              itemData.nilaiUntungRugi,
              0
            );
          const nilaiResaleRaw =
            (hargaPerGramBuyback * penyesuaianBerat) +
            nilaiUntungRugiFinal -
            potonganKondisi;
          const nilaiResaleRounded = roundUpToNearest5000(Math.ceil(nilaiResaleRaw));
          const optionalFields = {
            kondisi_fisik:
              (kondisiBarang.kondisi_fisik ??
                itemData.kondisi_fisik ??
                itemData.kondisiFisik ??
                'BAIK'),
            penyesuaian_berat: penyesuaianBerat,
            harga_per_gram: hargaPerGramBuyback,
            potongan_kondisi: potonganKondisi,
            nilai_resale: nilaiResaleRounded,
            untung_rugi: untungRugiNormalized || 'UNTUNG',
            nilai_untung_rugi: nilaiUntungRugiFinal,
            catatan_kondisi:
              catatanWithReference,
            foto_kondisi:
              kondisiBarang.foto_kondisi ||
              (itemData.photo_produk ? [itemData.photo_produk] : []),
          };
          for (const [col, val] of Object.entries(optionalFields)) {
            if (!itemConditionCols.has(col)) continue;
            insertCols.push(col);
            insertParams.push(val);
          }
          const placeholders = insertParams.map((_, i) => `$${i + 1}`).join(', ');
          await client.query(
            `INSERT INTO item_conditions (${insertCols.join(', ')}) VALUES (${placeholders})`,
            insertParams
          );
        }
  
        // Create order item
        // Catatan: diskon hanya level orders (bukan per item).
        // Default (jual/buyback): subtotal = qty * weight * harga_per_gram, lalu total dibulatkan naik ke kelipatan 5.000.
        // Service/Custom: boleh kirim angka final manual lewat `manual_total` (mis. biaya jasa / estimasi biaya).
        const qtyVal = parseInt(itemDetails.qty) || 1;
        const weightVal = parseFloat(itemDetails.weight) || 0;
        const hargaVal = parseFloat(itemDetails.harga_per_gram) || 0;
  
        const manualTotalRaw =
          itemDetails.manual_total ??
          itemDetails.manualTotal ??
          itemData.manual_total ??
          itemData.manualTotal;
        const manualTotalVal = parseFloat(manualTotalRaw);
  
        const isManualTotalAllowed = order_type === 'service' || order_type === 'custom';
        const subtotalVal =
          isManualTotalAllowed && Number.isFinite(manualTotalVal) && manualTotalVal > 0
            ? manualTotalVal
            : qtyVal * weightVal * hargaVal;
        const totalRoundedVal = Math.ceil(subtotalVal / 5000) * 5000;
  
        await client.query(
          `INSERT INTO order_items (
            order_id, item_id, nama_item, kode_produk, qty, weight, harga_per_gram,
            subtotal, diskon, total, ${orderItemsPhotoColName}, kategori, jenis, tipe, material, purity
          ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15, $16)`,
          [
            order.order_id,
            final_item_id,
            itemDetails.nama_item,
            itemDetails.kode_produk,
            qtyVal,
            weightVal,
            hargaVal,
            Number.isFinite(parseFloat(itemDetails.subtotal))
              ? parseFloat(itemDetails.subtotal)
              : subtotalVal,
            0, // diskon tidak disimpan per-item
            totalRoundedVal, // total item = pembulatan subtotal
            itemDetails.photo_produk,
            itemDetails.kategori,
            itemDetails.jenis,
            itemDetails.tipe,
            itemDetails.material,
            itemDetails.purity,
          ]
        );
  
        // Keep a running total from the authoritative per-item rounded value
        computedOrderItemsTotal += totalRoundedVal;
  
        // Update existing item stock if it's from items table (has item_id).
        // IMPORTANT: buyback should NOT check/consume stock like a sale.
        if (final_item_id && itemData.item_id) {
          const prevQtyRaw = itemDetails.item_quantity;
          const prevQty = Number.isFinite(parseInt(prevQtyRaw, 10))
            ? parseInt(prevQtyRaw, 10)
            : 0;
  
          if (order_type === 'jual') {
            // Decrease quantity for stock items. If stock remains, keep item as stock.
            const decRes = await client.query(
              `
                UPDATE items
                SET quantity = COALESCE(quantity, 0) - $1,
                    updated_at = NOW()
                WHERE item_id = $2
                  AND COALESCE(quantity, 0) >= $1
                RETURNING quantity, status
              `,
              [qtyVal, final_item_id]
            );
  
            if (decRes.rows.length === 0) {
              await client.query('ROLLBACK');
              return res.status(400).json({
                error: 'Insufficient stock quantity',
                detail: `Stock ${prevQty} < order quantity ${qtyVal}`,
              });
            }
  
            const nextQty = parseInt(decRes.rows[0].quantity, 10);
            const prevStatus = (itemDetails.item_status ?? decRes.rows[0].status ?? 'ready').toString();
  
            // If stock is depleted, mark as sold; otherwise keep as available for stock.
            if (nextQty <= 0) {
              const newItemStatus = 'sold';
              const newOwnership = 'pelanggan';
              const newStockType = 'non_inventory';
  
              await updateItemStatusAndStock(client, itemsColFlags, {
                itemId: final_item_id,
                status: newItemStatus,
                ownership: newOwnership,
                stockType: newStockType,
              });
  
              await client.query(
                `INSERT INTO stock_history (item_id, old_status, new_status, changed_by, notes)
                 VALUES ($1, $2, $3, $4, $5)`,
                [final_item_id, prevStatus, newItemStatus, user_id, `Order ${order_type} created (stock depleted)`]
              );
            }
  
            // Always record stock mutation for this sale (type must satisfy stock_mutations_type_check: in|out|transfer|adjustment)
            await client.query(
              `
                INSERT INTO stock_mutations (
                  item_id, branch_id, type, quantity, previous_stock, current_stock,
                  notes, reference_id, reference_type, created_by
                )
                VALUES ($1, $2, 'out', $3, $4, $5, $6, $7, 'order', $8)
              `,
              [
                final_item_id,
                branch_id,
                qtyVal,
                prevQty,
                nextQty,
                `Order ${order_type} (${nota_order})`,
                order.order_id,
                user_id,
              ]
            );
          }
        }
      }
  
      // Calculate total order amount
      // Source-of-truth: order_items.total (already rounded per item)
      // Order total formula: sum(order_items.total) - (sum(order_items.total) * diskon%)
      const orderItemsTotal = Number.isFinite(computedOrderItemsTotal)
        ? computedOrderItemsTotal
        : 0;
      const diskonOrder = parseFloat(diskon) || 0;
      const orderTotal = orderItemsTotal * (1 - diskonOrder / 100);
  
      // orders.jumlah may be GENERATED ALWAYS (vanessa3_schema) — never UPDATE it then.
      const jumlahRounded = roundUpToNearest5000(orderTotal);
      const jumlahMode = await getOrdersJumlahColumnMode(client);
      if (jumlahMode === 'plain') {
        await client.query(
          `UPDATE orders
           SET total = $1,
               jumlah = $2,
               updated_at = NOW()
           WHERE order_id = $3`,
          [orderTotal, jumlahRounded, order.order_id]
        );
      } else {
        await client.query(
          `UPDATE orders SET total = $1, updated_at = NOW() WHERE order_id = $2`,
          [orderTotal, order.order_id]
        );
      }
  
      // Commit the transaction before sending response
      await client.query('COMMIT');
  
      // Get order items for response (using new client since transaction committed)
      const itemsClient = await db.getClient();
      try {
        // Fetch the latest order row (including generated `jumlah`)
        const orderFreshResult = await itemsClient.query(
          `SELECT o.*, u.username AS created_by_username,
                  c.name as customer_name, c.phone as customer_phone, c.address as customer_address
           FROM orders o
           LEFT JOIN users u ON u.user_id = o.user_id
           LEFT JOIN customers c ON o.customer_id = c.customer_id
           WHERE o.order_id = $1
           LIMIT 1`,
          [order.order_id]
        );
        const orderFresh = orderFreshResult.rows[0] || order;
  
        // Fetch customer details for invoice/receipt display
        const orderItemsResult = await itemsClient.query(
          `SELECT oi.*, i.name as item_name, i.kode_produk as item_kode, i.material as item_material, i.purity as item_purity, i.weight as item_weight, i.kategori as item_kategori, i.jenis as item_jenis, i.tipe as item_tipe
           FROM order_items oi
           LEFT JOIN items i ON oi.item_id = i.item_id
           WHERE oi.order_id = $1`,
          [order.order_id]
        );
  
        const orderItems = orderItemsResult.rows.map(item => ({
          ...item,
          nama_item: item.nama_item || item.item_name,
          kode_produk: item.kode_produk || item.item_kode,
          material: item.material || item.item_material,
          purity: item.purity || item.item_purity,
          weight: item.weight || item.item_weight,
          kategori: item.kategori || item.item_kategori,
          jenis: item.jenis || item.item_jenis,
          tipe: item.tipe || item.item_tipe,
        }));
  
        const orderPayload = {
          ...orderFresh,
          total: orderTotal,
          items: orderItems,
          message: 'Order created successfully',
        };
        await storeIdempotentResponse(db, req, '/orders', 201, orderPayload);
        res.status(201).json(orderPayload);
      } finally {
        itemsClient.release();
      }
  
      // Update order total after response is sent
      process.nextTick(async () => {
        try {
          console.log('Starting async total update for order', order.order_id);
          const updateClient = await db.getClient();
          console.log('Got client for update');
          const updateResult = await updateClient.query(
            `UPDATE orders SET total = $1 WHERE order_id = $2`,
            [orderTotal, order.order_id]
          );
          console.log('UPDATE result:', updateResult.rowCount, 'rows affected');
          updateClient.release();
        } catch (err) {
          console.error('Failed to update order total:', err);
        }
      });
  
    } catch (error) {
      console.error('Error creating order:', {
        code: error?.code,
        message: error?.message,
        detail: error?.detail,
        table: error?.table,
        column: error?.column,
      });
      if (error && error.stack) {
        console.error(error.stack);
      }
  
      // Rollback transaction on error
      try {
        await client.query('ROLLBACK');
      } catch (rollbackError) {
        console.error('Error rolling back transaction:', rollbackError);
      }
  
      res.status(500).json({
        error: 'Internal server error',
        detail: formatDbErrorForClient(error),
      });
    } finally {
      client.release();
    }
  });

}

module.exports = { registerOrdersCreateRoutes };

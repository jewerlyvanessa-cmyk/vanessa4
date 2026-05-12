MIGRASI DATABASE — vanessa3 backend
====================================

1) File SQL di folder ini (backend/migrations/*.sql)
   - Biasanya dijalankan manual di PostgreSQL (psql / GUI) atau oleh skrip deploy tim.
   - Urutan: gunakan prefix tanggal pada nama file; jangan loncat versi.

2) node-pg-migrate (package.json: migrate:up / migrate:down)
   - Konfigurasi: backend/migrate.config.cjs
   - Folder migrasi JS: backend/migrations_js (terpisah dari file .sql di atas).

3) Kebijakan tim (pilih satu jalur)
   - Sumber kebenaran migrasi: file SQL di folder ini (backend/migrations/*.sql).
   - Urutan deploy: jalankan .sql sesuai prefix tanggal di psql / GUI / skrip deploy.
   - Folder backend/migrations_js + npm run migrate:up tetap ada untuk contoh / tooling
     node-pg-migrate; jangan menambah skema produksi di JS kecuali tim memutuskan
     pindah penuh ke JS (saat ini tidak).

4) Indeks performa (urutan disarankan)
   - 20260514_orders_daily_performance_indexes.sql — GET /api/orders/daily,
     dashboard order-today, snapshot.
   - 20260515_reporting_workshop_indexes.sql — laporan manajer
     (orders-completed-today) + workshop (dashboard / reports service|custom).
   - Jalankan di psql / GUI sesuai prefix tanggal (staging lalu prod).

5) Profiling dengan EXPLAIN (ANALYZE, BUFFERS)
   Ganti $BRANCH_ID dan sesuaikan tanggal. Tujuannya: cek "Seq Scan" besar,
   "Index Scan" / "Bitmap Index Scan", dan "Buffers: shared hit=" vs read.

   a) Pola order harian (setara orders/daily, satu cabang + tanggal):
      EXPLAIN (ANALYZE, BUFFERS)
      SELECT o.order_id
      FROM orders o
      WHERE o.branch_id = $BRANCH_ID
        AND (
          o.created_at::date = CURRENT_DATE
          OR EXISTS (
            SELECT 1 FROM payments p
            WHERE p.order_id = o.order_id AND p.status = 'completed'
              AND p.created_at::date = CURRENT_DATE
          )
        )
      ORDER BY o.created_at DESC
      LIMIT 200;

   b) Laporan manajer — completed hari ini (setara /reports/orders-completed-today):
      EXPLAIN (ANALYZE, BUFFERS)
      SELECT o.order_id, o.created_at
      FROM orders o
      WHERE o.status = 'completed'
        AND o.created_at::date = CURRENT_DATE
      ORDER BY o.created_at DESC
      LIMIT 100;

   c) Workshop reports — service/custom satu cabang + bulan berjalan:
      EXPLAIN (ANALYZE, BUFFERS)
      SELECT COUNT(*) FROM orders o
      WHERE o.branch_id = $BRANCH_ID
        AND o.order_type IN ('service', 'custom')
        AND o.created_at >= date_trunc('month', CURRENT_DATE);

   Jika masih sequential scan besar setelah indeks di atas, simpan output
   EXPLAIN dan tinjau kolom filter (mis. ekspresi DATE(...) vs rentang
   timestamp) sebelum menambah indeks baru.

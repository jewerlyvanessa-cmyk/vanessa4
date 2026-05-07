-- Backfill item_conditions for historical buyback orders
-- that do not yet have item condition rows.

BEGIN;

INSERT INTO item_conditions (
  item_id,
  order_id,
  kondisi_fisik,
  penyesuaian_berat,
  nilai_resale,
  harga_beli,
  harga_per_gram,
  potongan_kondisi,
  untung_rugi,
  nilai_untung_rugi,
  catatan_kondisi,
  foto_kondisi
)
SELECT
  oi.item_id,
  oi.order_id,
  'BAIK'::text AS kondisi_fisik,
  0::numeric AS penyesuaian_berat,
  COALESCE(oi.total, 0)::numeric AS nilai_resale,
  COALESCE(oi.subtotal, oi.total, 0)::numeric AS harga_beli,
  COALESCE(oi.harga_per_gram, 0)::numeric AS harga_per_gram,
  0::numeric AS potongan_kondisi,
  'UNTUNG'::text AS untung_rugi,
  0::numeric AS nilai_untung_rugi,
  'Backfill otomatis dari order_items (buyback lama).'::text AS catatan_kondisi,
  CASE
    WHEN oi.photo_produk IS NOT NULL AND TRIM(oi.photo_produk) <> ''
      THEN ARRAY[oi.photo_produk]::text[]
    ELSE ARRAY[]::text[]
  END AS foto_kondisi
FROM order_items oi
JOIN orders o ON o.order_id = oi.order_id
LEFT JOIN item_conditions ic
  ON ic.order_id = oi.order_id
 AND ic.item_id = oi.item_id
WHERE o.order_type = 'buyback'
  AND ic.condition_id IS NULL
  AND oi.item_id IS NOT NULL;

COMMIT;

-- Service/custom: cabang toko → antrian workshop (awaiting_warehouse) → workshop (sent-to-workshop).
-- confirmed = DP sudah dibayar di kasir, menunggu admin toko kirim ke workshop (UI).

BEGIN;

ALTER TABLE IF EXISTS orders
  DROP CONSTRAINT IF EXISTS orders_status_check;

ALTER TABLE IF EXISTS orders
  ADD CONSTRAINT orders_status_check CHECK (
    status IN (
      'draft',
      'pending',
      'confirmed',
      'ready_for_payment',
      'completed',
      'picked_up',
      'cancelled',
      'buyback',
      'delivered',
      'sold',
      'awaiting_warehouse',
      'sent-to-workshop',
      'in_workshop',
      'repairing',
      'polishing',
      'custom_work',
      'done_workshop',
      'ready_for_pickup'
    )
  );

COMMIT;

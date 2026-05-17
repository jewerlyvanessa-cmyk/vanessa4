-- Order service/custom sudah dikonfirmasi admin toko: kembalikan branch_id ke cabang toko asal.

BEGIN;

DO $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'orders'
      AND column_name = 'metadata'
  ) THEN
    UPDATE orders o
    SET
      branch_id = (NULLIF(BTRIM(o.metadata->>'service_origin_branch_id'), ''))::bigint,
      updated_at = NOW()
    WHERE o.order_type::text IN ('service', 'custom')
      AND o.status::text = 'ready_for_pickup'
      AND COALESCE(NULLIF(BTRIM(o.metadata->>'store_receipt_confirmed_at'), ''), '') <> ''
      AND COALESCE(NULLIF(BTRIM(o.metadata->>'service_origin_branch_id'), ''), '') ~ '^[0-9]+$'
      AND o.branch_id::bigint IS DISTINCT FROM (
        NULLIF(BTRIM(o.metadata->>'service_origin_branch_id'), '')
      )::bigint;
  END IF;
END $$;

COMMIT;

-- Order ready_for_pickup yang branch_id sudah kembali ke toko asal tetapi belum ada store_receipt_confirmed_at.

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
      metadata = COALESCE(o.metadata, '{}'::jsonb) || jsonb_build_object(
        'store_receipt_confirmed_at',
        COALESCE(
          NULLIF(BTRIM(o.metadata->>'store_receipt_confirmed_at'), ''),
          to_char(COALESCE(o.updated_at, NOW()) AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"')
        )
      ),
      updated_at = NOW()
    WHERE o.order_type::text IN ('service', 'custom')
      AND o.status::text = 'ready_for_pickup'
      AND COALESCE(NULLIF(BTRIM(o.metadata->>'store_receipt_confirmed_at'), ''), '') = ''
      AND COALESCE(NULLIF(BTRIM(o.metadata->>'service_origin_branch_id'), ''), '') ~ '^[0-9]+$'
      AND o.branch_id::bigint = (
        NULLIF(BTRIM(o.metadata->>'service_origin_branch_id'), '')
      )::bigint;
  END IF;
END $$;

COMMIT;

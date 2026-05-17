-- Order service/custom yang sudah disetujui workshop: selaraskan branch_id dengan cabang workshop
-- agar muncul di GET /workshop-orders (antrian) walau metadata tidak terbaca.

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
      branch_id = (NULLIF(BTRIM(o.metadata->>'service_workshop_branch_id'), ''))::bigint,
      pickup_branch_id = COALESCE(
        o.pickup_branch_id,
        (NULLIF(BTRIM(o.metadata->>'service_origin_branch_id'), ''))::bigint
      ),
      updated_at = NOW()
    WHERE o.order_type::text IN ('service', 'custom')
      AND o.status::text IN (
        'sent-to-workshop',
        'in_workshop',
        'repairing',
        'polishing',
        'custom_work'
      )
      AND o.metadata IS NOT NULL
      AND COALESCE(NULLIF(BTRIM(o.metadata->>'service_workshop_branch_id'), ''), '') ~ '^[0-9]+$'
      AND o.branch_id::bigint IS DISTINCT FROM (
        NULLIF(BTRIM(o.metadata->>'service_workshop_branch_id'), '')
      )::bigint;
  END IF;
END $$;

COMMIT;

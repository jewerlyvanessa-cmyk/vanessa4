-- Migration: Add payments.validated_by to track who validated payment
-- Date: 2026-05-02

BEGIN;

ALTER TABLE payments
  ADD COLUMN IF NOT EXISTS validated_by BIGINT;

-- Optional FK (only if users table exists with user_id)
DO $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM information_schema.tables
    WHERE table_schema = 'public'
      AND table_name = 'users'
  ) THEN
    BEGIN
      ALTER TABLE payments
        ADD CONSTRAINT payments_validated_by_fkey
        FOREIGN KEY (validated_by) REFERENCES users(user_id)
        ON DELETE SET NULL;
    EXCEPTION
      WHEN duplicate_object THEN
        -- constraint already exists
        NULL;
    END;
  END IF;
END $$;

CREATE INDEX IF NOT EXISTS idx_payments_validated_by ON payments(validated_by);

COMMIT;


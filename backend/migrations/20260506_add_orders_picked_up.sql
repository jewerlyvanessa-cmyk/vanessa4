-- Migration: Add picked-up fields + status for service/custom pickup flow
-- Date: 2026-05-06

ALTER TABLE orders
  ADD COLUMN IF NOT EXISTS picked_up_at TIMESTAMP,
  ADD COLUMN IF NOT EXISTS picked_up_by INTEGER,
  ADD COLUMN IF NOT EXISTS picked_up_notes TEXT,
  ADD COLUMN IF NOT EXISTS picked_up_photo_url TEXT;

-- Ensure the status constraint includes picked_up (some deployments use orders_status_check)
ALTER TABLE orders DROP CONSTRAINT IF EXISTS orders_status_check;
ALTER TABLE orders ADD CONSTRAINT orders_status_check
CHECK (status IN ('draft', 'pending', 'completed', 'picked_up', 'cancelled'));

COMMIT;


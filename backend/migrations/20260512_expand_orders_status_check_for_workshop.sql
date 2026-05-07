-- Expand orders status constraint for workshop flow statuses.
-- Safe for repeated runs.

BEGIN;

ALTER TABLE IF EXISTS orders
  DROP CONSTRAINT IF EXISTS orders_status_check;

ALTER TABLE IF EXISTS orders
  ADD CONSTRAINT orders_status_check CHECK (
    status IN (
      'draft',
      'pending',
      'completed',
      'picked_up',
      'cancelled',
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

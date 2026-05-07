-- Store service/custom estimates in orders and actual costs in revision table.
-- Safe for repeated runs.

BEGIN;

ALTER TABLE IF EXISTS orders
  ADD COLUMN IF NOT EXISTS estimate_amount NUMERIC(14, 2),
  ADD COLUMN IF NOT EXISTS estimate_due_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS estimate_duration_text TEXT,
  ADD COLUMN IF NOT EXISTS estimate_notes TEXT;

CREATE TABLE IF NOT EXISTS order_cost_breakdowns (
  breakdown_id BIGSERIAL PRIMARY KEY,
  order_id BIGINT NOT NULL REFERENCES orders(order_id) ON DELETE CASCADE,
  revision INTEGER NOT NULL,
  material_cost NUMERIC(14, 2) NOT NULL DEFAULT 0,
  labor_cost NUMERIC(14, 2) NOT NULL DEFAULT 0,
  other_cost NUMERIC(14, 2) NOT NULL DEFAULT 0,
  notes TEXT,
  created_by BIGINT REFERENCES users(user_id),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT order_cost_breakdowns_revision_unique UNIQUE (order_id, revision),
  CONSTRAINT order_cost_breakdowns_non_negative_costs CHECK (
    material_cost >= 0 AND labor_cost >= 0 AND other_cost >= 0
  )
);

CREATE INDEX IF NOT EXISTS idx_order_cost_breakdowns_order_created_at
  ON order_cost_breakdowns(order_id, created_at DESC);

COMMIT;

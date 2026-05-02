-- Migration: Add payments.proof_url for payment proof photos
-- Date: 2026-05-01

BEGIN;

ALTER TABLE payments
  ADD COLUMN IF NOT EXISTS proof_url TEXT;

CREATE INDEX IF NOT EXISTS idx_payments_proof_url ON payments(proof_url);

COMMIT;


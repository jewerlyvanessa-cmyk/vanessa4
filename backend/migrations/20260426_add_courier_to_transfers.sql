-- Migration: Add courier column to transfers
-- Date: 2026-04-26
-- Description: Track courier/driver for shipment

BEGIN;

ALTER TABLE transfers
  ADD COLUMN IF NOT EXISTS courier TEXT;

COMMIT;


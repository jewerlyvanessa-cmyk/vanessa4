-- Migration: Expand allowed transfers.source_type values
-- Description: Allow transfer source from service/custom orders.

ALTER TABLE transfers
  DROP CONSTRAINT IF EXISTS transfers_source_type_check;

ALTER TABLE transfers
  ADD CONSTRAINT transfers_source_type_check
  CHECK (source_type IN ('stok', 'buyback', 'service', 'custom'));

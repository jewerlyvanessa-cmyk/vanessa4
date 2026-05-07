-- Foto bukti pada catatan keuangan toko
-- Date: 2026-05-09

ALTER TABLE store_operational_entries
  ADD COLUMN IF NOT EXISTS proof_photo_url TEXT;


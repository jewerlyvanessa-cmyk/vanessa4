-- Drop legacy columns from item_conditions table.
-- Safe for repeated runs.

BEGIN;

ALTER TABLE IF EXISTS item_conditions
  DROP COLUMN IF EXISTS berat_awal,
  DROP COLUMN IF EXISTS berat_akhir,
  DROP COLUMN IF EXISTS keaslian,
  DROP COLUMN IF EXISTS sertifikat,
  DROP COLUMN IF EXISTS dinilai_oleh,
  DROP COLUMN IF EXISTS tanggal_penilaian;

COMMIT;

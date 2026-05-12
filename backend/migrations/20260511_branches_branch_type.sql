-- Tipe cabang: operasional / pelabelan (bukan pengganti user_branch_roles).
-- Nilai: toko | warehouse | workshop | pusat

ALTER TABLE branches
  ADD COLUMN IF NOT EXISTS branch_type TEXT NOT NULL DEFAULT 'toko';

DO $$
BEGIN
  ALTER TABLE branches
    ADD CONSTRAINT branches_branch_type_check
    CHECK (branch_type IN ('toko', 'warehouse', 'workshop', 'pusat'));
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;

COMMENT ON COLUMN branches.branch_type IS
  'toko=etalase; warehouse=gudang/stok pusat; workshop=bengkel; pusat=kantor/HQ';

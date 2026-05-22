-- Kategori pencatatan keuangan (manajer). Aman dijalankan berulang.

CREATE TABLE IF NOT EXISTS store_operational_categories (
  category_id BIGSERIAL PRIMARY KEY,
  name TEXT NOT NULL,
  entry_kind TEXT NOT NULL DEFAULT 'expense'
    CHECK (entry_kind IN ('expense', 'income')),
  sort_order INT NOT NULL DEFAULT 0,
  is_active BOOLEAN NOT NULL DEFAULT TRUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_store_ops_cat_kind_name
  ON store_operational_categories (entry_kind, lower(btrim(name)));

INSERT INTO store_operational_categories (name, entry_kind, sort_order)
SELECT v.name, v.entry_kind, v.sort_order
FROM (VALUES
  ('ATK & perlengkapan', 'expense', 10),
  ('Listrik / utilitas', 'expense', 20),
  ('Air', 'expense', 30),
  ('Transport / kirim', 'expense', 40),
  ('Konsumsi', 'expense', 50),
  ('Maintenance & perbaikan', 'expense', 60),
  ('Lainnya (pengeluaran)', 'expense', 70),
  ('Pendapatan lain (bukan order)', 'income', 10),
  ('Pengembalian / koreksi kas (+)', 'income', 20),
  ('Pendapatan jasa / komisi', 'income', 30),
  ('Lainnya (pemasukan)', 'income', 40)
) AS v(name, entry_kind, sort_order)
WHERE NOT EXISTS (SELECT 1 FROM store_operational_categories LIMIT 1);

-- =============================================================================
-- Vanessa3 — Skema database PostgreSQL (database baru, tanpa data)
-- =============================================================================
-- Cara pakai:
--   createdb -U postgres vanessa_store
--   psql -U postgres -d vanessa_store -f backend/sql/vanessa3_schema_new_database.sql
--
-- Setelah ini: isi data awal (cabang, user superadmin) atau restore dari pg_dump data.
-- Untuk salin struktur + data dari server lama: gunakan pg_dump (lihat PANDUAN_EXPORT_SERVER_BARU.md)
-- =============================================================================

BEGIN;

-- -----------------------------------------------------------------------------
-- Fungsi utilitas
-- -----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION round_to_nearest_5000(amount NUMERIC)
RETURNS NUMERIC
LANGUAGE plpgsql
AS $$
DECLARE
  modulo_10000 NUMERIC;
BEGIN
  modulo_10000 := amount % 10000;
  IF modulo_10000 = 5000 THEN
    RETURN amount;
  ELSIF modulo_10000 < 5000 THEN
    RETURN amount - modulo_10000 + 5000;
  ELSE
    RETURN amount - modulo_10000 + 10000;
  END IF;
END;
$$;

CREATE OR REPLACE FUNCTION terbilang(n BIGINT)
RETURNS TEXT
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
  satuan TEXT[] := ARRAY['', 'satu', 'dua', 'tiga', 'empat', 'lima', 'enam', 'tujuh', 'delapan', 'sembilan'];
  hasil TEXT := '';
BEGIN
  IF n = 0 THEN
    RETURN 'nol rupiah';
  ELSIF n < 10 THEN
    hasil := satuan[n + 1];
  ELSIF n < 20 THEN
    hasil := satuan[n - 10 + 1] || ' belas';
  ELSIF n < 100 THEN
    hasil := satuan[(n / 10)::INT + 1] || ' puluh ' || satuan[(n % 10) + 1];
  ELSIF n < 200 THEN
    hasil := 'seratus ' || terbilang(n - 100);
  ELSIF n < 1000 THEN
    hasil := satuan[(n / 100)::INT + 1] || ' ratus ' || terbilang(n % 100);
  ELSIF n < 2000 THEN
    hasil := 'seribu ' || terbilang(n - 1000);
  ELSIF n < 1000000 THEN
    hasil := terbilang(n / 1000) || ' ribu ' || terbilang(n % 1000);
  ELSIF n < 1000000000 THEN
    hasil := terbilang(n / 1000000) || ' juta ' || terbilang(n % 1000000);
  ELSE
    hasil := 'terlalu besar';
  END IF;
  RETURN trim(hasil) || ' rupiah';
END;
$$;

CREATE OR REPLACE FUNCTION update_item_conditions_updated_at()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$;

CREATE SEQUENCE IF NOT EXISTS order_nota_seq START 1 INCREMENT 1 MINVALUE 1 NO CYCLE;

CREATE OR REPLACE FUNCTION generate_nota_order(
  p_branch_id BIGINT,
  p_order_type TEXT
)
RETURNS TEXT
LANGUAGE plpgsql
AS $$
DECLARE
  v_initial TEXT;
  v_code TEXT;
  v_order_code TEXT;
  v_seq BIGINT;
BEGIN
  SELECT initials, code
  INTO v_initial, v_code
  FROM branches
  WHERE branch_id = p_branch_id;

  v_order_code := CASE p_order_type
    WHEN 'jual' THEN 'JL'
    WHEN 'buyback' THEN 'BB'
    WHEN 'service' THEN 'SV'
    WHEN 'custom' THEN 'CT'
    ELSE NULL
  END;

  IF v_order_code IS NULL THEN
    RAISE EXCEPTION 'Invalid order_type: %', p_order_type;
  END IF;

  v_seq := nextval('order_nota_seq');

  RETURN COALESCE(NULLIF(TRIM(v_initial), ''), 'XX')
    || '-'
    || COALESCE(NULLIF(TRIM(v_code), ''), 'BR')
    || '-'
    || v_order_code
    || '-'
    || LPAD(v_seq::TEXT, 8, '0');
END;
$$;

-- -----------------------------------------------------------------------------
-- Cabang & pengguna
-- -----------------------------------------------------------------------------

CREATE TABLE branches (
  branch_id         BIGSERIAL PRIMARY KEY,
  name              TEXT NOT NULL,
  code              TEXT NOT NULL UNIQUE,
  alias             TEXT,
  initials          TEXT,
  address           TEXT,
  phone_number      TEXT,
  status            TEXT NOT NULL DEFAULT 'active'
    CHECK (status IN ('active', 'inactive')),
  branch_type       TEXT NOT NULL DEFAULT 'toko'
    CHECK (branch_type IN ('toko', 'warehouse', 'workshop', 'pusat')),
  logo_url          TEXT,
  created_at        TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at        TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_branches_name ON branches (name);
CREATE INDEX idx_branches_initials ON branches (initials);

CREATE TABLE users (
  user_id       BIGSERIAL PRIMARY KEY,
  username      TEXT NOT NULL UNIQUE,
  password_hash TEXT NOT NULL,
  status        TEXT NOT NULL DEFAULT 'active'
    CHECK (status IN ('active', 'inactive')),
  created_at    TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at    TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_users_status ON users (status);

CREATE TABLE user_branch_roles (
  id         BIGSERIAL PRIMARY KEY,
  user_id    BIGINT NOT NULL REFERENCES users (user_id) ON DELETE CASCADE,
  branch_id  BIGINT NOT NULL REFERENCES branches (branch_id) ON DELETE CASCADE,
  role       TEXT NOT NULL
    CHECK (role IN (
      'cs', 'kasir', 'admin_toko', 'admin_workshop', 'admin_warehouse',
      'tukang', 'manajer', 'superadmin', 'stockist', 'owner'
    )),
  is_primary BOOLEAN NOT NULL DEFAULT FALSE,
  UNIQUE (user_id, branch_id, role)
);

CREATE INDEX idx_user_branch_roles_user_id ON user_branch_roles (user_id);
CREATE INDEX idx_user_branch_roles_branch_id ON user_branch_roles (branch_id);
CREATE INDEX idx_user_branch_roles_role ON user_branch_roles (role);

-- -----------------------------------------------------------------------------
-- Pelanggan & stok
-- -----------------------------------------------------------------------------

CREATE TABLE customers (
  customer_id BIGSERIAL PRIMARY KEY,
  name        TEXT NOT NULL,
  phone       TEXT,
  address     TEXT,
  branch_id   BIGINT REFERENCES branches (branch_id) ON DELETE SET NULL,
  metadata    JSONB,
  created_at  TIMESTAMP NOT NULL DEFAULT NOW(),
  updated_at  TIMESTAMP NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_customers_phone ON customers (phone);
CREATE INDEX idx_customers_name ON customers (name);
CREATE INDEX idx_customers_branch_id ON customers (branch_id);

CREATE TABLE items (
  item_id      BIGSERIAL PRIMARY KEY,
  branch_id    BIGINT NOT NULL REFERENCES branches (branch_id),
  kode_produk  TEXT NOT NULL,
  kategori     TEXT,
  jenis        TEXT,
  tipe         TEXT,
  name         TEXT NOT NULL,
  material     TEXT,
  purity       TEXT,
  weight       NUMERIC,
  quantity     INTEGER NOT NULL DEFAULT 1,
  status       TEXT NOT NULL,
  ownership    TEXT NOT NULL DEFAULT 'unknown'
    CHECK (ownership IN ('toko', 'pelanggan', 'unknown')),
  stock_type   TEXT NOT NULL DEFAULT 'non_inventory'
    CHECK (stock_type IN ('inventory', 'non_inventory')),
  is_quick_registered BOOLEAN NOT NULL DEFAULT FALSE,
  is_estimated BOOLEAN NOT NULL DEFAULT FALSE,
  photo_produk TEXT,
  source       TEXT NOT NULL DEFAULT 'manual',
  metadata     JSONB,
  created_by   BIGINT REFERENCES users (user_id) ON DELETE SET NULL,
  created_at   TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at   TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  UNIQUE (branch_id, kode_produk)
);

CREATE INDEX idx_items_branch_id ON items (branch_id);
CREATE INDEX idx_items_status ON items (status);
CREATE INDEX idx_items_kategori ON items (kategori);
CREATE INDEX idx_items_kode_produk ON items (kode_produk);
CREATE INDEX idx_items_ownership ON items (ownership);

-- -----------------------------------------------------------------------------
-- Order & pembayaran
-- -----------------------------------------------------------------------------

CREATE TABLE orders (
  order_id              BIGSERIAL PRIMARY KEY,
  order_type            TEXT NOT NULL
    CHECK (order_type IN ('jual', 'buyback', 'service', 'custom')),
  order_number          TEXT UNIQUE,
  branch_id             BIGINT NOT NULL REFERENCES branches (branch_id),
  user_id               BIGINT NOT NULL REFERENCES users (user_id),
  customer_id           BIGINT REFERENCES customers (customer_id) ON DELETE SET NULL,
  pickup_branch_id      BIGINT REFERENCES branches (branch_id) ON DELETE SET NULL,
  mode                  VARCHAR,
  diskon                NUMERIC(5, 2) DEFAULT 0,
  total                 NUMERIC(15, 2) NOT NULL DEFAULT 0,
  jumlah                NUMERIC GENERATED ALWAYS AS (
    CEIL((COALESCE(total, 0)) / 5000) * 5000
  ) STORED,
  status                TEXT NOT NULL DEFAULT 'draft'
    CHECK (status IN (
      'draft', 'pending', 'confirmed', 'ready_for_payment', 'completed',
      'picked_up', 'cancelled', 'buyback', 'delivered', 'sold',
      'awaiting_warehouse', 'sent-to-workshop', 'in_workshop', 'repairing',
      'polishing', 'custom_work', 'done_workshop', 'ready_for_pickup'
    )),
  metadata              JSONB NOT NULL DEFAULT '{}'::JSONB,
  estimate_amount       NUMERIC(14, 2),
  estimate_due_at       TIMESTAMPTZ,
  estimate_duration_text TEXT,
  estimate_notes        TEXT,
  picked_up_at          TIMESTAMP,
  picked_up_by          BIGINT REFERENCES users (user_id) ON DELETE SET NULL,
  picked_up_notes       TEXT,
  picked_up_photo_url   TEXT,
  created_at            TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at            TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_orders_branch_id ON orders (branch_id);
CREATE INDEX idx_orders_user_id ON orders (user_id);
CREATE INDEX idx_orders_customer_id ON orders (customer_id);
CREATE INDEX idx_orders_order_number ON orders (order_number);
CREATE INDEX idx_orders_branch_created_at ON orders (branch_id, created_at DESC);
CREATE INDEX idx_orders_branch_user_created_at ON orders (branch_id, user_id, created_at DESC);
CREATE INDEX idx_orders_status_created_at_desc ON orders (status, created_at DESC);
CREATE INDEX idx_orders_branch_service_custom_created_at
  ON orders (branch_id, created_at DESC)
  WHERE order_type IN ('service', 'custom');

CREATE TABLE order_items (
  order_item_id  BIGSERIAL PRIMARY KEY,
  order_id       BIGINT NOT NULL REFERENCES orders (order_id) ON DELETE CASCADE,
  item_id        BIGINT REFERENCES items (item_id) ON DELETE SET NULL,
  nama_item      TEXT,
  kode_produk    TEXT,
  qty            INTEGER NOT NULL DEFAULT 1,
  weight         NUMERIC(10, 2) NOT NULL,
  harga_per_gram NUMERIC(10, 2) NOT NULL,
  material       TEXT,
  purity         TEXT,
  kategori       TEXT,
  jenis          TEXT,
  tipe           TEXT,
  subtotal       NUMERIC(10, 2),
  total          NUMERIC(10, 2),
  diskon         NUMERIC(10, 2) DEFAULT 0,
  jumlah         NUMERIC GENERATED ALWAYS AS (
    CEIL((qty * weight * harga_per_gram * (1 - COALESCE(diskon, 0) / 100)) / 5000) * 5000
  ) STORED,
  kondisi_barang JSONB,
  photo_produk   TEXT,
  created_at     TIMESTAMP NOT NULL DEFAULT NOW(),
  updated_at     TIMESTAMP NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_order_items_order_id ON order_items (order_id);
CREATE INDEX idx_order_items_item_id ON order_items (item_id);

CREATE TABLE order_cost_breakdowns (
  breakdown_id   BIGSERIAL PRIMARY KEY,
  order_id       BIGINT NOT NULL REFERENCES orders (order_id) ON DELETE CASCADE,
  revision       INTEGER NOT NULL,
  material_cost  NUMERIC(14, 2) NOT NULL DEFAULT 0,
  labor_cost     NUMERIC(14, 2) NOT NULL DEFAULT 0,
  other_cost     NUMERIC(14, 2) NOT NULL DEFAULT 0,
  notes          TEXT,
  created_by     BIGINT REFERENCES users (user_id) ON DELETE SET NULL,
  created_at     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT order_cost_breakdowns_revision_unique UNIQUE (order_id, revision),
  CONSTRAINT order_cost_breakdowns_non_negative_costs CHECK (
    material_cost >= 0 AND labor_cost >= 0 AND other_cost >= 0
  )
);

CREATE INDEX idx_order_cost_breakdowns_order_created_at
  ON order_cost_breakdowns (order_id, created_at DESC);

CREATE TABLE payments (
  payment_id         BIGSERIAL PRIMARY KEY,
  order_id           BIGINT NOT NULL REFERENCES orders (order_id) ON DELETE CASCADE,
  amount             NUMERIC NOT NULL,
  method             TEXT NOT NULL
    CHECK (method IN ('cash', 'transfer', 'qris', 'e-wallet')),
  status             TEXT NOT NULL DEFAULT 'pending'
    CHECK (status IN ('pending', 'completed', 'failed', 'cancelled')),
  payment_date       TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  notes              TEXT,
  proof_url          TEXT,
  revenue_branch_id  BIGINT REFERENCES branches (branch_id) ON DELETE SET NULL,
  validated_by       BIGINT REFERENCES users (user_id) ON DELETE SET NULL,
  created_at         TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at         TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_payments_order_id ON payments (order_id);
CREATE INDEX idx_payments_payment_date ON payments (payment_date);
CREATE INDEX idx_payments_validated_by ON payments (validated_by);
CREATE INDEX idx_payments_revenue_branch_id ON payments (revenue_branch_id);
CREATE INDEX idx_payments_order_completed_created
  ON payments (order_id, created_at)
  WHERE status = 'completed';

-- -----------------------------------------------------------------------------
-- Kondisi buyback
-- -----------------------------------------------------------------------------

CREATE TABLE item_conditions (
  condition_id       BIGSERIAL PRIMARY KEY,
  item_id            BIGINT REFERENCES items (item_id) ON DELETE CASCADE,
  order_id           BIGINT REFERENCES orders (order_id) ON DELETE CASCADE,
  kondisi_fisik      TEXT
    CHECK (kondisi_fisik IS NULL OR kondisi_fisik IN (
      'BAIK', 'RUSAK_RINGAN', 'RUSAK_BERAT', 'RUSAK_PARAH'
    )),
  penyesuaian_berat  TEXT,
  nilai_resale       BIGINT,
  harga_per_gram     NUMERIC(15, 2),
  potongan_kondisi   NUMERIC(15, 2) DEFAULT 0,
  untung_rugi        VARCHAR(20),
  nilai_untung_rugi  NUMERIC(15, 2) DEFAULT 0,
  catatan_kondisi    TEXT,
  foto_kondisi       TEXT[],
  created_at         TIMESTAMP NOT NULL DEFAULT NOW(),
  updated_at         TIMESTAMP NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_item_conditions_item_id ON item_conditions (item_id);
CREATE INDEX idx_item_conditions_order_id ON item_conditions (order_id);

CREATE TRIGGER trg_item_conditions_updated_at
  BEFORE UPDATE ON item_conditions
  FOR EACH ROW
  EXECUTE FUNCTION update_item_conditions_updated_at();

-- -----------------------------------------------------------------------------
-- Transfer & mutasi stok
-- -----------------------------------------------------------------------------

CREATE TABLE transfers (
  transfer_id     BIGSERIAL PRIMARY KEY,
  from_branch_id  BIGINT REFERENCES branches (branch_id) ON DELETE SET NULL,
  to_branch_id    BIGINT REFERENCES branches (branch_id) ON DELETE SET NULL,
  item_name       TEXT NOT NULL,
  quantity        INTEGER NOT NULL,
  source_type     TEXT NOT NULL DEFAULT 'stok'
    CHECK (source_type IN ('stok', 'buyback', 'service', 'custom')),
  courier         TEXT,
  notes           TEXT,
  order_id        BIGINT REFERENCES orders (order_id) ON DELETE SET NULL,
  status          TEXT NOT NULL DEFAULT 'pending'
    CHECK (status IN ('pending', 'approved', 'completed', 'rejected')),
  created_by      BIGINT REFERENCES users (user_id) ON DELETE SET NULL,
  approved_by     BIGINT REFERENCES users (user_id) ON DELETE SET NULL,
  created_at      TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at      TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_transfers_from_branch ON transfers (from_branch_id);
CREATE INDEX idx_transfers_to_branch ON transfers (to_branch_id);
CREATE INDEX idx_transfers_status ON transfers (status);
CREATE INDEX idx_transfers_created_at ON transfers (created_at);

CREATE TABLE stock_mutations (
  mutation_id     BIGSERIAL PRIMARY KEY,
  item_id         BIGINT REFERENCES items (item_id) ON DELETE SET NULL,
  branch_id       BIGINT REFERENCES branches (branch_id) ON DELETE SET NULL,
  type            TEXT NOT NULL
    CHECK (type IN ('in', 'out', 'transfer', 'adjustment')),
  quantity        INTEGER NOT NULL,
  previous_stock  INTEGER,
  current_stock   INTEGER,
  notes           TEXT,
  reference_id    BIGINT,
  reference_type  TEXT,
  created_by      BIGINT REFERENCES users (user_id) ON DELETE SET NULL,
  created_at      TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_stock_mutations_item_id ON stock_mutations (item_id);
CREATE INDEX idx_stock_mutations_branch_id ON stock_mutations (branch_id);

CREATE TABLE stock_history (
  history_id  BIGSERIAL PRIMARY KEY,
  item_id     BIGINT REFERENCES items (item_id) ON DELETE CASCADE,
  old_status  TEXT NOT NULL,
  new_status  TEXT NOT NULL,
  changed_by  BIGINT REFERENCES users (user_id) ON DELETE SET NULL,
  notes       TEXT,
  created_at  TIMESTAMP NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_stock_history_item_id ON stock_history (item_id);

-- -----------------------------------------------------------------------------
-- Upload & operasional toko
-- -----------------------------------------------------------------------------

CREATE TABLE uploads (
  upload_id           BIGSERIAL PRIMARY KEY,
  storage_key         TEXT NOT NULL UNIQUE,
  original_name       TEXT,
  mime_type           TEXT,
  size_bytes          BIGINT,
  url_path            TEXT,
  uploaded_by_user_id BIGINT REFERENCES users (user_id) ON DELETE SET NULL,
  created_at          TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_uploads_uploaded_by_user_id ON uploads (uploaded_by_user_id);
CREATE INDEX idx_uploads_created_at ON uploads (created_at);

CREATE TABLE store_operational_entries (
  entry_id        BIGSERIAL PRIMARY KEY,
  branch_id       BIGINT NOT NULL REFERENCES branches (branch_id) ON DELETE CASCADE,
  user_id         BIGINT REFERENCES users (user_id) ON DELETE SET NULL,
  amount          NUMERIC(15, 2) NOT NULL CHECK (amount > 0),
  category        TEXT NOT NULL,
  notes           TEXT,
  entry_kind      TEXT NOT NULL DEFAULT 'expense'
    CHECK (entry_kind IN ('expense', 'income')),
  proof_photo_url TEXT,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_store_ops_branch_created
  ON store_operational_entries (branch_id, created_at DESC);

-- -----------------------------------------------------------------------------
-- Komentar dokumentasi
-- -----------------------------------------------------------------------------

COMMENT ON TABLE branches IS 'Cabang: toko, warehouse, workshop, pusat';
COMMENT ON TABLE items IS 'Inventori per cabang; kode_produk unik per branch_id';
COMMENT ON TABLE orders IS 'Transaksi jual, buyback, service, custom';
COMMENT ON TABLE order_cost_breakdowns IS 'Revisi biaya aktual order service/custom';
COMMENT ON TABLE store_operational_entries IS 'Pengeluaran/pendapatan operasional toko';

COMMIT;

-- =============================================================================
-- Data awal minimal (opsional — hapus jika tidak perlu)
-- =============================================================================
-- Password contoh: ganti setelah deploy (hash bcrypt untuk "admin123")
/*
INSERT INTO branches (name, code, alias, initials, branch_type, status)
VALUES ('Pusat', 'PST', 'Pusat', 'PS', 'pusat', 'active');

INSERT INTO users (username, password_hash, status)
VALUES ('superadmin', '$2b$10$REPLACE_WITH_BCRYPT_HASH', 'active');

INSERT INTO user_branch_roles (user_id, branch_id, role, is_primary)
VALUES (1, 1, 'superadmin', TRUE);
*/

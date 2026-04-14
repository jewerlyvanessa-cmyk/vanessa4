-- Skema untuk tabel users
CREATE TABLE users (
    user_id BIGSERIAL PRIMARY KEY,
    username TEXT UNIQUE NOT NULL,
    password_hash TEXT NOT NULL,
    status TEXT NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Skema untuk tabel branches
CREATE TABLE branches (
    branch_id BIGSERIAL PRIMARY KEY,
    name TEXT NOT NULL,
    code TEXT UNIQUE NOT NULL,
    alias TEXT,
    initials TEXT,
    address TEXT,
    phone_number TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Skema untuk tabel user_branch_roles
CREATE TABLE user_branch_roles (
    id BIGSERIAL PRIMARY KEY,
    user_id BIGINT REFERENCES users(user_id),
    branch_id BIGINT REFERENCES branches(branch_id),
    role TEXT NOT NULL,
    is_primary BOOLEAN DEFAULT FALSE
);

-- Skema untuk tabel items (FINAL)
CREATE TABLE items (
  item_id BIGSERIAL PRIMARY KEY,

  -- Business Identifier
  item_code TEXT,
  item_code_source TEXT DEFAULT 'internal',
  qr_code TEXT UNIQUE,

  -- Basic Info
  name TEXT NOT NULL,
  weight NUMERIC(10,2),
  quantity INTEGER DEFAULT 1,
  material TEXT,
  purity TEXT,

  kategori TEXT,
  jenis TEXT,
  tipe TEXT,

  -- Ownership & Stock
  ownership TEXT CHECK (ownership IN ('toko','pelanggan','unknown')) DEFAULT 'unknown',
  stock_type TEXT CHECK (stock_type IN ('inventory','non_inventory')) DEFAULT 'non_inventory',

  -- Lifecycle
  status TEXT NOT NULL,
  is_quick_registered BOOLEAN DEFAULT FALSE,
  is_estimated BOOLEAN DEFAULT FALSE,

  branch_id BIGINT REFERENCES branches(branch_id),

  -- Media & Metadata
  photo_url TEXT,
  source TEXT DEFAULT 'manual',
  metadata JSONB,

  created_at TIMESTAMP DEFAULT now(),
  updated_at TIMESTAMP DEFAULT now()
);

CREATE UNIQUE INDEX uq_item_code_branch
ON items(branch_id, item_code)
WHERE item_code IS NOT NULL;

-- Skema untuk tabel orders (FINAL)
CREATE TABLE orders (
  order_id BIGSERIAL PRIMARY KEY,
  order_type TEXT CHECK (order_type IN ('jual','buyback','service','custom')),
  item_id BIGINT REFERENCES items(item_id),
  customer_id BIGINT REFERENCES customers(customer_id),

  -- Status workflow
  status TEXT CHECK (
    status IN ('draft','submitted','in_progress','done','cancelled')
  ) DEFAULT 'draft',

  -- Nota / Invoice
  nota_order TEXT UNIQUE,

  branch_id BIGINT REFERENCES branches(branch_id),

  created_at TIMESTAMP DEFAULT now(),
  updated_at TIMESTAMP DEFAULT now()
);

-- Skema untuk tabel stock_history
CREATE TABLE stock_history (
  history_id BIGSERIAL PRIMARY KEY,
  item_id BIGINT REFERENCES items(item_id),
  old_status TEXT,
  new_status TEXT,
  changed_by BIGINT REFERENCES users(user_id),
  notes TEXT,
  created_at TIMESTAMP DEFAULT now()
);

-- Skema untuk tabel customers (diperlukan untuk orders)
CREATE TABLE customers (
    customer_id BIGSERIAL PRIMARY KEY,
    name TEXT NOT NULL,
    phone TEXT,
    address TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Sequence & Function Nota Order
CREATE SEQUENCE order_nota_seq
START 1
INCREMENT 1
MINVALUE 1
NO CYCLE;

CREATE OR REPLACE FUNCTION generate_nota_order(
  p_branch_id BIGINT,
  p_order_type TEXT
)
RETURNS TEXT AS $$
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

  RETURN v_initial || '-' || v_code || '-' || v_order_code || '-' || LPAD(v_seq::TEXT, 8, '0');
END;
$$ LANGUAGE plpgsql;

-- Trigger: Cegah Update Nota Order
CREATE OR REPLACE FUNCTION prevent_nota_order_update()
RETURNS TRIGGER AS $$
BEGIN
  IF OLD.nota_order IS NOT NULL AND NEW.nota_order <> OLD.nota_order THEN
    RAISE EXCEPTION 'nota_order cannot be modified';
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_prevent_nota_update
BEFORE UPDATE ON orders
FOR EACH ROW
EXECUTE FUNCTION prevent_nota_order_update();

-- Tabel branches
CREATE TABLE IF NOT EXISTS branches (
    branch_id BIGSERIAL PRIMARY KEY,
    name TEXT NOT NULL,
    code TEXT NOT NULL UNIQUE,
    alias TEXT,
    initials TEXT,
    address TEXT,
    phone_number TEXT,
    created_at TIMESTAMP DEFAULT now(),
    updated_at TIMESTAMP DEFAULT now()
);

-- Index tambahan untuk query
CREATE INDEX IF NOT EXISTS idx_branches_name ON branches(name);
CREATE INDEX IF NOT EXISTS idx_branches_initials ON branches(initials);


-- Tabel users
CREATE TABLE IF NOT EXISTS users (
    user_id BIGSERIAL PRIMARY KEY,
    username TEXT UNIQUE NOT NULL,
    password_hash TEXT NOT NULL,
    status TEXT CHECK (status IN ('active','inactive')) DEFAULT 'active',
    created_at TIMESTAMP DEFAULT now(),
    updated_at TIMESTAMP DEFAULT now()
);

-- Index tambahan
CREATE INDEX IF NOT EXISTS idx_users_status ON users(status);


-- Tabel user_branch_roles
CREATE TABLE IF NOT EXISTS user_branch_roles (
    id BIGSERIAL PRIMARY KEY,
    user_id BIGINT NOT NULL REFERENCES users(user_id),
    branch_id BIGINT NOT NULL REFERENCES branches(branch_id),
    role TEXT CHECK(role IN ('cs','kasir','admin_toko','admin_workshop','tukang','manajer','superadmin')),
    is_primary BOOLEAN DEFAULT FALSE,
    UNIQUE(user_id, branch_id, role)
);

-- Index tambahan untuk query per user, per branch
CREATE INDEX IF NOT EXISTS idx_user_branch_roles_user_id ON user_branch_roles(user_id);
CREATE INDEX IF NOT EXISTS idx_user_branch_roles_branch_id ON user_branch_roles(branch_id);
CREATE INDEX IF NOT EXISTS idx_user_branch_roles_role ON user_branch_roles(role);


-- Tabel items
CREATE TABLE IF NOT EXISTS items (
    item_id BIGSERIAL PRIMARY KEY,
    branch_id BIGINT NOT NULL REFERENCES branches(branch_id),
    kode_produk TEXT NOT NULL,
    kategori TEXT,
    jenis TEXT,
    tipe TEXT,
    name TEXT NOT NULL,
    material TEXT NOT NULL,
    purity TEXT NOT NULL,
    weight NUMERIC NOT NULL,
    quantity INTEGER NOT NULL DEFAULT 1,
    status TEXT NOT NULL,
    source TEXT DEFAULT 'manual',
    metadata JSONB,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(branch_id, kode_produk) -- pastikan kode unik per branch
);

-- Index tambahan
CREATE INDEX IF NOT EXISTS idx_items_branch_id ON items(branch_id);
CREATE INDEX IF NOT EXISTS idx_items_status ON items(status);
CREATE INDEX IF NOT EXISTS idx_items_kategori ON items(kategori);


-- Tabel customers
CREATE TABLE IF NOT EXISTS customers (
    customer_id BIGSERIAL PRIMARY KEY,
    name TEXT NOT NULL,
    phone TEXT,
    address TEXT NOT NULL,
    metadata JSONB,
    created_at TIMESTAMP DEFAULT now(),
    updated_at TIMESTAMP DEFAULT now()
);

-- Index tambahan
CREATE INDEX IF NOT EXISTS idx_customers_phone ON customers(phone);
CREATE INDEX IF NOT EXISTS idx_customers_name ON customers(name);

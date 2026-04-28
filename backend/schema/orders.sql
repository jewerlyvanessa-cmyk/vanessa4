-- Tabel orders
CREATE TABLE IF NOT EXISTS orders (
    order_id BIGSERIAL PRIMARY KEY,
    order_type TEXT NOT NULL,
    order_number TEXT UNIQUE,
    branch_id BIGINT NOT NULL REFERENCES user_branch_roles(branch_id), -- multi-branch & multi-role
    user_id BIGINT NOT NULL REFERENCES users(user_id),
    mode VARCHAR,
    customer_id BIGINT REFERENCES customers(customer_id),
    diskon DECIMAL(5,2) DEFAULT 0,
    total NUMERIC(15,2) DEFAULT 0,
    jumlah NUMERIC GENERATED ALWAYS AS (CEIL((COALESCE(total, 0)) / 5000) * 5000) STORED,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Index tambahan
CREATE INDEX IF NOT EXISTS idx_orders_branch_id ON orders(branch_id);
CREATE INDEX IF NOT EXISTS idx_orders_user_id ON orders(user_id);
CREATE INDEX IF NOT EXISTS idx_orders_customer_id ON orders(customer_id);
CREATE INDEX IF NOT EXISTS idx_orders_order_number ON orders(order_number);


-- Tabel order_items
CREATE TABLE IF NOT EXISTS order_items (
    order_item_id BIGSERIAL PRIMARY KEY,
    order_id BIGINT NOT NULL REFERENCES orders(order_id),
    item_id BIGINT REFERENCES items(item_id),
    nama_item VARCHAR(255),
    kode_produk VARCHAR(100),
    berat NUMERIC(10,2),
    qty INTEGER DEFAULT 1,
    weight NUMERIC NOT NULL,
    harga_per_gram NUMERIC NOT NULL,
    jumlah NUMERIC GENERATED ALWAYS AS (qty * weight * harga_per_gram) STORED,
    photo_produk TEXT,
    kategori VARCHAR(50),
    jenis VARCHAR(100),
    tipe VARCHAR(50)
);

-- Index tambahan
CREATE INDEX IF NOT EXISTS idx_order_items_order_id ON order_items(order_id);
CREATE INDEX IF NOT EXISTS idx_order_items_item_id ON order_items(item_id);

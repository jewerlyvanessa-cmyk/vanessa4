-- Siapa yang mencatat barang pertama kali (input stok / massal / API).
ALTER TABLE items ADD COLUMN IF NOT EXISTS created_by BIGINT REFERENCES users(user_id);
CREATE INDEX IF NOT EXISTS idx_items_created_by ON items(created_by);

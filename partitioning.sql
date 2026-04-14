-- Implementing table partitioning for large tables: orders and items

-- Partitioning the orders table by branch_id
CREATE TABLE orders_partitioned (
    order_id BIGSERIAL NOT NULL,
    order_type TEXT NOT NULL,
    item_id BIGINT,
    status TEXT NOT NULL,
    branch_id BIGINT NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
) PARTITION BY LIST (branch_id);

-- Example partitions for orders
CREATE TABLE orders_branch_1 PARTITION OF orders_partitioned FOR VALUES IN (1);
CREATE TABLE orders_branch_2 PARTITION OF orders_partitioned FOR VALUES IN (2);

-- Partitioning the items table by branch_id
CREATE TABLE items_partitioned (
    item_id BIGSERIAL NOT NULL,
    name TEXT NOT NULL,
    weight NUMERIC NOT NULL,
    material TEXT NOT NULL,
    purity TEXT NOT NULL,
    status TEXT NOT NULL,
    branch_id BIGINT NOT NULL,
    photo_url TEXT,
    metadata JSONB,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
) PARTITION BY LIST (branch_id);

-- Example partitions for items
CREATE TABLE items_branch_1 PARTITION OF items_partitioned FOR VALUES IN (1);
CREATE TABLE items_branch_2 PARTITION OF items_partitioned FOR VALUES IN (2);

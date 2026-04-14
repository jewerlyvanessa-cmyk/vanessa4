-- Migration to fix order_items foreign key reference
-- Change order_id to reference orders(order_id) instead of orders(id)

-- Drop existing foreign key constraint
ALTER TABLE order_items DROP CONSTRAINT IF EXISTS order_items_order_id_fkey;

-- Add correct foreign key constraint
ALTER TABLE order_items ADD CONSTRAINT order_items_order_id_fkey
    FOREIGN KEY (order_id) REFERENCES orders(order_id) ON DELETE CASCADE;

-- Optional: Update any existing data if needed
-- This assumes order_items.order_id values are already correct

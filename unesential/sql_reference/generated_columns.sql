-- Adding generated columns for auto-generated document numbers in the orders table

-- Alter the orders table to include a generated column for document numbers
ALTER TABLE orders
ADD COLUMN document_number TEXT GENERATED ALWAYS AS (
    'ORD-' || branch_id || '-' || EXTRACT(YEAR FROM created_at) || '-' || LPAD(order_id::TEXT, 6, '0')
) STORED;

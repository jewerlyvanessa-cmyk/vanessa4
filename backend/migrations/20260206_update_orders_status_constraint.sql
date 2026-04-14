-- Migration: Update orders status check constraint to include 'pending'
-- Date: 2026-02-06
-- Description: Add 'pending' status to the orders_status_check constraint

-- First, drop the existing constraint if it exists
ALTER TABLE orders DROP CONSTRAINT IF EXISTS orders_status_check;

-- Create new constraint with all valid status values
ALTER TABLE orders ADD CONSTRAINT orders_status_check
CHECK (status IN ('draft', 'pending', 'completed', 'cancelled'));

-- Optional: Update any existing 'draft' orders to 'pending' if needed
-- UPDATE orders SET status = 'pending' WHERE status = 'draft' AND order_type = 'jual';

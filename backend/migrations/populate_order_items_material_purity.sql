-- Migration to populate material and purity in order_items from items table
-- Run this after adding material and purity columns to order_items table

-- Update order_items with material and purity from items table where order_items.material is null/empty
UPDATE order_items
SET
  material = i.material,
  purity = i.purity,
  updated_at = NOW()
FROM items i
WHERE order_items.item_id = i.item_id
  AND (order_items.material IS NULL OR order_items.material = '')
  AND i.material IS NOT NULL AND i.material != '';

-- Update order_items with material and purity from order data (if stored in order_items but empty)
-- This handles cases where material/purity might be stored in other fields

COMMIT;

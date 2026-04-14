-- Migration: Add quantity and source columns to items table
-- Run this if you have existing items table without these columns

ALTER TABLE items ADD COLUMN IF NOT EXISTS quantity INTEGER DEFAULT 1;
ALTER TABLE items ADD COLUMN IF NOT EXISTS source TEXT DEFAULT 'manual';

-- Update existing records to have quantity = 1 if null
UPDATE items SET quantity = 1 WHERE quantity IS NULL;

-- Add status column to branches table
ALTER TABLE branches ADD COLUMN IF NOT EXISTS status TEXT CHECK (status IN ('active','inactive')) DEFAULT 'active';

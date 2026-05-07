-- Logo cabang (path relatif, mis. /uploads/...)
ALTER TABLE branches
  ADD COLUMN IF NOT EXISTS logo_url TEXT;

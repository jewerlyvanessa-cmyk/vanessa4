-- Migration: Create uploads table for safe metadata storage
-- Date: 2026-04-24
--
-- Purpose:
-- - Store upload metadata (original name, mime, size, uploader, storage key)
-- - Avoid relying on user-controlled filenames for storage paths

CREATE TABLE IF NOT EXISTS uploads (
  upload_id BIGSERIAL PRIMARY KEY,
  storage_key TEXT NOT NULL UNIQUE, -- stored filename in ./uploads
  original_name TEXT,
  mime_type TEXT,
  size_bytes BIGINT,
  url_path TEXT, -- e.g. /uploads/<storage_key>
  uploaded_by_user_id BIGINT REFERENCES users(user_id),
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_uploads_uploaded_by_user_id ON uploads(uploaded_by_user_id);
CREATE INDEX IF NOT EXISTS idx_uploads_created_at ON uploads(created_at);

COMMIT;

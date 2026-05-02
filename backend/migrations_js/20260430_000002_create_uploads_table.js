/**
 * Create `uploads` table used by backend for upload metadata.
 *
 * This aligns DB schema with `backend/server.js` which inserts into `uploads`.
 */

exports.shorthands = undefined;

exports.up = async (pgm) => {
  pgm.createTable(
    'uploads',
    {
      upload_id: { type: 'bigserial', primaryKey: true },
      storage_key: { type: 'text', notNull: true, unique: true },
      original_name: { type: 'text' },
      mime_type: { type: 'text' },
      size_bytes: { type: 'bigint' },
      url_path: { type: 'text' },
      uploaded_by_user_id: {
        type: 'bigint',
        references: '"users"',
        referencesConstraintName: 'uploads_uploaded_by_user_id_fkey',
        onDelete: 'set null',
      },
      created_at: { type: 'timestamp', default: pgm.func('CURRENT_TIMESTAMP') },
    },
    { ifNotExists: true }
  );

  pgm.createIndex('uploads', 'uploaded_by_user_id', {
    name: 'idx_uploads_uploaded_by_user_id',
    ifNotExists: true,
  });
  pgm.createIndex('uploads', 'created_at', {
    name: 'idx_uploads_created_at',
    ifNotExists: true,
  });

  // Best-effort: if legacy table `uploaded_files` exists, backfill basic metadata.
  // (This keeps older data discoverable without breaking existing installs.)
  pgm.sql(`
    INSERT INTO uploads (storage_key, url_path, created_at)
    SELECT uf.filename, uf.url, COALESCE(uf.uploaded_at, CURRENT_TIMESTAMP)
    FROM uploaded_files uf
    WHERE uf.filename IS NOT NULL
      AND NOT EXISTS (
        SELECT 1 FROM uploads u WHERE u.storage_key = uf.filename
      )
  `);
};

exports.down = async (pgm) => {
  pgm.dropTable('uploads', { ifExists: true, cascade: false });
};


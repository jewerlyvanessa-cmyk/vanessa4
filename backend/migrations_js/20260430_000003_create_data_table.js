/**
 * Create `data` table used by `/api/data` endpoints (backend/api.js).
 */

exports.shorthands = undefined;

exports.up = async (pgm) => {
  pgm.createTable(
    'data',
    {
      id: { type: 'serial', primaryKey: true },
      name: { type: 'text', notNull: true },
      value: { type: 'text', notNull: true },
      created_at: { type: 'timestamptz', default: pgm.func('now()'), notNull: true },
    },
    { ifNotExists: true }
  );
};

exports.down = async (pgm) => {
  pgm.dropTable('data', { ifExists: true, cascade: false });
};


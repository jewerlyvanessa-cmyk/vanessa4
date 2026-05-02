/**
 * Example node-pg-migrate migration.
 *
 * Safe to keep as a template; you can delete later.
 */

exports.shorthands = undefined;

exports.up = (pgm) => {
  pgm.createTable('migration_log', {
    id: 'id',
    note: { type: 'text', notNull: true },
    created_at: { type: 'timestamptz', notNull: true, default: pgm.func('now()') },
  }, { ifNotExists: true });
};

exports.down = (pgm) => {
  pgm.dropTable('migration_log', { ifExists: true });
};


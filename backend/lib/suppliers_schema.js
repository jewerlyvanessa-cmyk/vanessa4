'use strict';

/** Idempotent: tabel master supplier untuk gudang / manajemen. */
async function ensureSuppliersTable(db) {
  await db.query(`
    CREATE TABLE IF NOT EXISTS suppliers (
      supplier_id BIGSERIAL PRIMARY KEY,
      name TEXT NOT NULL,
      code TEXT,
      contact_name TEXT,
      phone TEXT,
      email TEXT,
      address TEXT,
      notes TEXT,
      status TEXT NOT NULL DEFAULT 'active',
      created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
      updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
    )
  `);
  await db.query(`
    DO $$ BEGIN
      ALTER TABLE suppliers
        ADD CONSTRAINT suppliers_status_check
        CHECK (status IN ('active', 'inactive'));
    EXCEPTION
      WHEN duplicate_object THEN NULL;
    END $$;
  `);
  await db.query(`
    CREATE UNIQUE INDEX IF NOT EXISTS suppliers_name_lower_unique
    ON suppliers (LOWER(TRIM(name)))
  `);
  await db.query(`
    CREATE INDEX IF NOT EXISTS suppliers_status_idx
    ON suppliers (status)
  `);
}

module.exports = { ensureSuppliersTable };

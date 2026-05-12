'use strict';

const BRANCH_TYPES = ['toko', 'warehouse', 'workshop', 'pusat'];
const BRANCH_TYPE_SET = new Set(BRANCH_TYPES);

function normalizeBranchType(raw) {
  const s = String(raw ?? 'toko')
    .trim()
    .toLowerCase();
  return BRANCH_TYPE_SET.has(s) ? s : 'toko';
}

/** Idempotent: kolom + constraint check (abaikan jika sudah ada). */
async function ensureBranchesBranchTypeColumn(db) {
  await db.query(`
    ALTER TABLE branches
    ADD COLUMN IF NOT EXISTS branch_type TEXT NOT NULL DEFAULT 'toko'
  `);
  await db.query(`
    DO $$ BEGIN
      ALTER TABLE branches
        ADD CONSTRAINT branches_branch_type_check
        CHECK (branch_type IN ('toko', 'warehouse', 'workshop', 'pusat'));
    EXCEPTION
      WHEN duplicate_object THEN NULL;
    END $$;
  `);
}

module.exports = {
  BRANCH_TYPES,
  normalizeBranchType,
  ensureBranchesBranchTypeColumn,
};

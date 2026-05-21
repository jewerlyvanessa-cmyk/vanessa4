/**
 * Introspeksi kolom opsional tabel `branches` dan `user_branch_roles`.
 */

async function getBranchesColumnFlags(client) {
  const r = await client.query(
    `
      SELECT column_name
      FROM information_schema.columns
      WHERE table_schema = 'public'
        AND table_name = 'branches'
        AND column_name IN ('alias', 'initials')
    `,
    []
  );
  const cols = new Set(r.rows.map((x) => x.column_name));
  return {
    alias: cols.has('alias'),
    initials: cols.has('initials'),
  };
}

function branchSelectFields(flags) {
  const parts = ['b.name'];
  if (flags.alias) parts.push('b.alias');
  if (flags.initials) parts.push('b.initials');
  return parts.join(', ');
}

async function userBranchRolesHasIsPrimary(client) {
  const r = await client.query(
    `
      SELECT 1
      FROM information_schema.columns
      WHERE table_schema = 'public'
        AND table_name = 'user_branch_roles'
        AND column_name = 'is_primary'
      LIMIT 1
    `,
    []
  );
  return r.rows.length > 0;
}

module.exports = {
  getBranchesColumnFlags,
  branchSelectFields,
  userBranchRolesHasIsPrimary,
};

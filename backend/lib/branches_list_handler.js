'use strict';

const {
  normalizeBranchType,
  ensureBranchesBranchTypeColumn,
} = require('./branches_schema');

/**
 * GET /branches dan GET /api/branches — satu implementasi (filter branch_type, logo_url opsional).
 */
async function handleBranchesListGet(req, res, db) {
  try {
    await ensureBranchesBranchTypeColumn(db);
    const typeFilter = String(req.query.branch_type ?? '').trim().toLowerCase();
    const allowedTypes = new Set(['toko', 'warehouse', 'workshop', 'pusat']);
    const typeWhere = allowedTypes.has(typeFilter) ? ' WHERE branch_type = $1' : '';
    const typeParams = allowedTypes.has(typeFilter) ? [typeFilter] : [];
    const qWithLogo = `
      SELECT
        branch_id,
        name,
        code,
        alias,
        initials,
        address,
        phone_number,
        status,
        branch_type,
        logo_url
      FROM branches
      ${typeWhere}
      ORDER BY name
    `;
    const qNoLogo = `
      SELECT
        branch_id,
        name,
        code,
        alias,
        initials,
        address,
        phone_number,
        status,
        branch_type,
        NULL::text AS logo_url
      FROM branches
      ${typeWhere}
      ORDER BY name
    `;
    let result;
    try {
      result = await db.query(qWithLogo, typeParams);
    } catch (e) {
      if (String(e.message || '').includes('logo_url')) {
        result = await db.query(qNoLogo, typeParams);
      } else {
        throw e;
      }
    }

    const processedRows = result.rows.map((row) => ({
      branch_id: row.branch_id != null ? String(row.branch_id) : '',
      name: row.name,
      code: row.code,
      alias: row.alias,
      initials: row.initials,
      address: row.address,
      phone_number: row.phone_number,
      status: row.status,
      branch_type: normalizeBranchType(row.branch_type),
      logo_url: row.logo_url || null,
    }));

    res.status(200).json(processedRows);
  } catch (error) {
    console.error('Error fetching branches:', error);
    res.status(500).json({
      error: 'Internal server error',
      details: error.message,
    });
  }
}

module.exports = { handleBranchesListGet };

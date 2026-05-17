const path = require('path');
require('dotenv').config({ path: path.join(__dirname, '../backend/.env') });

const bcrypt = require('bcryptjs');
const db = require('../backend/db');

/**
 * Bootstrap superadmin user with bcrypt password hash.
 *
 * Usage:
 *   SUPERADMIN_USERNAME=superadmin SUPERADMIN_PASSWORD='StrongPass123!' node unesential/setup_superadmin.js
 */
async function setupSuperadminUser() {
  const username = process.env.SUPERADMIN_USERNAME || 'superadmin';
  const password = process.env.SUPERADMIN_PASSWORD;
  const branchCode = process.env.SUPERADMIN_BRANCH_CODE || 'MAIN';
  const branchName = process.env.SUPERADMIN_BRANCH_NAME || 'Cabang Utama';
  const branchAlias = process.env.SUPERADMIN_BRANCH_ALIAS || 'Main Branch';
  const branchAddress = process.env.SUPERADMIN_BRANCH_ADDRESS || 'Jl. Raya No. 123';

  if (!username || !password) {
    throw new Error('SUPERADMIN_PASSWORD must be provided explicitly for security.');
  }

  try {
    console.log(`Using DB: ${process.env.DB_NAME || 'vanessa3'} @ ${process.env.DB_HOST || 'localhost'}:${process.env.DB_PORT || 5432}`);
    const passwordHash = await bcrypt.hash(password, 10);

    const userResult = await db.query(
      `
      INSERT INTO users (username, password_hash, status, created_at, updated_at)
      VALUES ($1, $2, 'active', NOW(), NOW())
      ON CONFLICT (username) DO UPDATE SET
        password_hash = EXCLUDED.password_hash,
        status = 'active',
        updated_at = NOW()
      RETURNING user_id
      `,
      [username, passwordHash]
    );

    const userId = userResult.rows[0].user_id;

    const branchInsertResult = await db.query(
      `
      INSERT INTO branches (name, code, alias, address, status, created_at, updated_at)
      VALUES ($1, $2, $3, $4, 'active', NOW(), NOW())
      ON CONFLICT (code) DO NOTHING
      RETURNING branch_id
      `,
      [branchName, branchCode, branchAlias, branchAddress]
    );

    let branchId;
    if (branchInsertResult.rows.length > 0) {
      branchId = branchInsertResult.rows[0].branch_id;
    } else {
      const existingBranch = await db.query('SELECT branch_id FROM branches WHERE code = $1 LIMIT 1', [branchCode]);
      if (existingBranch.rows.length === 0) {
        throw new Error(`Failed to locate branch with code "${branchCode}"`);
      }
      branchId = existingBranch.rows[0].branch_id;
    }

    await db.query('UPDATE user_branch_roles SET is_primary = false WHERE user_id = $1', [userId]);

    const roleExists = await db.query(
      'SELECT id FROM user_branch_roles WHERE user_id = $1 AND branch_id = $2 AND role = $3 LIMIT 1',
      [userId, branchId, 'superadmin']
    );

    if (roleExists.rows.length > 0) {
      await db.query(
        'UPDATE user_branch_roles SET is_primary = true WHERE id = $1',
        [roleExists.rows[0].id]
      );
    } else {
      await db.query(
        `
        INSERT INTO user_branch_roles (user_id, branch_id, role, is_primary)
        VALUES ($1, $2, 'superadmin', true)
        `,
        [userId, branchId]
      );
    }

    console.log('Superadmin bootstrap completed.');
    console.log(`Username : ${username}`);
    console.log(`Password : ${password}`);
    console.log(`Branch   : ${branchCode} (ID: ${branchId})`);
    console.log(`User ID  : ${userId}`);
  } catch (error) {
    console.error('Failed to setup superadmin user:', error.message);
    process.exitCode = 1;
  } finally {
    process.exit();
  }
}

if (require.main === module) {
  setupSuperadminUser();
}

module.exports = { setupSuperadminUser };

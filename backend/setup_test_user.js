const crypto = require('crypto');

// Script untuk setup user test
async function setupTestUser() {
  const db = require('./db');

  try {
    // Hash password "admin123" dengan SHA256
    const password = 'admin123';
    const hash = crypto.createHash('sha256').update(password).digest('hex');

    console.log('Password:', password);
    console.log('SHA256 Hash:', hash);

    // Insert test user
    const insertUserQuery = `
      INSERT INTO users (username, password_hash, status)
      VALUES ($1, $2, $3)
      ON CONFLICT (username) DO UPDATE SET
        password_hash = EXCLUDED.password_hash,
        status = EXCLUDED.status
      RETURNING user_id
    `;

    const userResult = await db.query(insertUserQuery, ['admin', hash, 'active']);
    const userId = userResult.rows[0].user_id;

    console.log('User created/updated with ID:', userId);

    // Insert branch if not exists
    const insertBranchQuery = `
      INSERT INTO branches (name, code, alias, address)
      VALUES ($1, $2, $3, $4)
      ON CONFLICT (code) DO NOTHING
      RETURNING branch_id
    `;

    const branchResult = await db.query(insertBranchQuery, [
      'Cabang Utama',
      'MAIN',
      'Main Branch',
      'Jl. Raya No. 123'
    ]);

    let branchId;
    if (branchResult.rows.length > 0) {
      branchId = branchResult.rows[0].branch_id;
      console.log('Branch created with ID:', branchId);
    } else {
      // Get existing branch
      const existingBranch = await db.query('SELECT branch_id FROM branches WHERE code = $1', ['MAIN']);
      branchId = existingBranch.rows[0].branch_id;
      console.log('Using existing branch ID:', branchId);
    }

    // Insert user branch role (cek dulu apakah sudah ada)
    const checkRoleQuery = `
      SELECT id FROM user_branch_roles
      WHERE user_id = $1 AND branch_id = $2 AND role = $3
    `;

    // CS role (primary)
    const csExists = await db.query(checkRoleQuery, [userId, branchId, 'cs']);
    if (csExists.rows.length === 0) {
      await db.query(`
        INSERT INTO user_branch_roles (user_id, branch_id, role, is_primary)
        VALUES ($1, $2, $3, $4)
      `, [userId, branchId, 'cs', true]);
      console.log('User role assigned: cs (primary)');
    } else {
      console.log('User role cs already exists');
    }

    // Kasir role
    const kasirExists = await db.query(checkRoleQuery, [userId, branchId, 'kasir']);
    if (kasirExists.rows.length === 0) {
      await db.query(`
        INSERT INTO user_branch_roles (user_id, branch_id, role, is_primary)
        VALUES ($1, $2, $3, $4)
      `, [userId, branchId, 'kasir', false]);
      console.log('User role assigned: kasir');
    } else {
      console.log('User role kasir already exists');
    }

    console.log('\n=== LOGIN TEST CREDENTIALS ===');
    console.log('Username: admin');
    console.log('Password: admin123');
    console.log('SHA256 Hash:', hash);
    console.log('===============================\n');

  } catch (error) {
    console.error('Error setting up test user:', error);
  } finally {
    process.exit();
  }
}

// Run if called directly
if (require.main === module) {
  setupTestUser();
}

module.exports = { setupTestUser };

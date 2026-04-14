const crypto = require('crypto');
const db = require('./db');

// Script untuk setup user customer_service
async function setupCustomerServiceUser() {
  try {
    // Hash password "P@ssw0rd" dengan SHA256 (sesuai backend)
    const password = 'P@ssw0rd';
    const hash = crypto.createHash('sha256').update(password).digest('hex');

    console.log('Password:', password);
    console.log('SHA256 Hash:', hash);

    // Insert user customer_service
    const insertUserQuery = `
      INSERT INTO users (username, password_hash, status)
      VALUES ($1, $2, $3)
      ON CONFLICT (username) DO UPDATE SET
        password_hash = EXCLUDED.password_hash,
        status = EXCLUDED.status
      RETURNING user_id
    `;

    const userResult = await db.query(insertUserQuery, ['customer_service', hash, 'active']);
    const userId = userResult.rows[0].user_id;

    console.log('User customer_service created/updated with ID:', userId);

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
      const getBranchQuery = 'SELECT branch_id FROM branches WHERE code = $1';
      const existingBranch = await db.query(getBranchQuery, ['MAIN']);
      branchId = existingBranch.rows[0].branch_id;
      console.log('Using existing branch ID:', branchId);
    }

    // Insert user_branch_roles (check if exists first)
    const checkRoleQuery = 'SELECT 1 FROM user_branch_roles WHERE user_id = $1 AND branch_id = $2 AND role = $3';
    const roleExists = await db.query(checkRoleQuery, [userId, branchId, 'cs']);

    if (roleExists.rows.length === 0) {
      const insertRoleQuery = `
        INSERT INTO user_branch_roles (user_id, branch_id, role, is_primary)
        VALUES ($1, $2, $3, $4)
      `;
      await db.query(insertRoleQuery, [userId, branchId, 'cs', true]);
      console.log('Role cs assigned to user customer_service');
    } else {
      console.log('Role cs already exists for user customer_service');
    }

    console.log('Setup completed successfully!');
  } catch (error) {
    console.error('Error setting up user:', error);
  } finally {
    process.exit();
  }
}

setupCustomerServiceUser();

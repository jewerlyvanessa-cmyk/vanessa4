'use strict';

const jwt = require('jsonwebtoken');
const bcrypt = require('bcryptjs');
const { requireLoginBody } = require('../middleware/require_login_body');

let _cachedUsersRoleColumnExists = null;
let _cachedUsersBranchIdColumnExists = null;

async function usersHasRoleAndBranchColumns(client) {
  if (
    _cachedUsersRoleColumnExists !== null &&
    _cachedUsersBranchIdColumnExists !== null
  ) {
    return {
      hasRole: _cachedUsersRoleColumnExists,
      hasBranchId: _cachedUsersBranchIdColumnExists,
    };
  }
  try {
    const r = await client.query(
      `
        SELECT column_name
        FROM information_schema.columns
        WHERE table_schema = 'public'
          AND table_name = 'users'
          AND column_name IN ('role', 'branch_id')
      `,
      []
    );
    const cols = new Set(r.rows.map((x) => x.column_name));
    _cachedUsersRoleColumnExists = cols.has('role');
    _cachedUsersBranchIdColumnExists = cols.has('branch_id');
  } catch (_) {
    _cachedUsersRoleColumnExists = false;
    _cachedUsersBranchIdColumnExists = false;
  }
  return {
    hasRole: _cachedUsersRoleColumnExists,
    hasBranchId: _cachedUsersBranchIdColumnExists,
  };
}

function mainModuleForRole(role) {
  switch (role) {
    case 'cs':
      return 'cs';
    case 'kasir':
      return 'kasir';
    case 'superadmin':
      return 'superadmin';
    case 'admin_toko':
      return 'order';
    case 'admin_workshop':
    case 'tukang':
      return 'workshop';
    case 'stockist':
    case 'admin_warehouse':
      return 'warehouse';
    case 'manajer':
      return 'reporting';
    default:
      return 'dashboard';
  }
}

/**
 * @param {import('express').Express} app
 * @param {{ db: any, loginLimiter: import('express').RequestHandler, SECRET_KEY: string, JWT_EXPIRES_IN: string }} deps
 */
function registerLoginRoutes(app, deps) {
  const { db, loginLimiter, SECRET_KEY, JWT_EXPIRES_IN } = deps;

  app.post('/login', loginLimiter, requireLoginBody, async (req, res) => {
    try {
      const { username, password } = req.body;

      const usersCols = await usersHasRoleAndBranchColumns(db);
      const userRoleSelect = usersCols.hasRole ? 'u.role as user_role,' : '';
      const userBranchSelect = usersCols.hasBranchId
        ? 'u.branch_id as user_branch_id,'
        : '';
      const query = `
      SELECT
        u.*,
        ${userRoleSelect}
        ${userBranchSelect}
        ubr.role as branch_role,
        ubr.branch_id as branch_role_branch_id
      FROM users u
      LEFT JOIN user_branch_roles ubr ON u.user_id = ubr.user_id
      WHERE u.username = $1
      ORDER BY ubr.is_primary DESC NULLS LAST
      LIMIT 1
    `;
      const result = await db.query(query, [username]);

      if (result.rows.length === 0) {
        return res.status(401).json({ error: 'Invalid username or password' });
      }

      const user = result.rows[0];
      const resolvedRole =
        (user.branch_role ?? user.user_role ?? user.role ?? '')
          .toString()
          .trim()
          .toLowerCase();
      const resolvedBranchId = (
        user.branch_role_branch_id ??
        user.user_branch_id ??
        user.branch_id ??
        ''
      )
        .toString()
        .trim();

      if (!resolvedRole || !resolvedBranchId) {
        return res.status(403).json({
          error: 'Forbidden',
          details:
            'User belum memiliki role/branch. Tambahkan assignment di tabel user_branch_roles (atau jalankan unesential/setup_superadmin.js untuk akun superadmin).',
        });
      }
      let isPasswordValid = false;
      const passwordHash = user.password_hash || '';
      const allowLegacyPlaintext =
        process.env.ALLOW_LEGACY_PLAINTEXT_PASSWORD === 'true' ||
        (process.env.NODE_ENV !== 'production' &&
          process.env.ALLOW_LEGACY_PLAINTEXT_PASSWORD !== 'false');
      if (passwordHash.startsWith('$2')) {
        isPasswordValid = await bcrypt.compare(password, passwordHash);
      } else if (allowLegacyPlaintext) {
        isPasswordValid = password === passwordHash;
        if (isPasswordValid) {
          const migratedHash = await bcrypt.hash(password, 10);
          await db.query(
            'UPDATE users SET password_hash = $1, updated_at = CURRENT_TIMESTAMP WHERE user_id = $2',
            [migratedHash, user.user_id]
          );
        }
      } else {
        isPasswordValid = false;
      }

      if (!isPasswordValid) {
        return res.status(401).json({ error: 'Invalid username or password' });
      }

      const mainModule = mainModuleForRole(resolvedRole);

      const rolesResult = await db.query(
        'SELECT DISTINCT role FROM user_branch_roles WHERE user_id = $1',
        [user.user_id]
      );
      const branchesWithRolesResult = await db.query(
        `SELECT ubr.branch_id, b.name, b.alias, b.initials, array_agg(ubr.role) as roles
        FROM user_branch_roles ubr
        JOIN branches b ON ubr.branch_id = b.branch_id
        WHERE ubr.user_id = $1
        GROUP BY ubr.branch_id, b.name, b.alias, b.initials`,
        [user.user_id]
      );
      const roles = rolesResult.rows.map((r) => r.role);
      const branches = branchesWithRolesResult.rows.map((b) => ({
        branch_id: b.branch_id,
        name: b.name,
        alias: b.alias,
        initials: b.initials,
        roles: b.roles,
      }));

      const token = jwt.sign(
        {
          user_id: user.user_id,
          username: user.username,
          role: resolvedRole,
          branch_id: resolvedBranchId,
        },
        SECRET_KEY,
        { expiresIn: JWT_EXPIRES_IN }
      );

      const loginResponse = {
        success: true,
        user_id: user.user_id,
        username: user.username,
        role: resolvedRole,
        branch: resolvedBranchId,
        mainModule,
        roles,
        branches,
        token,
      };
      res.status(200).json(loginResponse);
    } catch (error) {
      console.error('Error during login:', error);
      res.status(500).json({ error: 'Internal server error' });
    }
  });

  app.post('/api/auth/switch-context', async (req, res) => {
    try {
      const uid = req.user?.user_id;
      const username = req.user?.username;
      if (uid == null) {
        return res.status(401).json({ error: 'Unauthorized' });
      }
      const branchIdRaw = req.body?.branch_id ?? req.body?.branch;
      const roleRaw = req.body?.role;
      const branchIdNum = parseInt(String(branchIdRaw ?? '').trim(), 10);
      const role = (roleRaw ?? '').toString().trim().toLowerCase();
      if (!Number.isFinite(branchIdNum) || branchIdNum <= 0 || !role) {
        return res.status(400).json({ error: 'branch_id and role are required' });
      }
      const chk = await db.query(
        `
        SELECT 1
        FROM user_branch_roles
        WHERE user_id = $1
          AND branch_id = $2
          AND lower(trim(role::text)) = $3
        LIMIT 1
      `,
        [uid, branchIdNum, role]
      );
      if (chk.rows.length === 0) {
        return res.status(403).json({
          error: 'Forbidden',
          details: 'Kombinasi cabang dan peran tidak valid untuk akun ini.',
        });
      }
      const branchIdStr = String(branchIdNum);
      const mainModule = mainModuleForRole(role);
      const token = jwt.sign(
        {
          user_id: uid,
          username,
          role,
          branch_id: branchIdStr,
        },
        SECRET_KEY,
        { expiresIn: JWT_EXPIRES_IN }
      );
      res.status(200).json({
        success: true,
        token,
        role,
        branch: branchIdStr,
        mainModule,
      });
    } catch (error) {
      console.error('Error in switch-context:', error);
      res.status(500).json({ error: 'Internal server error' });
    }
  });
}

module.exports = { registerLoginRoutes };

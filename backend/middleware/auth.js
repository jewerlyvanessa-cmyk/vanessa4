const jwt = require('jsonwebtoken');

function authenticateToken(SECRET_KEY) {
  return (req, res, next) => {
    const authHeader = req.headers.authorization || '';
    const token = authHeader.startsWith('Bearer ') ? authHeader.slice(7) : null;
    if (!token) {
      return res.status(401).json({ error: 'Unauthorized' });
    }

    try {
      const payload = jwt.verify(token, SECRET_KEY);
      req.user = payload;
      next();
    } catch (error) {
      return res.status(401).json({ error: 'Invalid or expired token' });
    }
  };
}

function requireRoles(...roles) {
  return (req, res, next) => {
    const roleRaw = req.user?.role;
    const role = (roleRaw ?? '').toString().trim().toLowerCase();
    const allowed = roles.map((r) => (r ?? '').toString().trim().toLowerCase());
    if (!role) {
      return res.status(403).json({
        error: 'Forbidden',
        details: 'Role tidak ditemukan di token. Pastikan user punya assignment di user_branch_roles.',
      });
    }
    if (!allowed.includes(role)) {
      return res.status(403).json({
        error: 'Forbidden',
        details: `Role "${roleRaw}" tidak punya akses. Butuh salah satu: ${roles.join(', ')}`,
      });
    }
    next();
  };
}

module.exports = {
  authenticateToken,
  requireRoles,
};


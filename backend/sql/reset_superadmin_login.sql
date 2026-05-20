-- Reset akun superadmin setelah migrasi ke vanessa_store
-- Password TIDAK bisa ditulis manual di SQL (harus bcrypt).
-- Cara terbaik: jalankan di server (dari folder project):
--
--   cd backend
--   SUPERADMIN_USERNAME=superadmin SUPERADMIN_PASSWORD='PasswordBaru123!' \
--     node ../unesential/setup_superadmin.js
--
-- Script di atas membuat/update user + cabang + user_branch_roles.

-- Cek apakah user ada dan punya role (jika 403, bukan 401):
SELECT
  u.user_id,
  u.username,
  u.status,
  left(u.password_hash, 7) AS hash_prefix,
  ubr.role,
  ubr.branch_id,
  ubr.is_primary
FROM users u
LEFT JOIN user_branch_roles ubr ON ubr.user_id = u.user_id
WHERE u.username = 'superadmin';

-- Jika user ada tapi tidak ada baris user_branch_roles, tambahkan manual
-- (ganti branch_id sesuai cabang Anda, mis. dari SELECT * FROM branches):
/*
INSERT INTO user_branch_roles (user_id, branch_id, role, is_primary)
SELECT u.user_id, b.branch_id, 'superadmin', TRUE
FROM users u
CROSS JOIN branches b
WHERE u.username = 'superadmin'
  AND b.code = 'PST'
ON CONFLICT (user_id, branch_id, role) DO UPDATE SET is_primary = EXCLUDED.is_primary;
*/

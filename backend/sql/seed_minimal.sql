-- Data awal minimal
--
-- Urutan:
--   1. Database kosong → jalankan vanessa3_schema_new_database.sql
--   2. Database lama  → jalankan patch_missing_columns.sql
--   3. Baru ini
--
-- Jika error "current transaction is aborted" → jalankan: ROLLBACK;

INSERT INTO branches (name, code, alias, initials, branch_type, status)
VALUES
  ('Kantor Pusat', 'PST', 'Pusat', 'PS', 'pusat', 'active'),
  ('Toko Contoh', 'TK1', 'Toko 1', 'T1', 'toko', 'active')
ON CONFLICT (code) DO NOTHING;

-- Password: jangan tebak hash ini. Setelah seed, jalankan setup_superadmin.js dengan password yang Anda pilih.
INSERT INTO users (username, password_hash, status)
VALUES (
  'superadmin',
  '$2a$12$h6dhHYNiex3LAa/hcgHubuLfLZkEsZBNR1vD/LoTVmiOD/ofi2iua',
  'active'
)
ON CONFLICT (username) DO NOTHING;

INSERT INTO user_branch_roles (user_id, branch_id, role, is_primary)
SELECT u.user_id, b.branch_id, 'superadmin', TRUE
FROM users u
CROSS JOIN branches b
WHERE u.username = 'superadmin'
  AND b.code = 'PST'
ON CONFLICT (user_id, branch_id, role) DO NOTHING;

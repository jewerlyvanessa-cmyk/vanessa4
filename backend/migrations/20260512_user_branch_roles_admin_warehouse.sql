-- Role baru: admin_warehouse (+ pastikan stockist ada di CHECK bila DB dari skema lama).
ALTER TABLE user_branch_roles DROP CONSTRAINT IF EXISTS user_branch_roles_role_check;
ALTER TABLE user_branch_roles ADD CONSTRAINT user_branch_roles_role_check CHECK (
  role IN (
    'cs',
    'kasir',
    'admin_toko',
    'admin_workshop',
    'admin_warehouse',
    'tukang',
    'manajer',
    'superadmin',
    'stockist'
  )
);

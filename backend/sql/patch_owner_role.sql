-- Role Owner: dashboard global (penjualan, buyback, stok, order).
DO $$ BEGIN
  ALTER TABLE user_branch_roles DROP CONSTRAINT IF EXISTS user_branch_roles_role_check;
EXCEPTION
  WHEN undefined_object THEN NULL;
END $$;

ALTER TABLE user_branch_roles
  ADD CONSTRAINT user_branch_roles_role_check
  CHECK (role IN (
    'cs', 'kasir', 'admin_toko', 'admin_workshop', 'admin_warehouse',
    'tukang', 'manajer', 'superadmin', 'stockist', 'owner'
  ));

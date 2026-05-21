-- Fungsi nomor nota order (wajib untuk POST /orders tanpa order_number).
-- Jalankan setelah ROLLBACK jika transaksi sebelumnya error.

CREATE SEQUENCE IF NOT EXISTS order_nota_seq START 1 INCREMENT 1 MINVALUE 1 NO CYCLE;

CREATE OR REPLACE FUNCTION generate_nota_order(
  p_branch_id BIGINT,
  p_order_type TEXT
)
RETURNS TEXT
LANGUAGE plpgsql
AS $$
DECLARE
  v_initial TEXT;
  v_code TEXT;
  v_order_code TEXT;
  v_seq BIGINT;
BEGIN
  SELECT initials, code
  INTO v_initial, v_code
  FROM branches
  WHERE branch_id = p_branch_id;

  v_order_code := CASE p_order_type
    WHEN 'jual' THEN 'JL'
    WHEN 'buyback' THEN 'BB'
    WHEN 'service' THEN 'SV'
    WHEN 'custom' THEN 'CT'
    ELSE NULL
  END;

  IF v_order_code IS NULL THEN
    RAISE EXCEPTION 'Invalid order_type: %', p_order_type;
  END IF;

  v_seq := nextval('order_nota_seq');

  RETURN COALESCE(NULLIF(TRIM(v_initial), ''), 'XX')
    || '-'
    || COALESCE(NULLIF(TRIM(v_code), ''), 'BR')
    || '-'
    || v_order_code
    || '-'
    || LPAD(v_seq::TEXT, 8, '0');
END;
$$;

-- Cabang tanpa initials (opsional)
ALTER TABLE branches ADD COLUMN IF NOT EXISTS initials TEXT;
UPDATE branches SET initials = UPPER(LEFT(code, 3)) WHERE initials IS NULL OR TRIM(initials) = '';

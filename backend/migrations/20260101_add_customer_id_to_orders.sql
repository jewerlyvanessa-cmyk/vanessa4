-- Migration: Add customer_id to orders and set up foreign key
ALTER TABLE orders ADD COLUMN IF NOT EXISTS customer_id INTEGER;
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'fk_customer'
  ) THEN
    ALTER TABLE orders
      ADD CONSTRAINT fk_customer
      FOREIGN KEY (customer_id) REFERENCES customers(customer_id);
  END IF;
END $$;

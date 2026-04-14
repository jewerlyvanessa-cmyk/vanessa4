-- Migration: Add customer_id to orders and set up foreign key
ALTER TABLE orders ADD COLUMN customer_id INTEGER;
ALTER TABLE orders ADD CONSTRAINT fk_customer FOREIGN KEY (customer_id) REFERENCES customers(customer_id);

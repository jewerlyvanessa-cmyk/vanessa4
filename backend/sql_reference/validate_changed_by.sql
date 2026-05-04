-- Validate the `changed_by` column in the stock_history table

-- Add a foreign key constraint to ensure `changed_by` references a valid user
ALTER TABLE stock_history
ADD CONSTRAINT fk_changed_by_users
FOREIGN KEY (changed_by)
REFERENCES users(user_id)
ON DELETE SET NULL;

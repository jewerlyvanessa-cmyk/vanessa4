-- Ensure all status changes are logged in the stock_history table

-- Trigger to log changes in the items table
CREATE OR REPLACE FUNCTION log_stock_history()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.status IS DISTINCT FROM OLD.status THEN
        INSERT INTO stock_history (item_id, old_status, new_status, changed_by, timestamp)
        VALUES (NEW.item_id, OLD.status, NEW.status, NEW.updated_by, now());
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Attach the trigger to the items table
CREATE TRIGGER stock_history_trigger
AFTER UPDATE OF status
ON items
FOR EACH ROW
EXECUTE FUNCTION log_stock_history();

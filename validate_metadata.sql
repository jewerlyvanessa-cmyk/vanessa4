-- Validate and populate the `metadata` column in the items table

-- Example: Add a trigger to ensure metadata is not null and has default values
CREATE OR REPLACE FUNCTION validate_metadata()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.metadata IS NULL THEN
        NEW.metadata = jsonb_build_object('default_key', 'default_value');
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Attach the trigger to the items table
CREATE TRIGGER validate_metadata_trigger
BEFORE INSERT OR UPDATE OF metadata
ON items
FOR EACH ROW
EXECUTE FUNCTION validate_metadata();

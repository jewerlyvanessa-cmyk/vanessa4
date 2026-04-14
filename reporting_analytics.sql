-- Add reporting and analytics features

-- Example query for revenue report
CREATE OR REPLACE VIEW revenue_report AS
SELECT
    branch_id,
    EXTRACT(YEAR FROM created_at) AS year,
    EXTRACT(MONTH FROM created_at) AS month,
    SUM(amount) AS total_revenue
FROM
    payments
WHERE
    status = 'paid'
GROUP BY
    branch_id, year, month;

-- Example query for stock report
CREATE OR REPLACE VIEW stock_report AS
SELECT
    branch_id,
    status,
    COUNT(*) AS total_items
FROM
    items
GROUP BY
    branch_id, status;

-- Example query for exporting data to CSV
COPY (
    SELECT * FROM revenue_report
) TO '/path/to/export/revenue_report.csv' WITH CSV HEADER;

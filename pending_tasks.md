# Pending Tasks

## Database Enhancements
1. Implement partitioning for large tables (`orders`, `items`) to optimize performance.
2. Add auto-generated document numbers for orders.

## Stock History
1. Ensure all status changes are logged in the `stock_history` table.
2. Validate the `changed_by` column to track user actions.

## Metadata Validation
1. Validate and populate the `metadata` column in the `items` table.

## Additional Features
1. Implement optional `payments` table for financial tracking.
2. Add reporting and analytics features (e.g., revenue, stock reports, and export to PDF).

## Testing and Validation
1. Comprehensive testing of all flows (order, payment, workshop, reporting).
2. Validate database constraints and relationships.

const fs = require('fs');
const path = require('path');
const db = require('./db');

async function runItemConditionsMigration() {
    try {
        console.log('Starting migration to create item_conditions table...');

        // Read migration file
        const migrationPath = path.join(__dirname, 'migrations', '20260206_create_item_conditions_table.sql');
        const migrationSQL = fs.readFileSync(migrationPath, 'utf8');

        // Split SQL commands and execute them
        const commands = migrationSQL.split(';').filter(cmd => cmd.trim().length > 0);

        for (const command of commands) {
            if (command.trim()) {
                console.log('Executing:', command.trim().substring(0, 50) + '...');
                await db.query(command);
            }
        }

        console.log('✅ Item conditions table migration completed successfully!');
    } catch (error) {
        console.error('❌ Migration failed:', error);
        console.error(error.stack);
    } finally {
        process.exit();
    }
}

runItemConditionsMigration();

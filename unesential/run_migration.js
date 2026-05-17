const fs = require('fs');
const path = require('path');
const db = require('../backend/db');

async function runMigration() {
  try {
    console.log('Starting migration to cleanup order tables...');

    // Read migration file
    const migrationPath = path.join(
      __dirname,
      '../backend/migrations',
      '20260117_cleanup_order_tables.sql',
    );
    const migrationSQL = fs.readFileSync(migrationPath, 'utf8');

    // Split SQL commands and execute them
    const commands = migrationSQL.split(';').filter(cmd => cmd.trim().length > 0);

    for (const command of commands) {
      if (command.trim()) {
        console.log('Executing:', command.trim().substring(0, 50) + '...');
        await db.query(command);
      }
    }

    console.log('✅ Migration completed successfully!');
  } catch (error) {
    console.error('❌ Migration failed:', error);
  } finally {
    process.exit();
  }
}

runMigration();

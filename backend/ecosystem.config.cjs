/**
 * PM2 — disarankan dari folder backend:
 *   pm2 start ecosystem.config.cjs
 *   pm2 restart vanessa --update-env
 *
 * cwd = root project agar `node_modules` (googleapis, dll.) terbaca.
 * .env tetap di folder backend.
 */
const path = require('path');

const backendDir = __dirname;
const rootDir = path.join(backendDir, '..');

module.exports = {
  apps: [
    {
      name: 'vanessa',
      script: path.join(backendDir, 'server.js'),
      cwd: rootDir,
      env_file: path.join(backendDir, '.env'),
      instances: 1,
      autorestart: true,
      max_memory_restart: '512M',
      env: {
        NODE_ENV: 'production',
        STRICT_DB_ENV: 'true',
      },
    },
  ],
};

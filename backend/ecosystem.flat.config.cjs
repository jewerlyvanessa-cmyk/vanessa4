/**
 * PM2 untuk deploy flat (isi folder backend/ → nodeapp/, tanpa subfolder backend).
 * Salin ke root nodeapp: ecosystem.config.cjs
 *
 *   cd ~/web/mobile.vanessa.id/private/nodeapp
 *   pm2 start ecosystem.config.cjs
 *   pm2 restart vanessa --update-env
 */
module.exports = {
  apps: [
    {
      name: 'vanessa',
      script: './scripts/start.js',
      cwd: __dirname,
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

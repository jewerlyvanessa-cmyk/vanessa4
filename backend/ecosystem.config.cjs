/**
 * PM2 — jalankan dari folder backend:
 *   pm2 start ecosystem.config.cjs
 *   pm2 restart vanessa --update-env
 */
module.exports = {
  apps: [
    {
      name: 'vanessa',
      script: 'server.js',
      cwd: __dirname,
      env_file: '.env',
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

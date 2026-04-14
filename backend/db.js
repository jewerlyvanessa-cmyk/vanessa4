const { Pool } = require('pg');

// Konfigurasi koneksi database
const pool = new Pool({
  user: process.env.DB_USER || 'postgres', // Ganti dengan username database Anda
  host: process.env.DB_HOST || 'localhost', // Host database
  database: process.env.DB_NAME || 'vanessa3', // Nama database
  password: process.env.DB_PASSWORD || 'password', // Password database
  port: process.env.DB_PORT || 5432, // Port database
});

module.exports = {
  query: (text, params) => pool.query(text, params),
  getClient: () => pool.connect(),
};

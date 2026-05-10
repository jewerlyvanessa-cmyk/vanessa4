require('dotenv').config({ path: require('path').join(__dirname, '.env') });

const express = require('express');
const cors = require('cors');
const bodyParser = require('body-parser');

const port = process.env.PORT || 3000;
const SECRET_KEY = process.env.JWT_SECRET;
const JWT_EXPIRES_IN = process.env.JWT_EXPIRES_IN || '8h';

const allowedOrigins = (process.env.CORS_ORIGINS || '')
  .split(',')
  .map(origin => origin.trim())
  .filter(Boolean);

if (!SECRET_KEY) {
  throw new Error('JWT_SECRET is required. Please set it in environment variables.');
}

const app = express();

// Middleware (shared)
app.use(cors({
  origin: (origin, callback) => {
    // Allow server-to-server/mobile requests (no browser origin)
    if (!origin) {
      return callback(null, true);
    }
    // Always allow localhost for Flutter web dev / internal tools.
    // Flutter `flutter run -d chrome` uses a random localhost port.
    if (/^https?:\/\/(localhost|127\.0\.0\.1)(:\d+)?$/i.test(origin)) {
      return callback(null, true);
    }
    if (allowedOrigins.length === 0 || allowedOrigins.includes(origin)) {
      return callback(null, true);
    }
    return callback(new Error('CORS origin not allowed'));
  },
  methods: ['GET', 'POST', 'PUT', 'PATCH', 'DELETE', 'OPTIONS'],
  allowedHeaders: ['Content-Type', 'Authorization', 'X-Idempotency-Key'],
}));

app.use(bodyParser.json());

// Header keamanan dasar (tanpa dependensi tambahan)
app.use((req, res, next) => {
  res.setHeader('X-Content-Type-Options', 'nosniff');
  res.setHeader('X-Frame-Options', 'DENY');
  res.setHeader('Referrer-Policy', 'strict-origin-when-cross-origin');
  // camera=(self): izinkan getUserMedia di halaman same-origin (Flutter web / QR); tetap blok di iframe lintas origin.
  res.setHeader(
    'Permissions-Policy',
    'camera=(self), microphone=(), geolocation=()'
  );
  next();
});

// Request log awal rantai — berlaku untuk semua route yang didaftarkan setelahnya.
app.use((req, res, next) => {
  console.log(`HTTP ${req.method} ${req.url}`);
  next();
});

module.exports = {
  app,
  port,
  SECRET_KEY,
  JWT_EXPIRES_IN,
};


require('dotenv').config({ path: require('path').join(__dirname, '.env') });

const express = require('express');
const cors = require('cors');
const bodyParser = require('body-parser');
const { createRequestLogger } = require('./middleware/request_logger');

const port = process.env.PORT || 3000;
const SECRET_KEY = process.env.JWT_SECRET;
const JWT_EXPIRES_IN = process.env.JWT_EXPIRES_IN || '8h';

function normalizeOrigin(value) {
  if (!value || typeof value !== 'string') return '';
  let v = value.trim();
  if (
    (v.startsWith('"') && v.endsWith('"')) ||
    (v.startsWith("'") && v.endsWith("'"))
  ) {
    v = v.slice(1, -1).trim();
  }
  return v.replace(/\/+$/, '');
}

function parseAllowedOrigins(raw) {
  return (raw || '')
    .split(',')
    .map(normalizeOrigin)
    .filter(Boolean);
}

function originHostname(origin) {
  try {
    return new URL(origin).hostname.toLowerCase();
  } catch {
    return null;
  }
}

function stripWww(hostname) {
  return hostname.replace(/^www\./, '');
}

/** Same host as an allowed entry (http/https and optional www). */
function originMatchesAllowedHost(origin, allowedList) {
  const host = originHostname(origin);
  if (!host) return false;
  const oh = stripWww(host);
  return allowedList.some((allowed) => {
    const ah = stripWww(originHostname(allowed) || '');
    return ah && oh === ah;
  });
}

function isVanessaHostname(hostname) {
  if (!hostname) return false;
  const h = stripWww(hostname);
  return h === 'vanessa.id' || h.endsWith('.vanessa.id');
}

/** If allowlist includes any *.vanessa.id host, permit all vanessa.id subdomains. */
function originMatchesVanessaAllowlist(origin, allowedList) {
  const includesVanessa =
    allowedList.length > 0 &&
    allowedList.some((allowed) => isVanessaHostname(originHostname(allowed)));
  if (!includesVanessa) return false;
  return isVanessaHostname(originHostname(origin));
}

const allowedOrigins = parseAllowedOrigins(process.env.CORS_ORIGINS);

if (!SECRET_KEY) {
  throw new Error('JWT_SECRET is required. Please set it in environment variables.');
}

const app = express();

// Di belakang reverse proxy (nginx) agar req.ip = IP klien, bukan IP proxy.
// Tanpa ini, semua user di production bisa dihitung sebagai 1 IP → mudah kena 429.
if (process.env.TRUST_PROXY === 'true' || process.env.NODE_ENV === 'production') {
  app.set('trust proxy', 1);
}

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
    const normalized = normalizeOrigin(origin);
    if (
      allowedOrigins.length === 0 ||
      allowedOrigins.includes(normalized) ||
      allowedOrigins.includes(origin) ||
      originMatchesAllowedHost(origin, allowedOrigins) ||
      originMatchesVanessaAllowlist(origin, allowedOrigins)
    ) {
      return callback(null, true);
    }
    console.warn(
      `[cors] Blocked origin: ${origin} | CORS_ORIGINS=${allowedOrigins.join(', ') || '(empty — allow all)'}`
    );
    return callback(new Error('CORS origin not allowed'));
  },
  methods: ['GET', 'POST', 'PUT', 'PATCH', 'DELETE', 'OPTIONS'],
  allowedHeaders: [
    'Content-Type',
    'Authorization',
    'X-Idempotency-Key',
    'Cache-Control',
    'Accept',
  ],
}));

app.use(bodyParser.json());
app.use(createRequestLogger());

// Header keamanan dasar (tanpa dependensi tambahan)
app.use((req, res, next) => {
  res.setHeader('X-Content-Type-Options', 'nosniff');
  res.setHeader('X-Frame-Options', 'DENY');
  res.setHeader('Referrer-Policy', 'strict-origin-when-cross-origin');
  res.setHeader(
    'Permissions-Policy',
    'camera=(self), microphone=(), geolocation=()'
  );
  // API JSON — batasi sumber konten; upload/file dilayani terpisah.
  res.setHeader(
    'Content-Security-Policy',
    "default-src 'none'; frame-ancestors 'none'"
  );
  if (process.env.NODE_ENV === 'production') {
    res.setHeader(
      'Strict-Transport-Security',
      'max-age=31536000; includeSubDomains'
    );
  }
  next();
});

module.exports = {
  app,
  port,
  SECRET_KEY,
  JWT_EXPIRES_IN,
};


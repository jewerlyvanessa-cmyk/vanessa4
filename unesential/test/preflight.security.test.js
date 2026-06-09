'use strict';

const { describe, it, beforeEach, afterEach } = require('node:test');
const assert = require('node:assert/strict');
const { runPreflightSync } = require('../../backend/scripts/preflight');

function withEnv(overrides, fn) {
  const saved = { ...process.env };
  Object.assign(process.env, overrides);
  try {
    fn();
  } finally {
    process.env = saved;
  }
}

describe('preflight production JWT checks', () => {
  const baseProd = {
    NODE_ENV: 'production',
    JWT_SECRET: 'a'.repeat(64),
    DB_USER: 'u',
    DB_HOST: 'h',
    DB_NAME: 'n',
    DB_PASSWORD: 'p',
    DB_PORT: '5432',
    DB_SSL: 'true',
    PORT: '3000',
  };

  it('rejects placeholder JWT_SECRET in production', () => {
    withEnv({ ...baseProd, JWT_SECRET: 'change-me' }, () => {
      assert.throws(() => runPreflightSync(), /placeholder|change-me/i);
    });
  });

  it('rejects leaked example JWT prefix in production', () => {
    withEnv(
      {
        ...baseProd,
        JWT_SECRET: 'vanessa_jwt_super_secret_2025 ' + 'x'.repeat(64),
      },
      () => {
        assert.throws(() => runPreflightSync(), /ter-commit|Rotate/i);
      },
    );
  });

  it('rejects ALLOW_LEGACY_PLAINTEXT_PASSWORD in production', () => {
    withEnv(
      { ...baseProd, ALLOW_LEGACY_PLAINTEXT_PASSWORD: 'true' },
      () => {
        assert.throws(() => runPreflightSync(), /ALLOW_LEGACY_PLAINTEXT_PASSWORD/i);
      },
    );
  });
});

'use strict';

const { describe, it } = require('node:test');
const assert = require('node:assert/strict');
const { parseQueryLimit } = require('../../backend/lib/query_limits');

describe('parseQueryLimit', () => {
  it('returns default when missing', () => {
    assert.equal(parseQueryLimit(undefined, { defaultLimit: 500 }), 500);
  });

  it('caps at maxLimit', () => {
    assert.equal(
      parseQueryLimit('9999', { defaultLimit: 500, maxLimit: 2000 }),
      2000,
    );
  });

  it('parses valid limit', () => {
    assert.equal(parseQueryLimit('100', { defaultLimit: 500 }), 100);
  });

  it('falls back on invalid', () => {
    assert.equal(parseQueryLimit('abc', { defaultLimit: 200 }), 200);
  });
});

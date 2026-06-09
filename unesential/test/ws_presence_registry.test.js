'use strict';

const { test } = require('node:test');
const assert = require('node:assert/strict');
const jwt = require('jsonwebtoken');
const { EventEmitter } = require('events');

const { createWsPresenceRegistry } = require('../../backend/websocket/presence_registry');

const SECRET = 'ws-presence-test-secret';

function fakeOpenSocket() {
  const sock = new EventEmitter();
  sock.readyState = 1; // WebSocket.OPEN
  sock.send = () => {};
  sock.close = () => {};
  return sock;
}

test('registers presence from valid JWT', () => {
  const registry = createWsPresenceRegistry(SECRET);
  const sock = fakeOpenSocket();
  const token = jwt.sign(
    { user_id: 42, username: 'kasir1', role: 'kasir', branch_id: '3' },
    SECRET,
  );
  assert.equal(registry.tryRegisterWsPresenceFromToken(sock, token), true);
  const snap = registry.getActivePresenceSnapshot();
  assert.equal(snap.total_connections, 1);
  assert.equal(snap.users.length, 1);
  assert.equal(snap.users[0].user_id, 42);
  assert.equal(snap.users[0].username, 'kasir1');
});

test('rejects invalid JWT', () => {
  const registry = createWsPresenceRegistry(SECRET);
  const sock = fakeOpenSocket();
  assert.equal(registry.tryRegisterWsPresenceFromToken(sock, 'not-a-jwt'), false);
  assert.equal(registry.getActivePresenceSnapshot().total_connections, 0);
});

test('disconnectPresenceSessionsForUser closes matching sockets', () => {
  const registry = createWsPresenceRegistry(SECRET);
  const sock = fakeOpenSocket();
  let closed = false;
  sock.close = () => {
    closed = true;
  };
  const token = jwt.sign(
    { user_id: 7, username: 'u7', role: 'cs', branch_id: '1' },
    SECRET,
  );
  registry.tryRegisterWsPresenceFromToken(sock, token);
  const result = registry.disconnectPresenceSessionsForUser(7, 'test kick');
  assert.equal(result.closed, 1);
  assert.equal(closed, true);
});

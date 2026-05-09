'use strict';

const jwt = require('jsonwebtoken');
const WebSocket = require('ws');

/**
 * @param {string} secretKey JWT_SECRET
 */
function createWsPresenceRegistry(secretKey) {
  const wsPresenceBySocket = new Map();

  function tryRegisterWsPresenceFromToken(ws, token) {
    if (!token || typeof token !== 'string') return false;
    try {
      const payload = jwt.verify(token, secretKey);
      const userIdRaw = payload.user_id ?? payload.id;
      const user_id =
        userIdRaw != null ? parseInt(String(userIdRaw), 10) : NaN;
      if (Number.isNaN(user_id)) return false;
      wsPresenceBySocket.set(ws, {
        user_id,
        username: (payload.username || '').toString(),
        role: (payload.role || '').toString(),
        branch_id: (payload.branch_id ?? '').toString(),
        connected_at: new Date().toISOString(),
      });
      return true;
    } catch (_) {
      return false;
    }
  }

  function getActivePresenceSnapshot() {
    const byUser = new Map();
    for (const meta of wsPresenceBySocket.values()) {
      const uid = meta.user_id;
      if (!byUser.has(uid)) {
        byUser.set(uid, {
          user_id: uid,
          username: meta.username,
          role_active: meta.role,
          branch_id: meta.branch_id,
          sessions: 0,
          connected_since: meta.connected_at,
        });
      }
      const row = byUser.get(uid);
      row.sessions += 1;
      if (meta.connected_at < row.connected_since) {
        row.connected_since = meta.connected_at;
      }
    }
    const users = Array.from(byUser.values()).sort((a, b) =>
      String(a.username).localeCompare(String(b.username)),
    );
    return { users, total_connections: wsPresenceBySocket.size };
  }

  function disconnectPresenceSessionsForUser(targetUserId, reason) {
    const uid = parseInt(String(targetUserId), 10);
    if (!Number.isFinite(uid)) return { closed: 0 };
    const toClose = [];
    for (const [sock, meta] of wsPresenceBySocket.entries()) {
      if (meta.user_id === uid) toClose.push(sock);
    }
    const msg = JSON.stringify({
      type: 'force_logout',
      reason: reason || 'Anda dilogoutkan oleh administrator.',
    });
    for (const sock of toClose) {
      try {
        if (sock.readyState === WebSocket.OPEN) {
          sock.send(msg);
        }
      } catch (_) { }
      try {
        sock.close();
      } catch (_) { }
    }
    return { closed: toClose.length };
  }

  function forgetSocket(ws) {
    wsPresenceBySocket.delete(ws);
  }

  return {
    tryRegisterWsPresenceFromToken,
    getActivePresenceSnapshot,
    disconnectPresenceSessionsForUser,
    forgetSocket,
  };
}

module.exports = { createWsPresenceRegistry };

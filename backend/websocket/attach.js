'use strict';

const WebSocket = require('ws');

const WS_KEEPALIVE_MS = 25000;

/** @param {import('http').Server} httpServer */
function attachWebSocketServer(httpServer, presence) {
  const wss = new WebSocket.Server({ server: httpServer });

  const _pingInterval = setInterval(() => {
    wss.clients.forEach((client) => {
      if (client.readyState === WebSocket.OPEN) {
        try {
          client.ping();
        } catch (_) { }
      }
    });
  }, WS_KEEPALIVE_MS);

  wss.on('connection', (ws, req) => {
    console.log('New client connected');

    try {
      const host = req.headers.host || 'localhost';
      const url = new URL(req.url || '/', `http://${host}`);
      const token = url.searchParams.get('token');
      if (token) presence.tryRegisterWsPresenceFromToken(ws, token);
    } catch (err) {
      console.warn('WebSocket presence (query):', err.message);
    }

    ws.on('message', (raw) => {
      const text = Buffer.isBuffer(raw) ? raw.toString('utf8') : String(raw);
      try {
        const msg = JSON.parse(text);
        if (msg && msg.type === 'presence' && typeof msg.token === 'string') {
          const ok = presence.tryRegisterWsPresenceFromToken(ws, msg.token);
          ws.send(
            JSON.stringify(
              ok
                ? { type: 'presence_ack' }
                : { type: 'presence_error', error: 'invalid_token' },
            ),
          );
          return;
        }
        if (msg && msg.type === 'ping') {
          try {
            ws.send(
              JSON.stringify({
                type: 'pong',
                t: msg.t != null ? msg.t : null,
              }),
            );
          } catch (_) { }
          return;
        }
        if (process.env.WS_DEBUG === '1') {
          console.warn('WebSocket: ignored client JSON message', msg?.type);
        }
        return;
      } catch (_) {
        if (process.env.WS_DEBUG === '1') {
          console.warn('WebSocket: ignored non-JSON client message');
        }
      }
    });

    ws.on('close', () => {
      presence.forgetSocket(ws);
      console.log('Client disconnected');
    });
  });

  return wss;
}

module.exports = { attachWebSocketServer };

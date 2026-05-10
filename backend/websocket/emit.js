const crypto = require('crypto');

function emitNotification(wss, message, options = {}) {
  if (!wss) return;

  const eventId = crypto.randomUUID();
  const timestamp = new Date().toISOString();
  const branch_id = options.branch_id ?? null;
  const event = options.event ?? 'notification';
  const payload = options.payload ?? null;

  // Backward-compatible message schema:
  // - Flutter client currently expects: { type: 'notification', message: '...' }
  // - New fields are additive and safe for older clients.
  const frame = {
    type: 'notification',
    message: String(message ?? ''),
    eventId,
    timestamp,
    branch_id,
    event,
    payload,
  };

  const wire = JSON.stringify(frame);
  wss.clients.forEach((client) => {
    if (client.readyState !== 1 /* WebSocket.OPEN */) return;
    try {
      client.send(wire);
    } catch (e) {
      console.error('WebSocket client.send failed:', e?.message || e);
    }
  });
}

module.exports = {
  emitNotification,
};


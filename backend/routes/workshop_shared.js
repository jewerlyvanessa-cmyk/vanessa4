'use strict';

const ADMIN_WORKSHOP_PUT_ALLOWED_STATUSES = Object.freeze([
  'sent-to-workshop',
  'done_workshop',
  'ready_for_pickup',
  'cancelled',
]);

function createBroadcastWorkshop(notifyClients) {
  return (message, wsType, extra = {}) => {
    if (typeof notifyClients !== 'function') return;
    try {
      notifyClients(message, {
        wsType,
        branch_id: extra.branch_id ?? null,
        event: extra.event ?? wsType,
        payload: extra.payload ?? null,
      });
    } catch (e) {
      console.error('Workshop notify failed:', e?.message || e);
    }
  };
}

module.exports = {
  ADMIN_WORKSHOP_PUT_ALLOWED_STATUSES,
  createBroadcastWorkshop,
};

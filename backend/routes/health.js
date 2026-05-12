'use strict';

const express = require('express');

/**
 * Endpoint kesehatan publik (tanpa JWT).
 * @param {{ query: (text: string, params?: unknown[]) => Promise<unknown> }} db
 * @param {{ (): import('ws').Server | null | undefined }} getWss — diisi setelah WebSocket di-attach (boleh null).
 */
function createHealthRouter({ db, getWss }) {
  const router = express.Router();

  router.get('/health/live', (req, res) => {
    res.status(200).json({ status: 'ok', timestamp: new Date().toISOString() });
  });

  router.get('/health', async (req, res) => {
    try {
      await db.query('SELECT 1');
      const wss = typeof getWss === 'function' ? getWss() : null;
      res.status(200).json({
        status: 'healthy',
        timestamp: new Date().toISOString(),
        services: {
          database: 'connected',
          websocket: wss ? 'running' : 'not initialized',
        },
      });
    } catch (error) {
      res.status(500).json({
        status: 'unhealthy',
        timestamp: new Date().toISOString(),
        error: error.message,
      });
    }
  });

  return router;
}

module.exports = { createHealthRouter };

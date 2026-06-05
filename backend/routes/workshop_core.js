'use strict';

const express = require('express');
const { createBroadcastWorkshop } = require('./workshop_shared');
const { registerWorkshopQueueRoutes } = require('./workshop_api_queue');
const { registerWorkshopMaterialRoutes } = require('./workshop_api_material');
const { registerWorkshopDashboardRoutes } = require('./workshop_api_dashboard');
const { registerWorkshopCostRoutes } = require('./workshop_api_cost');
const { registerWorkshopOperationsRoutes } = require('./workshop_api_operations');
const { registerWorkshopTechnicianApiRoutes } = require('./workshop_technician_api');
const { registerWorkshopOrdersRoutes } = require('./workshop_orders');

function registerWorkshopRoutes(app, deps) {
  const { db, notifyClients } = deps;
  const broadcastWorkshop = createBroadcastWorkshop(notifyClients);
  const ctx = { db, broadcastWorkshop };

  const workshopApi = express.Router();
  const technicianApi = express.Router();

  registerWorkshopQueueRoutes(workshopApi, ctx);
  registerWorkshopMaterialRoutes(workshopApi, ctx);
  registerWorkshopDashboardRoutes(workshopApi, ctx);
  registerWorkshopCostRoutes(workshopApi, ctx);
  registerWorkshopOperationsRoutes(workshopApi, ctx);
  registerWorkshopTechnicianApiRoutes(technicianApi, ctx);

  app.use('/api/workshop', workshopApi);
  app.use('/api/technician', technicianApi);

  registerWorkshopOrdersRoutes(app, ctx);
}

module.exports = { registerWorkshopRoutes };

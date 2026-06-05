'use strict';

const { registerOrdersPickupRoutes } = require('./orders_pickup');
const { registerOrdersStoreOperationalRoutes } = require('./orders_store_operational');
const { registerOrdersReadRoutes } = require('./orders_read');
const { registerOrdersCreateRoutes } = require('./orders_create');

function registerOrdersCoreRoutes(app, deps) {
  const { db, upload, notifyClients, getOrdersDaily } = deps;

  registerOrdersPickupRoutes(app, { db, notifyClients });
  registerOrdersStoreOperationalRoutes(app, { db });
  registerOrdersReadRoutes(app, { db, getOrdersDaily });
  registerOrdersCreateRoutes(app, { db, upload, notifyClients });
}

module.exports = { registerOrdersCoreRoutes };

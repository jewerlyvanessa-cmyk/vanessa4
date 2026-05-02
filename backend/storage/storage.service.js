const local = require('./local.storage');
const s3 = require('./s3.storage');

function getStorageDriver() {
  // Future: choose by env, default local for now.
  return { kind: 'local', driver: local };
}

module.exports = {
  getStorageDriver,
  local,
  s3,
};


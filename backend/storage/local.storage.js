const crypto = require('crypto');
const path = require('path');

const allowedUploadMimeTypes = new Set(['image/jpeg', 'image/png', 'image/webp']);
const allowedUploadExts = new Set(['.jpg', '.jpeg', '.png', '.webp']);
const uploadExtByMime = {
  'image/jpeg': 'jpg',
  'image/png': 'png',
  'image/webp': 'webp',
};

function createSafeUploadFilename(file) {
  let ext = uploadExtByMime[file.mimetype];
  if (!ext) {
    const original = (file.originalname || '').toString();
    const originalExt = path.extname(original).toLowerCase();
    if (allowedUploadExts.has(originalExt)) {
      ext = originalExt === '.jpeg' ? 'jpg' : originalExt.slice(1);
    }
  }
  if (!ext) ext = 'bin';
  return `${Date.now()}-${crypto.randomUUID()}.${ext}`;
}

function isAllowedUploadMimeType(mimetype) {
  return allowedUploadMimeTypes.has(mimetype);
}

function isAllowedUploadFilename(filename) {
  const ext = path.extname((filename || '').toString()).toLowerCase();
  return allowedUploadExts.has(ext);
}

module.exports = {
  createSafeUploadFilename,
  isAllowedUploadMimeType,
  isAllowedUploadFilename,
};


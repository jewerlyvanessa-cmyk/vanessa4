/**
 * GET /branches/:id/logo & GET /api/branches/:id/logo — stream logo cabang (disk lokal atau unduhan dari logo_url).
 * Dipakai faktur PDF Flutter web (same-origin + JWT).
 */
const fs = require('fs');
const path = require('path');
const http = require('http');
const https = require('https');

const uploadsDir = path.resolve(path.join(__dirname, '..', 'uploads'));

function resolveBranchLogoUploadPath(logoUrlRaw) {
  let s = String(logoUrlRaw ?? '').trim();
  if (!s) return null;
  s = s.split(/[?#]/)[0];
  let relUnderUploads = null;
  try {
    if (/^https?:\/\//i.test(s)) {
      const u = new URL(s);
      const p = u.pathname || '';
      const lower = p.toLowerCase();
      const idx = lower.indexOf('/uploads/');
      if (idx >= 0) {
        relUnderUploads = p.slice(idx + '/uploads/'.length);
      } else {
        relUnderUploads = path.posix.basename(p.replace(/\\/g, '/'));
      }
    } else if (s.startsWith('/uploads/')) {
      relUnderUploads = s.slice('/uploads/'.length);
    } else if (/^uploads\//i.test(s)) {
      relUnderUploads = s.replace(/^uploads\//i, '');
    } else if (!/[\\/]/.test(s)) {
      relUnderUploads = s;
    } else {
      return null;
    }
  } catch (_) {
    return null;
  }
  if (!relUnderUploads || relUnderUploads.includes('..')) return null;
  const normalized = relUnderUploads.replace(/\\/g, '/');
  const resolved = path.resolve(
    path.join(uploadsDir, ...normalized.split('/').filter(Boolean)),
  );
  if (!resolved.startsWith(uploadsDir + path.sep)) return null;
  if (!fs.existsSync(resolved)) return null;
  return resolved;
}

function guessImageContentTypeFromBuffer(buf) {
  if (!buf || buf.length < 12) return null;
  if (buf[0] === 0xff && buf[1] === 0xd8) return 'image/jpeg';
  if (
    buf[0] === 0x89 &&
    buf[1] === 0x50 &&
    buf[2] === 0x4e &&
    buf[3] === 0x47 &&
    buf[4] === 0x0d &&
    buf[5] === 0x0a &&
    buf[6] === 0x1a &&
    buf[7] === 0x0a
  ) {
    return 'image/png';
  }
  if (
    buf.slice(0, 4).toString('ascii') === 'RIFF' &&
    buf.slice(8, 12).toString('ascii') === 'WEBP'
  ) {
    return 'image/webp';
  }
  if (
    buf.slice(0, 6).toString('ascii') === 'GIF87a' ||
    buf.slice(0, 6).toString('ascii') === 'GIF89a'
  ) {
    return 'image/gif';
  }
  return null;
}

function fetchRemoteLogoBuffer(urlString, maxBytes = 6 * 1024 * 1024) {
  return new Promise((resolve, reject) => {
    function attempt(targetUrl, redirectCount) {
      if (redirectCount > 5) {
        reject(new Error('too many redirects'));
        return;
      }
      let urlObj;
      try {
        urlObj = new URL(targetUrl);
      } catch (e) {
        reject(e);
        return;
      }
      if (!/^https?:$/i.test(urlObj.protocol)) {
        reject(new Error('unsupported protocol'));
        return;
      }
      const mod = urlObj.protocol === 'https:' ? https : http;
      const req = mod.get(
        targetUrl,
        {
          timeout: 20000,
          headers: { 'User-Agent': 'VanessaBranchLogo/1.0' },
        },
        (upstream) => {
          const code = upstream.statusCode || 0;
          if ([301, 302, 303, 307, 308].includes(code) && upstream.headers.location) {
            upstream.resume();
            attempt(new URL(upstream.headers.location, targetUrl).toString(), redirectCount + 1);
            return;
          }
          if (code !== 200) {
            upstream.resume();
            reject(new Error(`HTTP ${code}`));
            return;
          }
          const headerCt = (upstream.headers['content-type'] || '')
            .split(';')[0]
            .trim();
          const chunks = [];
          let total = 0;
          upstream.on('data', (chunk) => {
            total += chunk.length;
            if (total > maxBytes) {
              upstream.destroy();
              reject(new Error('too large'));
              return;
            }
            chunks.push(chunk);
          });
          upstream.on('end', () => {
            const buf = Buffer.concat(chunks);
            let ct = headerCt;
            if (!/^image\//i.test(ct)) {
              ct = guessImageContentTypeFromBuffer(buf) || 'application/octet-stream';
            }
            resolve({ buf, contentType: ct });
          });
          upstream.on('error', reject);
        },
      );
      req.on('error', reject);
      req.on('timeout', () => {
        req.destroy();
        reject(new Error('timeout'));
      });
    }
    attempt(urlString, 0);
  });
}

async function handleBranchLogoGet(req, res, db) {
  try {
    const id = parseInt(req.params.id, 10);
    if (!Number.isFinite(id) || id <= 0) {
      return res.status(400).json({ error: 'Invalid branch id' });
    }
    let logoRow;
    try {
      logoRow = await db.query(
        'SELECT logo_url FROM branches WHERE branch_id = $1 LIMIT 1',
        [id],
      );
    } catch (e) {
      if (String(e.message || '').includes('logo_url')) {
        return res.status(404).end();
      }
      throw e;
    }
    if (logoRow.rows.length === 0) return res.status(404).end();
    const rawLogo = String(logoRow.rows[0].logo_url ?? '').trim();
    if (!rawLogo) return res.status(404).end();

    const filePath = resolveBranchLogoUploadPath(rawLogo);
    if (filePath) {
      const ext = path.extname(filePath).toLowerCase();
      const ct =
        ext === '.png'
          ? 'image/png'
          : ext === '.webp'
            ? 'image/webp'
            : ext === '.gif'
              ? 'image/gif'
              : 'image/jpeg';
      res.setHeader('Content-Type', ct);
      return fs.createReadStream(filePath).pipe(res);
    }

    if (/^https?:\/\//i.test(rawLogo)) {
      try {
        const { buf, contentType } = await fetchRemoteLogoBuffer(rawLogo);
        const ct =
          /^image\//i.test(contentType)
            ? contentType
            : guessImageContentTypeFromBuffer(buf) || 'image/jpeg';
        res.setHeader('Content-Type', ct);
        return res.send(buf);
      } catch (e) {
        console.warn('Branch logo remote fetch failed', { branch_id: id, message: e.message });
        return res.status(404).end();
      }
    }

    return res.status(404).end();
  } catch (error) {
    console.error('Error streaming branch logo:', error);
    if (!res.headersSent) res.status(500).end();
  }
}

module.exports = {
  handleBranchLogoGet,
  resolveBranchLogoUploadPath,
};

#!/usr/bin/env node
'use strict';

/**
 * Cek semua require relatif di routes/ ada di disk.
 * Jalankan di server: node scripts/check-route-deps.js
 */
const fs = require('fs');
const path = require('path');

const routesDir = path.join(__dirname, '..', 'routes');

const entrypoints = [
  'workshop_core.js',
  'orders_core.js',
  'server.js',
];

function localRequires(filePath, seen = new Set()) {
  const abs = path.resolve(filePath);
  if (seen.has(abs)) return [];
  seen.add(abs);

  if (!fs.existsSync(abs)) {
    return [{ missing: abs, from: null }];
  }

  const src = fs.readFileSync(abs, 'utf8');
  const re = /require\s*\(\s*['"](\.[^'"]+)['"]\s*\)/g;
  const missing = [];
  let m;
  while ((m = re.exec(src)) !== null) {
    const rel = m[1];
    const resolved = path.resolve(path.dirname(abs), rel);
    const candidates = [
      resolved,
      `${resolved}.js`,
      path.join(resolved, 'index.js'),
    ];
    const found = candidates.some((c) => fs.existsSync(c));
    if (!found) {
      missing.push({ missing: resolved, from: abs });
    } else {
      const actual = candidates.find((c) => fs.existsSync(c));
      missing.push(...localRequires(actual, seen));
    }
  }
  return missing;
}

function main() {
  console.log(`[check-route-deps] routes dir: ${routesDir}`);
  if (!fs.existsSync(routesDir)) {
    console.error('Folder routes/ tidak ditemukan.');
    process.exit(1);
  }

  const allMissing = [];
  for (const entry of entrypoints) {
    const p = path.join(routesDir, entry);
    const misses = localRequires(p).filter((x) => x.missing && x.from);
    allMissing.push(...misses);
  }

  const unique = new Map();
  for (const item of allMissing) {
    unique.set(item.missing, item);
  }

  if (unique.size === 0) {
    console.log('[check-route-deps] OK — semua modul routes ditemukan.');
    process.exit(0);
  }

  console.error('[check-route-deps] FAIL — file hilang:');
  for (const [, item] of unique) {
    const base = path.basename(item.missing);
    console.error(`  - ${base} (required from ${path.basename(item.from)})`);
  }
  process.exit(1);
}

main();

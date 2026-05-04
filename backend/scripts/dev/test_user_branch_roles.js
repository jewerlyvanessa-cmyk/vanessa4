/**
 * Dev helper: starts backend/server.js from this repo and GETs /user-branch-roles/:id.
 * Run from repo root: node backend/scripts/dev/test_user_branch_roles.js
 */
const http = require('http');
const path = require('path');
const { spawn } = require('child_process');

const roleId = process.argv[2] || '11';
const backendDir = path.join(__dirname, '..', '..');

const testEndpoint = () => {
  const req = http.get(`http://localhost:3000/user-branch-roles/${roleId}`, (res) => {
    let data = '';
    res.on('data', (chunk) => {
      data += chunk;
    });
    res.on('end', () => {
      console.log('Status:', res.statusCode);
      console.log('Response:', data.substring(0, 500));
      process.exit(0);
    });
  });

  req.on('error', (err) => {
    console.error('Error:', err.message);
    process.exit(1);
  });

  req.setTimeout(5000, () => {
    console.error('Request timeout');
    req.destroy();
    process.exit(1);
  });
};

const server = spawn('node', ['server.js'], {
  cwd: backendDir,
  stdio: 'inherit',
});

server.on('error', (err) => {
  console.error('Failed to start server:', err);
  process.exit(1);
});

setTimeout(() => {
  testEndpoint();
}, 3000);

process.on('exit', () => {
  server.kill();
});
process.on('SIGINT', () => {
  server.kill();
  process.exit(0);
});

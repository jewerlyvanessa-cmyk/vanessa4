const path = require('path');
const { spawn } = require('child_process');
const http = require('http');

const backendRoot = path.join(__dirname, '..', '..');

// Start server
console.log('Starting server...');
const server = spawn('node', ['server.js'], {
  cwd: backendRoot,
  stdio: 'inherit'
});

server.on('error', (err) => {
  console.error('Failed to start server:', err);
  process.exit(1);
});

// Wait for server to start
setTimeout(() => {
  console.log('Testing /branches endpoint...');

  const options = {
    hostname: 'localhost',
    port: 3000,
    path: '/branches',
    method: 'GET',
    headers: {
      'Content-Type': 'application/json'
    }
  };

  const req = http.request(options, (res) => {
    console.log(`Status: ${res.statusCode}`);
    console.log(`Headers:`, res.headers);

    res.setEncoding('utf8');
    let body = '';
    res.on('data', (chunk) => {
      body += chunk;
    });
    res.on('end', () => {
      console.log('Response body:', body);

      // Stop server
      server.kill('SIGTERM');
      process.exit(0);
    });
  });

  req.on('error', (e) => {
    console.error(`Problem with request: ${e.message}`);
    server.kill('SIGTERM');
    process.exit(1);
  });

  req.end();
}, 3000);

const { spawn } = require('child_process');
const http = require('http');

// Start server
console.log('Starting server...');
const server = spawn('node', ['server.js'], {
  cwd: __dirname,
  stdio: 'inherit'
});

server.on('error', (err) => {
  console.error('Failed to start server:', err);
  process.exit(1);
});

// Wait for server to start
setTimeout(() => {
  console.log('Testing /api/customers endpoint...');

  const options = {
    hostname: 'localhost',
    port: 3000,
    path: '/api/customers',
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
      console.log('Response body length:', body.length);
      console.log('Response body (first 200 chars):', body.substring(0, 200));

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

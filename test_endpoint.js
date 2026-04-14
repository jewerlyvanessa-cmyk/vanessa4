const http = require('http');

// Test user-branch-roles endpoint
const testEndpoint = () => {
  const req = http.get('http://localhost:3000/user-branch-roles/11', (res) => {
    let data = '';
    res.on('data', chunk => data += chunk);
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

// Start server first
const { spawn } = require('child_process');
const server = spawn('node', ['server.js'], {
  cwd: '/Users/macbookpro2019/Documents/vanessa/vanessa 3/vanessa3/backend',
  stdio: 'inherit'
});

server.on('error', (err) => {
  console.error('Failed to start server:', err);
  process.exit(1);
});

// Wait for server to start
setTimeout(() => {
  testEndpoint();
}, 3000);

// Cleanup on exit
process.on('exit', () => {
  server.kill();
});
process.on('SIGINT', () => {
  server.kill();
  process.exit(0);
});

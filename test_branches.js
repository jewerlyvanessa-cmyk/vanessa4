const http = require('http');

// Test branches endpoints
const testBranches = () => {
  const req = http.get('http://localhost:3000/branches', (res) => {
    let data = '';
    res.on('data', chunk => data += chunk);
    res.on('end', () => {
      console.log('Branches Status:', res.statusCode);
      console.log('Branches Response:', data.substring(0, 300) + '...');

      // Test branch statistics
      const statsReq = http.get('http://localhost:3000/branches/4/statistics', (statsRes) => {
        let statsData = '';
        statsRes.on('data', chunk => statsData += chunk);
        statsRes.on('end', () => {
          console.log('\nStatistics Status:', statsRes.statusCode);
          console.log('Statistics Response:', statsData);
          process.exit(0);
        });
      });

      statsReq.on('error', (err) => {
        console.error('Statistics Error:', err.message);
        process.exit(1);
      });
    });
  });

  req.on('error', (err) => {
    console.error('Branches Error:', err.message);
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
  testBranches();
}, 3000);

// Cleanup on exit
process.on('exit', () => {
  server.kill();
});
process.on('SIGINT', () => {
  server.kill();
  process.exit(0);
});

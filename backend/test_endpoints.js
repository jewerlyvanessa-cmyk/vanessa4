const http = require('http');

const testEndpoint = (path, description) => {
  return new Promise((resolve, reject) => {
    const options = {
      hostname: 'localhost',
      port: 3000,
      path: path,
      method: 'GET',
      headers: {
        'Content-Type': 'application/json'
      }
    };

    const req = http.request(options, (res) => {
      console.log(`\n${description}`);
      console.log('Status:', res.statusCode);
      let data = '';
      res.on('data', (chunk) => data += chunk);
      res.on('end', () => {
        try {
          const json = JSON.parse(data);
          console.log('Response length:', json.length || 'N/A');
          if (json.length === 0) {
            console.log('Response: Empty array');
          } else {
            console.log('First item:', JSON.stringify(json[0], null, 2));
          }
          resolve(json);
        } catch (e) {
          console.log('Raw response:', data.substring(0, 200));
          resolve(data);
        }
      });
    });

    req.on('error', (e) => {
      console.error('Error:', e.message);
      reject(e);
    });
    req.end();
  });
};

// Test endpoints
async function runTests() {
  try {
    await testEndpoint('/api/workshop/work-queue?technician_id=1&branch_id=1', 'Testing work-queue endpoint');
    await testEndpoint('/api/workshop/dashboard?branch_id=1&user_id=1', 'Testing workshop dashboard endpoint');
    await testEndpoint('/api/technician/dashboard?branch_id=1&user_id=1', 'Testing technician dashboard endpoint');
  } catch (error) {
    console.error('Test failed:', error);
  }
}

runTests();

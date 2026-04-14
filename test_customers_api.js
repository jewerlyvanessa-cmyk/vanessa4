const http = require('http');

// Test the customers API
const options = {
  hostname: 'localhost',
  port: 3000,
  path: '/api/customers',
  method: 'GET',
  headers: {
    'Content-Type': 'application/json'
  }
};

console.log('Testing customers API...');

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
    try {
      const data = JSON.parse(body);
      console.log('Parsed data:', data);
    } catch (e) {
      console.log('Could not parse JSON response');
    }
  });
});

req.on('error', (e) => {
  console.error(`Problem with request: ${e.message}`);
  console.error('Error code:', e.code);
  console.error('Error errno:', e.errno);
});

req.setTimeout(5000, () => {
  console.error('Request timeout');
  req.destroy();
});

req.end();

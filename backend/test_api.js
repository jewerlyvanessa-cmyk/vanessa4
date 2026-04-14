const http = require('http');

console.log('Testing POST to create new branch...');

const postData = JSON.stringify({
  name: 'Test Branch',
  code: 'TEST',
  alias: 'Test Branch Alias',
  address: 'Test Address 123',
  phone_number: '08123456789',
  status: 'active'
});

const options = {
  hostname: 'localhost',
  port: 3000,
  path: '/api/branches',
  method: 'POST',
  headers: {
    'Content-Type': 'application/json',
    'Content-Length': Buffer.byteLength(postData)
  }
};

const req = http.request(options, (res) => {
  console.log(`Status: ${res.statusCode}`);

  let data = '';
  res.on('data', (chunk) => {
    data += chunk;
  });

  res.on('end', () => {
    console.log('Response received:');
    console.log(data);
    process.exit(0);
  });
});

req.on('error', (e) => {
  console.error(`Error: ${e.message}`);
  process.exit(1);
});

req.setTimeout(5000, () => {
  console.error('Request timeout');
  req.destroy();
  process.exit(1);
});

req.write(postData);
req.end();

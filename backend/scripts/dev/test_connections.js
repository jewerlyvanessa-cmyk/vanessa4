const http = require('http');

const ips = ['localhost', '127.0.0.1', '192.168.1.98'];

console.log('Testing API connections from different IPs:\n');

ips.forEach((ip, index) => {
  const options = {
    hostname: ip,
    port: 3000,
    path: '/api/customers',
    method: 'GET',
    headers: {
      'Content-Type': 'application/json'
    }
  };

  const req = http.request(options, (res) => {
    console.log(`${index + 1}. ${ip}: Status ${res.statusCode} ✅`);
  });

  req.on('error', (e) => {
    console.log(`${index + 1}. ${ip}: Failed ❌ (${e.code})`);
  });

  req.setTimeout(2000, () => {
    console.log(`${index + 1}. ${ip}: Timeout ⏰`);
    req.destroy();
  });

  req.end();
});

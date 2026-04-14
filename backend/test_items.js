const http = require('http');

setTimeout(() => {
  const options = {
    hostname: 'localhost',
    port: 3000,
    path: '/items?search=test&limit=10',
    method: 'GET',
    headers: {
      'Content-Type': 'application/json'
    }
  };

  const req = http.request(options, (res) => {
    console.log(`Status: ${res.statusCode}`);
    console.log(`Headers:`, res.headers);

    let data = '';
    res.on('data', (chunk) => {
      data += chunk;
    });

    res.on('end', () => {
      console.log('Response received');
      if (data) {
        try {
          const json = JSON.parse(data);
          console.log('Parsed JSON:', Array.isArray(json) ? `${json.length} items` : 'Not an array');
          if (Array.isArray(json) && json.length > 0) {
            console.log('First item:', json[0]);
          }
        } catch (e) {
          console.log('Raw response:', data.substring(0, 200));
        }
      } else {
        console.log('Empty response');
      }
      process.exit(0);
    });
  });

  req.on('error', (e) => {
    console.error('Request error:', e.message);
    process.exit(1);
  });

  req.setTimeout(10000, () => {
    console.log('Request timeout');
    req.destroy();
    process.exit(1);
  });

  req.end();
}, 3000);

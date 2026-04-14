const WebSocket = require('ws');

console.log('Testing WebSocket connection to ws://localhost:3000...');

const ws = new WebSocket('ws://localhost:3000');

ws.on('open', function open() {
  console.log('✅ WebSocket connection successful!');
  ws.close();
  process.exit(0);
});

ws.on('error', function error(err) {
  console.log('❌ WebSocket connection failed:', err.message);
  process.exit(1);
});

ws.on('close', function close() {
  console.log('WebSocket connection closed');
});

// Timeout after 5 seconds
setTimeout(() => {
  console.log('❌ WebSocket connection timeout');
  ws.close();
  process.exit(1);
}, 5000);

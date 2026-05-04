const WebSocket = require('ws');
const ws = new WebSocket('ws://localhost:8081');

ws.on('open', () => {
  console.log('Connected to WebSocket server');
  ws.send('Hello Server!');
});

ws.on('message', (message) => {
  console.log(`Received: ${message}`);
});

ws.on('error', (error) => {
  console.error(`WebSocket error: ${error}`);
});

ws.on('close', () => {
  console.log('Connection closed');
});

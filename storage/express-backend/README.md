# Node.js Express File Upload Backend

## Features
- POST /upload: Upload image, save to uploads/, store file URL in PostgreSQL
- GET /files: List all uploaded files
- .env for DB config

## Setup
1. Copy `.env.example` to `.env` dan edit DB credentials
2. Install dependencies: `npm install`
3. Run: `node index.js`

const crypto = require('crypto');

const password = 'P@ssw0rd'; // Ganti dengan password yang ingin di-hash
const hash = crypto.createHash('sha256').update(password, 'utf8').digest('hex');
console.log('SHA-256 hash:', hash);

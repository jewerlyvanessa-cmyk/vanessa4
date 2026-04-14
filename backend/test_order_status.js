const http = require('http');

const orderData = {
    "order_type": "jual",
    "branch_id": 1,
    "user_id": 1,
    "mode": "TOKO",
    "customer_id": 1,
    "diskon": 0,
    "order_items": [
        {
            "nama_item": "Test Item",
            "kode_produk": "TEST001",
            "weight": 10.0,
            "qty": 1,
            "harga_per_gram": 100000,
            "kategori": "PERHIASAN",
            "jenis": "KALUNG",
            "tipe": "GOLD",
            "material": "Emas",
            "purity": "24K"
        }
    ]
};

const postData = JSON.stringify(orderData);

const options = {
    hostname: 'localhost',
    port: 3000,
    path: '/orders',
    method: 'POST',
    headers: {
        'Content-Type': 'application/json',
        'Content-Length': Buffer.byteLength(postData)
    }
};

const req = http.request(options, (res) => {
    let data = '';
    res.on('data', (chunk) => data += chunk);
    res.on('end', () => {
        try {
            const response = JSON.parse(data);
            console.log('Order created successfully!');
            console.log('Order ID:', response.order_id);
            console.log('Order Number:', response.order_number);
            console.log('Status:', response.status);
            console.log('Order Type:', response.order_type);
        } catch (e) {
            console.log('Error parsing response:', e.message);
            console.log('Raw response:', data);
        }
    });
});

req.on('error', (e) => {
    console.error('Request error:', e.message);
});

req.write(postData);
req.end();

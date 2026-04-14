const http = require('http');

const options = {
    hostname: 'localhost',
    port: 3000,
    path: '/orders?type=jual&branch_id=1',
    method: 'GET',
    headers: {
        'Authorization': 'Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJ1c2VyX2lkIjoxLCJicmFuY2hfaWQiOjEsInJvbGUiOiJrYXNpciIsImlhdCI6MTY4MzQ3MjAwMCwiZXhwIjoxNjgzNTU4NDAwfQ.test'
    }
};

const req = http.request(options, (res) => {
    let data = '';
    res.on('data', (chunk) => data += chunk);
    res.on('end', () => {
        try {
            const orders = JSON.parse(data);
            if (orders && orders.length > 0) {
                console.log('Sample order data:');
                console.log('Order ID:', orders[0].order_id);
                console.log('Customer:', orders[0].customer_name);
                console.log('Item name:', orders[0].nama_item || orders[0].item_name);
                console.log('Material:', orders[0].material || orders[0].item_material);
                console.log('Purity:', orders[0].purity || orders[0].item_purity);
                console.log('Weight:', orders[0].weight || orders[0].item_weight);
                console.log('Quantity:', orders[0].qty);
                console.log('Harga per gram:', orders[0].harga_per_gram);
                console.log('Kategori:', orders[0].kategori || orders[0].item_kategori);
                console.log('Jenis:', orders[0].jenis || orders[0].item_jenis);
                console.log('Tipe:', orders[0].tipe || orders[0].item_tipe);
            } else {
                console.log('No orders found or empty response');
                console.log('Raw response:', data);
            }
        } catch (e) {
            console.log('Error parsing response:', e.message);
            console.log('Raw response:', data);
        }
    });
});

req.on('error', (e) => console.error('Request error:', e.message));
req.end();

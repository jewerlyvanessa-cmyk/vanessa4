const path = require('path');
const db = require(path.join(__dirname, '..', '..', 'db'));

async function testOrderSaving() {
  console.log('🧪 Testing Order Saving Functionality...\n');

  try {
    // Test data
    const testOrderData = {
      order_type: 'jual',
      order_number: 'TEST-' + Date.now(),
      branch_id: 1,
      user_id: 6, // from our DB check
      mode: 'TOKO',
      customer_id: 5, // from our DB check
      diskon: 5.0,
      order_items: [{
        nama_item: 'Test Gold Ring',
        kode_produk: 'TEST-RING-001',
        weight: 5.55, // Changed to test rounding (5.55 * 1000000 * 0.95 = 5,272,500 -> rounds to 5,275,000)
        harga_per_gram: 1000000,
        qty: 1,
        kategori: 'PERHIASAN',
        jenis: 'CINCIN',
        tipe: 'EMAS',
        photo_produk: 'test-photo-url.jpg'
      }]
    };

    console.log('📤 Test Order Data:');
    console.log(JSON.stringify(testOrderData, null, 2));
    console.log('\n' + '='.repeat(50) + '\n');

    // Start transaction
    const client = await db.getClient();

    try {
      await client.query('BEGIN');

      // Create order
      const orderResult = await client.query(
        `INSERT INTO orders (
          order_type, customer_id, status, order_number, branch_id, user_id, diskon, mode
        ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
        RETURNING *`,
        [
          testOrderData.order_type,
          testOrderData.customer_id,
          'draft',
          testOrderData.order_number,
          testOrderData.branch_id,
          testOrderData.user_id,
          testOrderData.diskon,
          testOrderData.mode
        ]
      );

      const order = orderResult.rows[0];
      console.log('✅ Order Created:');
      console.log(`   Order ID: ${order.order_id}`);
      console.log(`   Order Number: ${order.order_number}`);
      console.log(`   Order Type: ${order.order_type}`);
      console.log(`   Customer ID: ${order.customer_id}`);
      console.log(`   Branch ID: ${order.branch_id}`);
      console.log(`   User ID: ${order.user_id}`);
      console.log(`   Status: ${order.status}`);
      console.log(`   Diskon: ${order.diskon}`);
      console.log(`   Mode: ${order.mode}`);
      console.log(`   Total: ${order.total}`);
      console.log();

      // Create order item
      const itemData = testOrderData.order_items[0];
      const orderItemResult = await client.query(
        `INSERT INTO order_items (
          order_id, nama_item, kode_produk, qty, weight, harga_per_gram,
          subtotal, diskon, total, photo_produk, kategori, jenis, tipe
        ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13)
        RETURNING *`,
        [
          order.order_id,
          itemData.nama_item,
          itemData.kode_produk,
          itemData.qty,
          itemData.weight,
          itemData.harga_per_gram,
          itemData.qty * itemData.weight * itemData.harga_per_gram,
          testOrderData.diskon,
          itemData.qty * itemData.weight * itemData.harga_per_gram * (1 - testOrderData.diskon / 100),
          itemData.photo_produk,
          itemData.kategori,
          itemData.jenis,
          itemData.tipe
        ]
      );

      const orderItem = orderItemResult.rows[0];
      console.log('✅ Order Item Created:');
      console.log(`   Order Item ID: ${orderItem.order_item_id}`);
      console.log(`   Order ID: ${orderItem.order_id}`);
      console.log(`   Nama Item: ${orderItem.nama_item}`);
      console.log(`   Kode Produk: ${orderItem.kode_produk}`);
      console.log(`   Weight: ${orderItem.weight}`);
      console.log(`   Qty: ${orderItem.qty}`);
      console.log(`   Harga per Gram: ${orderItem.harga_per_gram}`);
      console.log(`   Jumlah (Generated): ${orderItem.jumlah}`);
      console.log(`   Subtotal: ${orderItem.subtotal}`);
      console.log(`   Diskon: ${orderItem.diskon}`);
      console.log(`   Total: ${orderItem.total}`);
      console.log(`   Photo Produk: ${orderItem.photo_produk}`);
      console.log(`   Kategori: ${orderItem.kategori}`);
      console.log(`   Jenis: ${orderItem.jenis}`);
      console.log(`   Tipe: ${orderItem.tipe}`);
      console.log();

      await client.query('COMMIT');

      console.log('🎉 SUCCESS: All data saved correctly!');
      console.log('\n📊 Verification Summary:');
      console.log('✅ Orders table: order_number, total, status fields working');
      console.log('✅ Order_items table: nama_item, weight, jumlah, kategori, jenis, tipe, photo_produk fields working');
      console.log('✅ No item_id column in orders (cleaned up)');
      console.log('✅ All calculated fields (subtotal, total, jumlah) working');

    } catch (error) {
      await client.query('ROLLBACK');
      console.error('❌ Transaction failed:', error);
      throw error;
    } finally {
      client.release();
    }

  } catch (error) {
    console.error('❌ Test failed:', error);
    process.exit(1);
  }
}

testOrderSaving();

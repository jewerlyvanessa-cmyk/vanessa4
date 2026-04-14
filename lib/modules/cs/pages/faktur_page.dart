import 'package:flutter/material.dart';
import 'package:vanessa3/utils/faktur_print.dart';

class FakturPage extends StatelessWidget {
  final Map<String, dynamic> orderData;
  const FakturPage({super.key, required this.orderData});

  @override
  Widget build(BuildContext context) {
    if (orderData.isEmpty || !orderData.containsKey('order_id')) {
      return Scaffold(
        appBar: AppBar(title: const Text('Faktur Order')),
        body: const Center(
          child: Text('Data faktur tidak valid atau tidak tersedia.'),
        ),
      );
    }

    // Get order items
    final List<dynamic> items = orderData['items'] ?? [];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Faktur Order'),
        actions: [
          IconButton(
            icon: const Icon(Icons.print),
            tooltip: 'Cetak / PDF',
            onPressed: () => printFakturOrder(context, orderData),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Center(
              child: Text(
                'FAKTUR PENJUALAN',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: Colors.blue[800],
                ),
              ),
            ),
            const SizedBox(height: 8),
            Center(
              child: Text(
                'VANESSA GOLD & DIAMOND',
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600),
              ),
            ),
            const Divider(height: 32, thickness: 2),

            // Order Information
            Text(
              'Informasi Order',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Card(
              elevation: 2,
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Order ID: ${orderData['order_id'] ?? '-'}'),
                    Text('Order Number: ${orderData['order_number'] ?? '-'}'),
                    Text('Tipe Order: ${orderData['order_type'] ?? '-'}'),
                    Text('Status: ${orderData['status'] ?? '-'}'),
                    Text(
                      'Tanggal: ${orderData['created_at'] != null ? DateTime.parse(orderData['created_at']).toLocal().toString().split('.')[0] : '-'}',
                    ),
                    Text('Customer: ${orderData['customer_name'] ?? '-'}'),
                    if (orderData['customer_phone'] != null)
                      Text('No. HP: ${orderData['customer_phone']}'),
                    if (orderData['customer_address'] != null)
                      Text('Alamat: ${orderData['customer_address']}'),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 24),

            // Order Items
            Text(
              'Detail Item',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),

            if (items.isEmpty)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(16.0),
                  child: Text('Tidak ada item dalam order ini'),
                ),
              )
            else
              ...items.map(
                (item) => Card(
                  elevation: 1,
                  margin: const EdgeInsets.only(bottom: 8),
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Text(
                                item['nama_item'] ?? 'Unknown Item',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 16,
                                ),
                              ),
                            ),
                            Text(
                              item['total'] != null
                                  ? 'Rp ${double.tryParse(item['total'].toString())?.toStringAsFixed(0).replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (Match m) => '${m[1]}.') ?? item['total']}'
                                  : 'Rp 0',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                                color: Colors.green,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 16,
                          runSpacing: 4,
                          children: [
                            if (item['weight'] != null)
                              Text('Berat: ${item['weight']}g'),
                            if (item['harga_per_gram'] != null)
                              Text(
                                'Harga/g: Rp ${double.tryParse(item['harga_per_gram'].toString())?.toStringAsFixed(0).replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (Match m) => '${m[1]}.') ?? item['harga_per_gram']}',
                              ),
                            if (item['jumlah'] != null)
                              Text(
                                'Jumlah: Rp ${double.tryParse(item['jumlah'].toString())?.toStringAsFixed(0).replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (Match m) => '${m[1]}.') ?? item['jumlah']}',
                              ),
                            if (item['qty'] != null)
                              Text('Qty: ${item['qty']}'),
                            if (item['kategori'] != null)
                              Text('Kategori: ${item['kategori']}'),
                            if (item['jenis'] != null)
                              Text('Jenis: ${item['jenis']}'),
                            if (item['tipe'] != null)
                              Text('Tipe: ${item['tipe']}'),
                            if (item['kode_produk'] != null)
                              Text('Kode: ${item['kode_produk']}'),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),

            const SizedBox(height: 24),

            // Order Summary
            Card(
              elevation: 3,
              color: Colors.blue[50],
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Ringkasan Order',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Total Order:',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          orderData['total'] != null
                              ? 'Rp ${double.tryParse(orderData['total'].toString())?.toStringAsFixed(0).replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (Match m) => '${m[1]}.') ?? orderData['total']}'
                              : 'Rp 0',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.green,
                          ),
                        ),
                      ],
                    ),
                    if (orderData['diskon'] != null &&
                        orderData['diskon'] != '0.00')
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Diskon:'),
                          Text(
                            'Rp ${double.tryParse(orderData['diskon'].toString())?.toStringAsFixed(0).replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (Match m) => '${m[1]}.') ?? orderData['diskon']}',
                            style: const TextStyle(color: Colors.red),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 32),

            // Footer
            Center(
              child: Column(
                children: [
                  Text(
                    'Terima kasih atas kunjungan Anda!',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Faktur ini dicetak pada: ${DateTime.now().toLocal().toString().split('.')[0]}',
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(color: Colors.grey[600]),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // Action Buttons
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.arrow_back),
                    label: const Text('Kembali'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.grey,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => Navigator.of(
                      context,
                    ).popUntil((route) => route.isFirst),
                    icon: const Icon(Icons.home),
                    label: const Text('Beranda'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

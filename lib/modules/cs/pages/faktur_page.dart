import 'package:flutter/material.dart';
import 'package:vanessa3/utils/faktur_print.dart';

class FakturPage extends StatelessWidget {
  final Map<String, dynamic> orderData;
  const FakturPage({super.key, required this.orderData});

  String _fmtMoney(dynamic v) {
    final n = double.tryParse(v?.toString() ?? '');
    if (n == null) return v?.toString() ?? '0';
    return n.toStringAsFixed(0).replaceAllMapped(
      RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
      (Match m) => '${m[1]}.',
    );
  }

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
    final customerName =
        orderData['customer_name'] ?? orderData['name'] ?? orderData['customer'];
    final customerPhone =
        orderData['customer_phone'] ?? orderData['phone'] ?? orderData['no_hp'];
    final customerAddress = orderData['customer_address'] ??
        orderData['address'] ??
        orderData['alamat'];

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
                    Text('Customer: ${customerName ?? '-'}'),
                    Text('No. HP: ${customerPhone ?? '-'}'),
                    Text('Alamat: ${customerAddress ?? '-'}'),
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
                        // 1) Kode
                        Text('Kode: ${item['kode_produk'] ?? '-'}'),
                        const SizedBox(height: 4),

                        // 2) Nama item
                        Text(
                          item['nama_item'] ?? 'Unknown Item',
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 8),

                        // 3) Berat
                        Text('Berat: ${item['weight'] ?? '-'}g'),

                        // 4) Harga/gram
                        Text(
                          'Harga/g: Rp ${double.tryParse((item['harga_per_gram'] ?? 0).toString())?.toStringAsFixed(0).replaceAllMapped(RegExp(r'(\\d{1,3})(?=(\\d{3})+(?!\\d))'), (Match m) => '${m[1]}.') ?? (item['harga_per_gram'] ?? 0)}',
                        ),

                        // 5) Total (source-of-truth dari backend)
                        Text(
                          'Total: Rp ${_fmtMoney(item['total'] ?? 0)}',
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
                    if (orderData['diskon'] != null &&
                        orderData['diskon'] != '0.00')
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Diskon:'),
                          Text(
                            (() {
                              final d =
                                  double.tryParse(orderData['diskon'].toString());
                              if (d == null) return '${orderData['diskon']}%';
                              final s = (d % 1 == 0)
                                  ? d.toStringAsFixed(0)
                                  : d.toStringAsFixed(2);
                              return '$s%';
                            })(),
                            style: const TextStyle(color: Colors.red),
                          ),
                        ],
                      ),
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
                          (orderData['jumlah'] ?? orderData['total']) != null
                              ? 'Rp ${_fmtMoney(orderData['jumlah'] ?? ((() {
                                  final t = double.tryParse(
                                        orderData['total']?.toString() ?? '',
                                      ) ??
                                      0;
                                  final rounded = (t / 5000).ceil() * 5000;
                                  return rounded;
                                })()))}'
                              : 'Rp 0',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.green,
                          ),
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

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:vanessa3/utils/faktur_print.dart'
    show
        printFakturOrder,
        printPickupServiceCustomFaktur,
        resolveFakturDpAmount,
        fakturDpFromPayloadSync,
        fakturServiceCustomFieldRows;
import 'package:vanessa3/utils/network_config.dart';
import 'package:http/http.dart' as http;
import 'package:qr_flutter/qr_flutter.dart';
import 'package:vanessa3/utils/responsive_layout.dart';

class FakturPage extends StatefulWidget {
  final Map<String, dynamic> orderData;
  const FakturPage({super.key, required this.orderData});

  @override
  State<FakturPage> createState() => _FakturPageState();
}

class _FakturPageState extends State<FakturPage> {
  late final Future<String> _branchTitleFuture;
  late final Future<double> _serviceCustomDpFuture;

  String _normalizeOrderType(dynamic raw) {
    return (raw ?? '').toString().trim().toLowerCase();
  }

  String _orderTypeDisplayLabel(dynamic raw) {
    final type = _normalizeOrderType(raw);
    switch (type) {
      case 'jual':
        return 'Jual';
      case 'buyback':
        return 'Buyback';
      case 'service':
        return 'Service';
      case 'custom':
        return 'Custom';
      case 'ambil':
      case 'pickup':
      case 'picked_up':
        return 'Ambil';
      default:
        if (type.isEmpty) return '-';
        return type
            .split(RegExp(r'[_\s-]+'))
            .where((e) => e.isNotEmpty)
            .map((w) => '${w[0].toUpperCase()}${w.substring(1)}')
            .join(' ');
    }
  }

  String _fakturHeading(dynamic raw) {
    final type = _normalizeOrderType(raw);
    switch (type) {
      case 'jual':
        return 'FAKTUR PENJUALAN';
      case 'buyback':
        return 'FAKTUR BUYBACK';
      case 'service':
        return 'FAKTUR SERVIS';
      case 'custom':
        return 'FAKTUR CUSTOM';
      case 'ambil':
      case 'pickup':
      case 'picked_up':
        return 'FAKTUR PENGAMBILAN';
      default:
        if (type.isEmpty) return 'FAKTUR ORDER';
        return 'FAKTUR ${_orderTypeDisplayLabel(type).toUpperCase()}';
    }
  }

  @override
  void initState() {
    super.initState();
    _branchTitleFuture = _resolveBranchTitle();
    _serviceCustomDpFuture = resolveFakturDpAmount(widget.orderData);
  }

  String _branchTitleFromOrderData() {
    final raw =
        widget.orderData['branch_name'] ??
        widget.orderData['nama_cabang'] ??
        widget.orderData['branchName'] ??
        widget.orderData['branch_name_text'];
    final s = raw?.toString().trim();
    if (s != null && s.isNotEmpty) return s;
    return '';
  }

  String _branchIdFromOrderData() {
    final raw =
        widget.orderData['branch_id'] ??
        widget.orderData['branchId'] ??
        widget.orderData['branch'];
    final s = raw?.toString().trim();
    if (s == null) return '';
    return s;
  }

  Future<String> _resolveBranchTitle() async {
    final fromData = _branchTitleFromOrderData();
    if (fromData.isNotEmpty) return fromData;

    final branchId = _branchIdFromOrderData();
    if (branchId.isEmpty) return 'VANESSA GOLD & DIAMOND';

    try {
      final url = '${NetworkConfig.baseUrl}/branches/$branchId';
      final resp = await http
          .get(Uri.parse(url), headers: NetworkConfig.defaultHeaders)
          .timeout(const Duration(seconds: 8));
      if (resp.statusCode != 200) return 'VANESSA GOLD & DIAMOND';
      final body = resp.body.trim();
      if (body.isEmpty) return 'VANESSA GOLD & DIAMOND';
      final decoded = jsonDecode(body);
      if (decoded is Map && decoded['name'] != null) {
        final name = decoded['name'].toString().trim();
        if (name.isNotEmpty) return name;
      }
    } catch (_) {}

    return 'VANESSA GOLD & DIAMOND';
  }

  String _fmtMoney(dynamic v) {
    final n = double.tryParse(v?.toString() ?? '');
    if (n == null) return v?.toString() ?? '0';
    return n
        .toStringAsFixed(0)
        .replaceAllMapped(
          RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
          (Match m) => '${m[1]}.',
        );
  }

  double _totalOrderRounded(Map<String, dynamic> od) {
    final rawJumlah = od['jumlah'];
    final rawTotal = od['total'];
    final j = double.tryParse(rawJumlah?.toString() ?? '');
    if (j != null) return (j / 5000).ceil() * 5000;
    final t = double.tryParse(rawTotal?.toString() ?? '') ?? 0;
    return (t / 5000).ceil() * 5000;
  }

  String? _photoUrl(dynamic raw) {
    final s = raw?.toString().trim();
    if (s == null || s.isEmpty) return null;
    if (s.startsWith('http://') || s.startsWith('https://')) return s;
    if (s.startsWith('/')) return '${NetworkConfig.baseUrl}$s';
    // Fallback: treat as relative filename or path
    return '${NetworkConfig.baseUrl}/uploads/$s';
  }

  @override
  Widget build(BuildContext context) {
    final orderData = widget.orderData;
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
        orderData['customer_name'] ??
        orderData['name'] ??
        orderData['customer'];
    final customerPhone =
        orderData['customer_phone'] ?? orderData['phone'] ?? orderData['no_hp'];
    final customerAddress =
        orderData['customer_address'] ??
        orderData['address'] ??
        orderData['alamat'];
    final orderNumber = (orderData['order_number'] ?? '').toString().trim();
    // QR = bukti order: isi nomor nota (scan di CS/kasir). Fallback order_id jika nota belum ada.
    final qrPayload = orderNumber.isNotEmpty
        ? orderNumber
        : (orderData['order_id'] ?? '').toString().trim();
    final orderType = orderData['order_type'];
    final fakturHeading = _fakturHeading(orderType);
    final orderTypeLabel = _orderTypeDisplayLabel(orderType);
    final svcFakturFields = (_normalizeOrderType(orderType) == 'service' ||
            _normalizeOrderType(orderType) == 'custom')
        ? fakturServiceCustomFieldRows(orderData)
        : const <String, String>{};
    final sisaAfterDpLabel =
        svcFakturFields['sisa_setelah_dp_row_label'] ?? 'Sisa estimasi';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Faktur Order'),
        actions: [
          if (_normalizeOrderType(orderType) == 'service' ||
              _normalizeOrderType(orderType) == 'custom')
            IconButton(
              icon: const Icon(Icons.receipt_long_outlined),
              tooltip: 'Cetak faktur pengambilan (AMBIL)',
              onPressed: () => printPickupServiceCustomFaktur(
                context,
                orderData,
              ),
            ),
          IconButton(
            icon: const Icon(Icons.print),
            tooltip: 'Cetak faktur order (referensi)',
            onPressed: () => printFakturOrder(context, orderData),
          ),
        ],
      ),
      body: ResponsiveLayout.scrollablePage(
        context: context,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Center(
              child: Text(
                fakturHeading,
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: Colors.blue[800],
                ),
              ),
            ),
            const SizedBox(height: 8),
            Center(
              child: FutureBuilder<String>(
                future: _branchTitleFuture,
                builder: (context, snapshot) {
                  final title =
                      (snapshot.data?.toString().trim().isNotEmpty ?? false)
                      ? snapshot.data!.toString().trim()
                      : 'VANESSA GOLD & DIAMOND';
                  return Text(
                    title,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  );
                },
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
                    if (qrPayload.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Center(
                        child: Column(
                          children: [
                            QrImageView(
                              data: qrPayload,
                              version: QrVersions.auto,
                              size: 160,
                              gapless: false,
                            ),
                            const SizedBox(height: 6),
                            Text(
                              orderNumber.isNotEmpty ? orderNumber : qrPayload,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    Text('Tipe Order: $orderTypeLabel'),
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
                        // Foto produk (jika ada)
                        if (_photoUrl(item['photo_produk']) != null) ...[
                          ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: AspectRatio(
                              aspectRatio: 16 / 9,
                              child: Image.network(
                                _photoUrl(item['photo_produk'])!,
                                fit: BoxFit.cover,
                                errorBuilder: (context, error, stackTrace) {
                                  return Container(
                                    color: Colors.grey.shade200,
                                    alignment: Alignment.center,
                                    child: const Text('Gagal memuat foto'),
                                  );
                                },
                                loadingBuilder:
                                    (context, child, loadingProgress) {
                                      if (loadingProgress == null) return child;
                                      final expected =
                                          loadingProgress.expectedTotalBytes;
                                      final loaded =
                                          loadingProgress.cumulativeBytesLoaded;
                                      final value =
                                          (expected != null && expected > 0)
                                          ? loaded / expected
                                          : null;
                                      return Container(
                                        color: Colors.grey.shade100,
                                        alignment: Alignment.center,
                                        child: CircularProgressIndicator(
                                          value: value,
                                        ),
                                      );
                                    },
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                        ],

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
                        Text('Total: Rp ${_fmtMoney(item['total'] ?? 0)}'),
                      ],
                    ),
                  ),
                ),
              ),

            if (_normalizeOrderType(orderType) == 'service' ||
                _normalizeOrderType(orderType) == 'custom') ...[
              const SizedBox(height: 24),
              Text(
                'Detail servis',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Card(
                elevation: 2,
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Builder(
                    builder: (context) {
                      final f = svcFakturFields;
                      if (f.isEmpty) return const SizedBox.shrink();
                      Widget row(String key, String label) {
                        final v = f[key] ?? '-';
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              SizedBox(
                                width: 132,
                                child: Text(
                                  label,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              Expanded(child: Text(v)),
                            ],
                          ),
                        );
                      }

                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          row('jenis_service', 'Jenis service'),
                          row('kelengkapan', 'Kelengkapan'),
                          row('catatan', 'Catatan'),
                          row(
                            'estimasi_biaya',
                            f['service_biaya_row_label'] ?? 'Estimasi biaya',
                          ),
                          row('estimasi_selesai', 'Estimasi selesai'),
                        ],
                      );
                    },
                  ),
                ),
              ),
            ],

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
                              final d = double.tryParse(
                                orderData['diskon'].toString(),
                              );
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
                    if (_normalizeOrderType(orderType) == 'service' ||
                        _normalizeOrderType(orderType) == 'custom')
                      FutureBuilder<double>(
                        future: _serviceCustomDpFuture,
                        builder: (context, snap) {
                          final dp = snap.hasData
                              ? snap.data!
                              : fakturDpFromPayloadSync(orderData);
                          if (dp <= 0) return const SizedBox.shrink();
                          final total = _totalOrderRounded(orderData);
                          final sisa = total > dp ? total - dp : 0.0;
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              const SizedBox(height: 8),
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text('Uang Muka (DP):'),
                                  Text(
                                    'Rp ${_fmtMoney(dp)}',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text('$sisaAfterDpLabel:'),
                                  Text(
                                    'Rp ${_fmtMoney(sisa)}',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w600,
                                      color: Colors.orange[900],
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          );
                        },
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
                                      final t = double.tryParse(orderData['total']?.toString() ?? '') ?? 0;
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

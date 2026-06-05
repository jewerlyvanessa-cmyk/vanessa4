import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:vanessa3/utils/faktur/faktur_payment_api.dart'
    show enrichOrderDataForFakturPrint;
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
  late Map<String, dynamic> _orderData;
  late final Future<String> _branchTitleFuture;
  late Future<double> _serviceCustomDpFuture;

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
    _orderData = Map<String, dynamic>.from(widget.orderData);
    _branchTitleFuture = _resolveBranchTitle();
    _serviceCustomDpFuture = resolveFakturDpAmount(_orderData);
    unawaited(_preloadFakturPrintContext());
  }

  /// Muat ringkasan bayar + logo cabang di background agar tombol cetak lebih cepat.
  Future<void> _preloadFakturPrintContext() async {
    await enrichOrderDataForFakturPrint(_orderData);
    if (!mounted) return;
    setState(() {
      _serviceCustomDpFuture = resolveFakturDpAmount(_orderData);
    });
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
    final orderData = _orderData;
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

    final normalizedType = _normalizeOrderType(orderType);
    final isServiceOrCustom =
        normalizedType == 'service' || normalizedType == 'custom';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Faktur Order'),
        actions: [
          if (isServiceOrCustom)
            IconButton(
              icon: const Icon(Icons.receipt_long_outlined),
              tooltip: 'Cetak faktur pengambilan (AMBIL)',
              onPressed: () => printPickupServiceCustomFaktur(context, _orderData),
            ),
          IconButton(
            icon: const Icon(Icons.print),
            tooltip: 'Cetak faktur order (referensi)',
            onPressed: () => printFakturOrder(context, _orderData),
          ),
        ],
      ),
      body: _buildFakturBody(
        context,
        orderData: orderData,
        items: items,
        fakturHeading: fakturHeading,
        orderTypeLabel: orderTypeLabel,
        orderType: orderType,
        isServiceOrCustom: isServiceOrCustom,
        customerName: customerName,
        customerPhone: customerPhone,
        customerAddress: customerAddress,
        orderNumber: orderNumber,
        qrPayload: qrPayload,
        svcFakturFields: svcFakturFields,
        sisaAfterDpLabel: sisaAfterDpLabel,
      ),
    );
  }

  /// Layar lebar (web PC): layout 2 kolom ringkas.
  /// Layar sempit: scroll vertikal seperti sebelumnya.
  Widget _buildFakturBody(
    BuildContext context, {
    required Map<String, dynamic> orderData,
    required List<dynamic> items,
    required String fakturHeading,
    required String orderTypeLabel,
    required dynamic orderType,
    required bool isServiceOrCustom,
    required dynamic customerName,
    required dynamic customerPhone,
    required dynamic customerAddress,
    required String orderNumber,
    required String qrPayload,
    required Map<String, String> svcFakturFields,
    required String sisaAfterDpLabel,
  }) {
    final content = _buildFakturContent(
      context,
      orderData: orderData,
      items: items,
      fakturHeading: fakturHeading,
      orderTypeLabel: orderTypeLabel,
      orderType: orderType,
      isServiceOrCustom: isServiceOrCustom,
      customerName: customerName,
      customerPhone: customerPhone,
      customerAddress: customerAddress,
      orderNumber: orderNumber,
      qrPayload: qrPayload,
      svcFakturFields: svcFakturFields,
      sisaAfterDpLabel: sisaAfterDpLabel,
      dense: !ResponsiveLayout.isMediumOrBelow(context),
    );

    if (ResponsiveLayout.isMediumOrBelow(context)) {
      return ResponsiveLayout.scrollablePage(
        context: context,
        child: content,
      );
    }

    final pad = ResponsiveLayout.pagePadding(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          physics: const ClampingScrollPhysics(),
          padding: EdgeInsets.fromLTRB(pad.left, 8, pad.right, 8),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Align(
              alignment: Alignment.topCenter,
              child: content,
            ),
          ),
        );
      },
    );
  }

  Widget _buildFakturContent(
    BuildContext context, {
    required Map<String, dynamic> orderData,
    required List<dynamic> items,
    required String fakturHeading,
    required String orderTypeLabel,
    required dynamic orderType,
    required bool isServiceOrCustom,
    required dynamic customerName,
    required dynamic customerPhone,
    required dynamic customerAddress,
    required String orderNumber,
    required String qrPayload,
    required Map<String, String> svcFakturFields,
    required String sisaAfterDpLabel,
    required bool dense,
  }) {
    final gap = dense ? 10.0 : 24.0;
    final sectionGap = dense ? 6.0 : 8.0;

    final header = _buildFakturHeader(context, fakturHeading, dense: dense);
    final orderInfo = _buildOrderInfoSection(
      context,
      orderData: orderData,
      orderTypeLabel: orderTypeLabel,
      customerName: customerName,
      customerPhone: customerPhone,
      customerAddress: customerAddress,
      orderNumber: orderNumber,
      qrPayload: qrPayload,
      dense: dense,
    );
    final itemsSection = _buildItemsSection(context, items: items, dense: dense);
    final serviceSection = isServiceOrCustom
        ? _buildServiceSection(context, svcFakturFields, dense: dense)
        : null;
    final summary = _buildSummarySection(
      context,
      orderData: orderData,
      orderType: orderType,
      isServiceOrCustom: isServiceOrCustom,
      sisaAfterDpLabel: sisaAfterDpLabel,
      dense: dense,
    );
    final footer = _buildFooterAndActions(context, dense: dense);

    if (!dense) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          header,
          SizedBox(height: gap),
          orderInfo,
          SizedBox(height: gap),
          itemsSection,
          if (serviceSection != null) ...[
            SizedBox(height: gap),
            serviceSection,
          ],
          SizedBox(height: gap),
          summary,
          SizedBox(height: gap),
          footer,
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        header,
        const SizedBox(height: 8),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 5,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  orderInfo,
                  if (serviceSection != null) ...[
                    SizedBox(height: sectionGap),
                    serviceSection,
                  ],
                ],
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 6,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  itemsSection,
                  SizedBox(height: sectionGap),
                  summary,
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        footer,
      ],
    );
  }

  Widget _buildFakturHeader(
    BuildContext context,
    String fakturHeading, {
    required bool dense,
  }) {
    return Column(
      children: [
        Text(
          fakturHeading,
          textAlign: TextAlign.center,
          style: (dense
                  ? Theme.of(context).textTheme.titleLarge
                  : Theme.of(context).textTheme.headlineMedium)
              ?.copyWith(
            fontWeight: FontWeight.bold,
            color: Colors.blue[800],
          ),
        ),
        SizedBox(height: dense ? 4 : 8),
        FutureBuilder<String>(
          future: _branchTitleFuture,
          builder: (context, snapshot) {
            final title =
                (snapshot.data?.toString().trim().isNotEmpty ?? false)
                ? snapshot.data!.toString().trim()
                : 'VANESSA GOLD & DIAMOND';
            return Text(
              title,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            );
          },
        ),
        Divider(height: dense ? 12 : 32, thickness: dense ? 1 : 2),
      ],
    );
  }

  Widget _buildOrderInfoSection(
    BuildContext context, {
    required Map<String, dynamic> orderData,
    required String orderTypeLabel,
    required dynamic customerName,
    required dynamic customerPhone,
    required dynamic customerAddress,
    required String orderNumber,
    required String qrPayload,
    required bool dense,
  }) {
    final createdAt = orderData['created_at'] != null
        ? DateTime.parse(orderData['created_at'])
            .toLocal()
            .toString()
            .split('.')[0]
        : '-';

    Widget infoLine(String text) => Text(
          text,
          style: TextStyle(fontSize: dense ? 13 : null),
        );

    final details = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        infoLine('Order ID: ${orderData['order_id'] ?? '-'}'),
        infoLine('Order Number: ${orderData['order_number'] ?? '-'}'),
        infoLine('Tipe Order: $orderTypeLabel'),
        infoLine('Status: ${orderData['status'] ?? '-'}'),
        infoLine('Tanggal: $createdAt'),
        infoLine('Customer: ${customerName ?? '-'}'),
        infoLine('No. HP: ${customerPhone ?? '-'}'),
        infoLine('Alamat: ${customerAddress ?? '-'}'),
      ],
    );

    final qrSize = dense ? 88.0 : 160.0;
    final qrWidget = qrPayload.isNotEmpty
        ? Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              QrImageView(
                data: qrPayload,
                version: QrVersions.auto,
                size: qrSize,
                gapless: false,
              ),
              SizedBox(height: dense ? 2 : 6),
              Text(
                orderNumber.isNotEmpty ? orderNumber : qrPayload,
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: dense ? 12 : null,
                ),
              ),
            ],
          )
        : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Informasi Order',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        SizedBox(height: dense ? 4 : 8),
        Card(
          elevation: 2,
          child: Padding(
            padding: EdgeInsets.all(dense ? 10 : 16),
            child: dense && qrWidget != null
                ? Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: details),
                      const SizedBox(width: 8),
                      qrWidget,
                    ],
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      details,
                      if (qrWidget != null) ...[
                        SizedBox(height: dense ? 8 : 12),
                        Center(child: qrWidget),
                      ],
                    ],
                  ),
          ),
        ),
      ],
    );
  }

  Widget _buildItemsSection(
    BuildContext context, {
    required List<dynamic> items,
    required bool dense,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Detail Item',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        SizedBox(height: dense ? 4 : 8),
        if (items.isEmpty)
          Card(
            child: Padding(
              padding: EdgeInsets.all(dense ? 10 : 16),
              child: const Text('Tidak ada item dalam order ini'),
            ),
          )
        else
          ...items.map((item) => _buildItemCard(context, item, dense: dense)),
      ],
    );
  }

  Widget _buildItemCard(
    BuildContext context,
    dynamic item, {
    required bool dense,
  }) {
    final photoUrl = _photoUrl(item['photo_produk']);
    final hargaPerGram = double.tryParse(
          (item['harga_per_gram'] ?? 0).toString(),
        )
            ?.toStringAsFixed(0)
            .replaceAllMapped(
              RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
              (Match m) => '${m[1]}.',
            ) ??
        (item['harga_per_gram'] ?? 0).toString();

    final details = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Kode: ${item['kode_produk'] ?? '-'}',
          style: TextStyle(fontSize: dense ? 13 : null),
        ),
        Text(
          item['nama_item'] ?? 'Unknown Item',
          style: TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: dense ? 14 : 16,
          ),
        ),
        Text(
          'Berat: ${item['weight'] ?? '-'}g',
          style: TextStyle(fontSize: dense ? 13 : null),
        ),
        Text(
          'Harga/g: Rp $hargaPerGram',
          style: TextStyle(fontSize: dense ? 13 : null),
        ),
        Text(
          'Total: Rp ${_fmtMoney(item['total'] ?? 0)}',
          style: TextStyle(fontSize: dense ? 13 : null),
        ),
      ],
    );

    Widget? photo;
    if (photoUrl != null) {
      photo = ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: dense
            ? Image.network(
                photoUrl,
                width: 120,
                height: 90,
                fit: BoxFit.cover,
                headers: NetworkConfig.imageHeaders,
                errorBuilder: (context, error, stackTrace) {
                  return Container(
                    width: 120,
                    height: 90,
                    color: Colors.grey.shade200,
                    alignment: Alignment.center,
                    child: const Text(
                      'Gagal memuat foto',
                      style: TextStyle(fontSize: 11),
                    ),
                  );
                },
                loadingBuilder: (context, child, loadingProgress) {
                  if (loadingProgress == null) return child;
                  return Container(
                    width: 120,
                    height: 90,
                    color: Colors.grey.shade100,
                    alignment: Alignment.center,
                    child: const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  );
                },
              )
            : AspectRatio(
                aspectRatio: 16 / 9,
                child: Image.network(
                  photoUrl,
                  fit: BoxFit.cover,
                  headers: NetworkConfig.imageHeaders,
                  errorBuilder: (context, error, stackTrace) {
                    return Container(
                      color: Colors.grey.shade200,
                      alignment: Alignment.center,
                      child: const Text('Gagal memuat foto'),
                    );
                  },
                  loadingBuilder: (context, child, loadingProgress) {
                    if (loadingProgress == null) return child;
                    final expected = loadingProgress.expectedTotalBytes;
                    final loaded = loadingProgress.cumulativeBytesLoaded;
                    final value = (expected != null && expected > 0)
                        ? loaded / expected
                        : null;
                    return Container(
                      color: Colors.grey.shade100,
                      alignment: Alignment.center,
                      child: CircularProgressIndicator(value: value),
                    );
                  },
                ),
              ),
      );
    }

    return Card(
      elevation: 1,
      margin: EdgeInsets.only(bottom: dense ? 6 : 8),
      child: Padding(
        padding: EdgeInsets.all(dense ? 10 : 16),
        child: dense && photo != null
            ? Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  photo,
                  const SizedBox(width: 10),
                  Expanded(child: details),
                ],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (photo != null) ...[
                    photo,
                    SizedBox(height: dense ? 8 : 12),
                  ],
                  details,
                ],
              ),
      ),
    );
  }

  Widget _buildServiceSection(
    BuildContext context,
    Map<String, String> fields, {
    required bool dense,
  }) {
    if (fields.isEmpty) return const SizedBox.shrink();

    Widget row(String key, String label) {
      final v = fields[key] ?? '-';
      return Padding(
        padding: EdgeInsets.only(bottom: dense ? 4 : 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: dense ? 108 : 132,
              child: Text(
                label,
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: dense ? 12 : null,
                ),
              ),
            ),
            Expanded(
              child: Text(v, style: TextStyle(fontSize: dense ? 12 : null)),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Detail servis',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        SizedBox(height: dense ? 4 : 8),
        Card(
          elevation: 2,
          child: Padding(
            padding: EdgeInsets.all(dense ? 10 : 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                row('jenis_service', 'Jenis service'),
                row('kelengkapan', 'Kelengkapan'),
                row('catatan', 'Catatan'),
                row(
                  'estimasi_biaya',
                  fields['service_biaya_row_label'] ?? 'Estimasi biaya',
                ),
                row('estimasi_selesai', 'Estimasi selesai'),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSummarySection(
    BuildContext context, {
    required Map<String, dynamic> orderData,
    required dynamic orderType,
    required bool isServiceOrCustom,
    required String sisaAfterDpLabel,
    required bool dense,
  }) {
    return Card(
      elevation: 3,
      color: Colors.blue[50],
      child: Padding(
        padding: EdgeInsets.all(dense ? 10 : 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Ringkasan Order',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            SizedBox(height: dense ? 4 : 8),
            if (orderData['diskon'] != null && orderData['diskon'] != '0.00')
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Diskon:', style: TextStyle(fontSize: dense ? 13 : null)),
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
                    style: TextStyle(
                      color: Colors.red,
                      fontSize: dense ? 13 : null,
                    ),
                  ),
                ],
              ),
            if (isServiceOrCustom)
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
                      SizedBox(height: dense ? 4 : 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Uang Muka (DP):',
                            style: TextStyle(fontSize: dense ? 13 : null),
                          ),
                          Text(
                            'Rp ${_fmtMoney(dp)}',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: dense ? 13 : null,
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: dense ? 2 : 4),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            '$sisaAfterDpLabel:',
                            style: TextStyle(fontSize: dense ? 13 : null),
                          ),
                          Text(
                            'Rp ${_fmtMoney(sisa)}',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: Colors.orange[900],
                              fontSize: dense ? 13 : null,
                            ),
                          ),
                        ],
                      ),
                    ],
                  );
                },
              ),
            SizedBox(height: dense ? 4 : 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Total Order:',
                  style: TextStyle(
                    fontSize: dense ? 15 : 18,
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
                              return (t / 5000).ceil() * 5000;
                            })()))}'
                      : 'Rp 0',
                  style: TextStyle(
                    fontSize: dense ? 15 : 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.green,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFooterAndActions(BuildContext context, {required bool dense}) {
    final printedAt =
        DateTime.now().toLocal().toString().split('.')[0];

    if (dense) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Terima kasih atas kunjungan Anda!',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
              Text(
                'Dicetak: $printedAt',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Colors.grey[600],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 36,
                  child: ElevatedButton.icon(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.arrow_back, size: 18),
                    label: const Text('Kembali'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.grey,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: SizedBox(
                  height: 36,
                  child: ElevatedButton.icon(
                    onPressed: () => Navigator.of(
                      context,
                    ).popUntil((route) => route.isFirst),
                    icon: const Icon(Icons.home, size: 18),
                    label: const Text('Beranda'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Center(
          child: Column(
            children: [
              Text(
                'Terima kasih atas kunjungan Anda!',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Text(
                'Faktur ini dicetak pada: $printedAt',
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: Colors.grey[600]),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
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
                onPressed: () =>
                    Navigator.of(context).popUntil((route) => route.isFirst),
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
    );
  }
}

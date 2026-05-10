import 'package:flutter/material.dart';
import 'dart:convert';
import 'dart:math' as math;
import 'package:http/http.dart' as http;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:io';
import 'package:vanessa3/widgets/qr_scan_route.dart';

// Conditional imports for platform-specific packages
import 'package:image_picker/image_picker.dart'
    if (dart.library.html) '../../../utils/image_picker_stub.dart';
import 'package:vanessa3/providers/user_state_provider.dart';
import 'package:vanessa3/utils/network_config.dart';
import 'package:vanessa3/core/theme/app_typography.dart';

class AmbilPage extends ConsumerStatefulWidget {
  const AmbilPage({super.key, this.client});

  final http.Client? client;

  @override
  ConsumerState<AmbilPage> createState() => _AmbilPageState();
}

class _AmbilPageState extends ConsumerState<AmbilPage> {
  final _formKey = GlobalKey<FormState>();

  // Controllers untuk form
  final TextEditingController _orderNumberController = TextEditingController();
  final TextEditingController _customerController = TextEditingController();
  final TextEditingController _customerPhoneController =
      TextEditingController();
  final TextEditingController _namaItemController = TextEditingController();
  final TextEditingController _beratController = TextEditingController();
  final TextEditingController _estimasiBiayaController = TextEditingController();
  final TextEditingController _dpController = TextEditingController();
  final TextEditingController _keteranganController = TextEditingController();

  File? _fotoFile;
  bool _isLoading = false;
  List<dynamic> _readyItems = [];
  bool _isLoadingItems = false;
  int? _selectedOrderId;

  static const Set<String> _allowedReadyPickupOrderTypes = {'service', 'custom'};

  @override
  void dispose() {
    _orderNumberController.dispose();
    _customerController.dispose();
    _customerPhoneController.dispose();
    _namaItemController.dispose();
    _beratController.dispose();
    _estimasiBiayaController.dispose();
    _dpController.dispose();
    _keteranganController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _loadReadyItems();
  }

  Future<void> _loadReadyItems() async {
    setState(() => _isLoadingItems = true);
    try {
      final userState = ref.read(userStateProvider);
      final baseUrl = NetworkConfig.baseUrl;

      final response = await (widget.client ?? http.Client()).get(
        Uri.parse(
          '$baseUrl/orders?branch_id=${userState.branch}&status=ready_for_pickup',
        ),
        headers: NetworkConfig.defaultHeaders,
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          final rows = data is List ? data : const [];
          _readyItems =
              rows.where((row) {
                if (row is! Map) return false;
                final type = (row['order_type'] ?? '').toString().toLowerCase();
                return _allowedReadyPickupOrderTypes.contains(type);
              }).toList();
        });
      }
    } catch (e) {
      debugPrint('Error loading ready items: $e');
    } finally {
      setState(() => _isLoadingItems = false);
    }
  }

  Future<void> _scanQRCode() async {
    final result = await pushQrScanPage(
      context,
      title: 'Scan QR Code',
      showTorchActions: true,
      appBarBackgroundColor: Colors.blue,
    );

    if (!mounted || result == null || result.isEmpty) return;
    setState(() {
      _orderNumberController.text = result;
    });
  }

  Future<String?> _uploadFoto(File? foto) async {
    if (foto == null) return null;
    final storageUrl = NetworkConfig.storageUrl;
    final uri = Uri.parse('$storageUrl/upload');
    final request = http.MultipartRequest('POST', uri)
      ..files.add(await http.MultipartFile.fromPath('file', foto.path));
    final token = NetworkConfig.authToken;
    if (token != null && token.isNotEmpty) {
      request.headers['Authorization'] = 'Bearer $token';
      request.headers['Accept'] = 'application/json';
    }
    final response = await request.send();
    if (response.statusCode == 200) {
      final respStr = await response.stream.bytesToString();
      final data = jsonDecode(respStr);
      return data['url'] ?? data['fileUrl'] ?? data['path'];
    }
    return null;
  }

  Future<void> _fetchAndApplyPaymentSummary(int orderId) async {
    try {
      final baseUrl = NetworkConfig.baseUrl;
      final resp = await (widget.client ?? http.Client()).get(
        Uri.parse('$baseUrl/orders/payment-summary?order_id=$orderId'),
        headers: NetworkConfig.defaultHeaders,
      );
      if (resp.statusCode != 200) return;
      final decoded = jsonDecode(resp.body);
      if (decoded is! Map) return;
      final m = Map<String, dynamic>.from(decoded);
      final total = m['total'];
      final dp = m['dp_amount'];
      setState(() {
        _estimasiBiayaController.text = (total ?? 0).toString();
        _dpController.text = (dp ?? 0).toString();
      });
    } catch (_) {
      // ignore
    }
  }

  void _applyReadyOrderToForm(Map<String, dynamic> order) {
    final id = int.tryParse(order['order_id']?.toString() ?? '');
    setState(() {
      _selectedOrderId = id;
      _orderNumberController.text = (order['order_number'] ?? '').toString();
      _customerController.text = (order['customer_name'] ?? '').toString();
      _customerPhoneController.text =
          (order['customer_phone'] ?? order['phone'] ?? '').toString();
      _namaItemController.text =
          (order['nama_item'] ?? order['item_name'] ?? '').toString();
      _beratController.text = (order['berat'] ?? order['weight'] ?? '').toString();
      _estimasiBiayaController.text = (order['total'] ?? 0).toString();
      _dpController.text = '0';
    });
    if (id != null) {
      _fetchAndApplyPaymentSummary(id);
    }
  }

  Future<void> _submitForm() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      final userState = ref.read(userStateProvider);
      final branchId = int.tryParse(userState.branch);
      final userId = userState.userId;

      if (branchId == null || userId == null) {
        throw Exception('User belum login atau branch belum dipilih');
      }

      String? fotoUrl;
      if (_fotoFile != null) {
        fotoUrl = await _uploadFoto(_fotoFile);
      }

      final baseUrl = NetworkConfig.baseUrl;
      final response = await (widget.client ?? http.Client()).post(
        Uri.parse('$baseUrl/orders/pickup'),
        headers: NetworkConfig.defaultHeaders,
        body: jsonEncode({
          'branch_id': branchId,
          'order_id': _selectedOrderId,
          'order_number': _orderNumberController.text.trim(),
          'notes': _keteranganController.text.trim(),
          'photo_url': fotoUrl,
        }),
      );

      if (response.statusCode == 200) {
        await _loadReadyItems();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Barang berhasil diambil')),
          );
        }
      } else {
        throw Exception('Gagal proses ambil barang: ${response.body}');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.gallery);

    if (pickedFile != null) {
      setState(() {
        _fotoFile = File(pickedFile.path);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Ambil Barang'),
        // follow global AppBarTheme (primary background)
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // No. Order
              Row(
                children: [
                  const SizedBox(
                    width: 120,
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text('No. Order'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextFormField(
                      controller: _orderNumberController,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        hintText: 'Nomor order',
                      ),
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'No. Order wajib diisi';
                        }
                        return null;
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    onPressed: _scanQRCode,
                    icon: const Icon(Icons.qr_code_scanner),
                    tooltip: 'Scan QR Code',
                    color: cs.primary,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // Customer
              Row(
                children: [
                  const SizedBox(
                    width: 120,
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text('Customer'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextFormField(
                      controller: _customerController,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        hintText: 'Nama pelanggan',
                      ),
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Customer wajib diisi';
                        }
                        return null;
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // No. HP
              Row(
                children: [
                  const SizedBox(
                    width: 120,
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text('No. HP'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextFormField(
                      controller: _customerPhoneController,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        hintText: 'Nomor HP pelanggan',
                      ),
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'No. HP wajib diisi';
                        }
                        return null;
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // Nama Item
              Row(
                children: [
                  const SizedBox(
                    width: 120,
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text('Nama Item'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextFormField(
                      controller: _namaItemController,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        hintText: 'Nama barang yang diambil',
                      ),
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Nama item wajib diisi';
                        }
                        return null;
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // Berat
              Row(
                children: [
                  const SizedBox(
                    width: 120,
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text('Berat'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextFormField(
                      controller: _beratController,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        hintText: 'Berat dalam gram',
                      ),
                      keyboardType: TextInputType.number,
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Berat wajib diisi';
                        }
                        return null;
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // Estimasi Biaya + DP (read-only, dari order service/custom)
              Row(
                children: [
                  const SizedBox(
                    width: 120,
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text('Estimasi Biaya'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextFormField(
                      controller: _estimasiBiayaController,
                      readOnly: true,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        prefixText: 'Rp ',
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  const SizedBox(
                    width: 120,
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text('DP'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextFormField(
                      controller: _dpController,
                      readOnly: true,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        prefixText: 'Rp ',
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // Keterangan
              Row(
                children: [
                  const SizedBox(
                    width: 120,
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text('Keterangan'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextFormField(
                      controller: _keteranganController,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        hintText: 'Keterangan pengambilan',
                      ),
                      maxLines: 3,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // Foto
              Row(
                children: [
                  const SizedBox(
                    width: 120,
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text('Foto'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _pickImage,
                      icon: const Icon(Icons.photo),
                      label: const Text('Pilih Foto'),
                    ),
                  ),
                ],
              ),
              if (_fotoFile != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8.0),
                  child: Row(
                    children: [
                      const SizedBox(width: 128),
                      Container(
                        width: 100,
                        height: 100,
                        decoration: BoxDecoration(
                          border: Border.all(color: cs.outlineVariant),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Image.file(_fotoFile!, fit: BoxFit.cover),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 24),

              // Submit Button
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _isLoading ? null : _submitForm,
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: _isLoading
                      ? SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: cs.onPrimary,
                          ),
                        )
                      : Text(
                          'SIMPAN',
                          style: TextStyle(
                            fontSize: AppTypography.section,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                ),
              ),
              const SizedBox(height: 24),

              // Daftar Barang Siap Ambil
              Text(
                'DAFTAR BARANG SIAP AMBIL',
                style: TextStyle(
                  fontSize: AppTypography.section,
                  fontWeight: FontWeight.bold,
                  color: cs.primary,
                ),
              ),
              const SizedBox(height: 12),
              if (_isLoadingItems)
                const Center(child: CircularProgressIndicator())
              else if (_readyItems.isEmpty)
                Center(
                  child: Text(
                    'Tidak ada barang siap ambil',
                    style: TextStyle(color: cs.onSurfaceVariant),
                  ),
                )
              else
                LayoutBuilder(
                  builder: (context, c) {
                    final cs = Theme.of(context).colorScheme;
final rows = <DataRow>[];
                    for (var i = 0; i < _readyItems.length; i++) {
                      final item = _readyItems[i] as Map;
                      rows.add(
                        DataRow(
                          onSelectChanged: (_) {
                            _applyReadyOrderToForm(
                              Map<String, dynamic>.from(item),
                            );
                          },
                          color: WidgetStateProperty.resolveWith((s) {
                            if (s.contains(WidgetState.hovered)) {
                              return cs.primary.withValues(alpha: 0.06);
                            }
                            return i.isOdd
                                ? cs.surfaceContainerHighest
                                    .withValues(alpha: 0.45)
                                : null;
                          }),
                          cells: [
                            DataCell(
                              Text(
                                '${item['order_number'] ?? '—'}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            DataCell(Text('${item['customer_name'] ?? '—'}')),
                            DataCell(Text('${item['nama_item'] ?? '—'}')),
                            DataCell(
                              Text('${item['berat'] ?? '—'} gr'),
                            ),
                            DataCell(Text('${item['customer_phone'] ?? '—'}')),
                          ],
                        ),
                      );
                    }
                    final tableH = math.max(
                      200.0,
                      48 + _readyItems.length * 52.0,
                    );
                    return SizedBox(
                      height: tableH,
                      child: Material(
                        elevation: 0,
                        color: cs.surfaceContainerLow.withValues(alpha: 0.65),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(
                            color: cs.outlineVariant.withValues(alpha: 0.45),
                          ),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: Scrollbar(
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: ConstrainedBox(
                              constraints: BoxConstraints(minWidth: c.maxWidth),
                              child: DataTable(
                                headingRowColor: WidgetStateProperty.all(
                                  cs.surfaceContainerHigh,
                                ),
dataRowMinHeight: 44,
                                dataRowMaxHeight: 56,
                                columnSpacing: 12,
                                horizontalMargin: 10,
                                showCheckboxColumn: false,
                                dividerThickness: 0.5,
                                columns: [
                                  DataColumn(label: dataTableColumnLabel('No. Order')),
                                  DataColumn(label: dataTableColumnLabel('Pelanggan')),
                                  DataColumn(label: dataTableColumnLabel('Item')),
                                  DataColumn(label: dataTableColumnLabel('Berat')),
                                  DataColumn(label: dataTableColumnLabel('No. HP')),
                                ],
                                rows: rows,
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }
}

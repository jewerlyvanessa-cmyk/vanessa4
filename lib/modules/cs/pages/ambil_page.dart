import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:convert';
import 'dart:typed_data';
import 'dart:math' as math;
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:vanessa3/widgets/qr_scan_route.dart';

// Conditional imports for platform-specific packages
import 'package:image_picker/image_picker.dart'
    if (dart.library.html) '../../../utils/image_picker_stub.dart';
import 'package:vanessa3/providers/user_state_provider.dart';
import 'package:vanessa3/utils/network_config.dart';
import 'package:vanessa3/utils/faktur_print.dart'
    show printPickupServiceCustomFaktur;
import 'package:vanessa3/core/theme/app_typography.dart';
import 'package:intl/intl.dart';

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
  final TextEditingController _estimasiBiayaController =
      TextEditingController();
  final TextEditingController _dpController = TextEditingController();
  final TextEditingController _keteranganController = TextEditingController();

  File? _fotoFile;
  Uint8List? _fotoBytes;
  String? _fotoName;
  bool _isLoading = false;
  bool _loadingOrderLookup = false;
  List<dynamic> _readyItems = [];
  bool _isLoadingItems = false;
  int? _selectedOrderId;

  static const Set<String> _allowedReadyPickupOrderTypes = {
    'service',
    'custom',
  };

  bool get _hasFoto =>
      (_fotoBytes != null && _fotoBytes!.isNotEmpty) || _fotoFile != null;

  static double _parseLooseAmount(String raw) {
    var t = raw.trim();
    if (t.isEmpty) return 0;
    t = t.replaceAll(RegExp(r'[^0-9.,]'), '');
    if (t.isEmpty) return 0;
    if (t.contains(',') && !t.contains('.')) {
      t = t.replaceAll(',', '.');
    } else {
      t = t.replaceAll('.', '');
    }
    return double.tryParse(t) ?? 0;
  }

  static String _fmtRpDots(double v) {
    return NumberFormat('#,###', 'id_ID').format(v.round());
  }

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
          _readyItems = rows.where((row) {
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
    await _loadOrderFromOrderNumberField();
  }

  MediaType _detectImageMediaType(String name) {
    final lower = name.toLowerCase();
    if (lower.endsWith('.png')) return MediaType('image', 'png');
    if (lower.endsWith('.webp')) return MediaType('image', 'webp');
    return MediaType('image', 'jpeg');
  }

  Future<String?> _uploadFoto() async {
    if (!_hasFoto) return null;
    final storageUrl = NetworkConfig.storageUrl;
    final uri = Uri.parse('$storageUrl/upload');
    final request = http.MultipartRequest('POST', uri);
    if (kIsWeb) {
      final bytes = _fotoBytes;
      if (bytes == null || bytes.isEmpty) return null;
      final name = (_fotoName != null && _fotoName!.trim().isNotEmpty)
          ? _fotoName!.trim()
          : 'foto.jpg';
      request.files.add(
        http.MultipartFile.fromBytes(
          'file',
          bytes,
          filename: name,
          contentType: _detectImageMediaType(name),
        ),
      );
    } else {
      final foto = _fotoFile;
      if (foto == null) return null;
      request.files.add(await http.MultipartFile.fromPath('file', foto.path));
    }
    final token = NetworkConfig.authToken;
    if (token != null && token.isNotEmpty) {
      request.headers['Authorization'] = 'Bearer $token';
      request.headers['Accept'] = 'application/json';
    }
    final response = await request.send();
    if (response.statusCode == 200) {
      final respStr = await response.stream.bytesToString();
      final data = jsonDecode(respStr);
      final raw = data['url'] ?? data['fileUrl'] ?? data['path'];
      if (raw is String && raw.startsWith('/')) {
        return '$storageUrl$raw';
      }
      return raw?.toString();
    }
    return null;
  }

  /// GET satu order (service/custom) dari nomor nota — sama sumber dengan cetak faktur ambil.
  Future<Map<String, dynamic>?> _fetchOrderByOrderNumber(String raw) async {
    final num = raw.trim();
    if (num.isEmpty) return null;
    try {
      final baseUrl = NetworkConfig.baseUrl;
      final r = await (widget.client ?? http.Client()).get(
        Uri.parse(
          '$baseUrl/orders?order_number=${Uri.encodeQueryComponent(num)}',
        ),
        headers: NetworkConfig.defaultHeaders,
      );
      if (r.statusCode != 200) return null;
      final body = r.body.trim();
      if (body.isEmpty || body == 'null') return null;
      final decoded = jsonDecode(r.body);
      if (decoded == null) return null;
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } catch (e) {
      debugPrint('fetch order by number: $e');
    }
    return null;
  }

  /// Isi form dari baris daftar **atau** payload lengkap `GET /orders?order_number=`.
  void _applyOrderPayloadToForm(Map<String, dynamic> order) {
    final id = int.tryParse(order['order_id']?.toString() ?? '');
    final items = order['items'] as List<dynamic>? ?? [];
    Map<String, dynamic> it = {};
    if (items.isNotEmpty && items.first is Map) {
      it = Map<String, dynamic>.from(items.first as Map);
    }
    final namaItem =
        (order['nama_item'] ??
                order['item_name'] ??
                it['nama_item'] ??
                it['name'] ??
                '')
            .toString();
    final beratRaw =
        order['berat'] ?? order['weight'] ?? it['weight'] ?? it['berat'];
    setState(() {
      _selectedOrderId = id;
      _orderNumberController.text = (order['order_number'] ?? '').toString();
      _customerController.text = (order['customer_name'] ?? order['name'] ?? '')
          .toString();
      _customerPhoneController.text =
          (order['customer_phone'] ?? order['phone'] ?? order['no_hp'] ?? '')
              .toString();
      _namaItemController.text = namaItem;
      _beratController.text = beratRaw?.toString() ?? '';
      _estimasiBiayaController.text = (order['total'] ?? 0).toString();
      _dpController.text = '0';
    });
    if (id != null) {
      _fetchAndApplyPaymentSummary(id);
    }
  }

  /// Muat service/custom dari nomor nota (keyboard Enter, ikon cari, atau scan QR).
  Future<bool> _loadOrderFromOrderNumberField({bool quiet = false}) async {
    final num = _orderNumberController.text.trim();
    if (num.isEmpty) {
      if (!quiet && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Isi nomor nota order service atau custom'),
          ),
        );
      }
      return false;
    }
    setState(() => _loadingOrderLookup = true);
    try {
      final order = await _fetchOrderByOrderNumber(num);
      if (!mounted) return false;
      if (order == null) {
        if (!quiet) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Order tidak ditemukan')),
          );
        }
        return false;
      }
      final type = (order['order_type'] ?? '').toString().toLowerCase();
      if (!_allowedReadyPickupOrderTypes.contains(type)) {
        if (!quiet) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Nomor ini bukan order Service atau Custom'),
            ),
          );
        }
        return false;
      }
      _applyOrderPayloadToForm(order);
      if (!quiet && mounted) {
        final st = (order['status'] ?? '').toString();
        if (st.toLowerCase() != 'ready_for_pickup') {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Data dimuat ($type). Status: $st — pastikan siap diambil sebelum simpan.',
              ),
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Data order $type #$num dimuat')),
          );
        }
      }
      return true;
    } finally {
      if (mounted) setState(() => _loadingOrderLookup = false);
    }
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
    _applyOrderPayloadToForm(Map<String, dynamic>.from(order));
  }

  Future<void> _submitForm() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      if (_selectedOrderId == null) {
        final ok = await _loadOrderFromOrderNumberField(quiet: true);
        if (!ok) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'Muat data gagal: pastikan nomor nota benar (order service/custom), ketik lalu ikon cari, atau pilih dari daftar.',
                ),
              ),
            );
          }
          return;
        }
      }

      final userState = ref.read(userStateProvider);
      final branchId = int.tryParse(userState.branch);
      final userId = userState.userId;

      if (branchId == null || userId == null) {
        throw Exception('User belum login atau branch belum dipilih');
      }

      String? fotoUrl;
      if (_hasFoto) {
        fotoUrl = await _uploadFoto();
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

  Future<Map<String, dynamic>?> _fetchFullOrderForPickupFaktur() async {
    return _fetchOrderByOrderNumber(_orderNumberController.text);
  }

  Future<void> _printPickupFaktur() async {
    final data = await _fetchFullOrderForPickupFaktur();
    if (!mounted) return;
    if (data == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Order tidak ditemukan — periksa nomor nota / scan QR'),
        ),
      );
      return;
    }
    final type = (data['order_type'] ?? '').toString().toLowerCase();
    if (type != 'service' && type != 'custom') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Hanya untuk order service atau custom')),
      );
      return;
    }
    if (!mounted) return;
    await printPickupServiceCustomFaktur(context, data);
  }

  Future<void> _pickImage() async {
    if (kIsWeb) {
      try {
        final picked = await FilePicker.platform.pickFiles(
          type: FileType.image,
          allowMultiple: false,
          withData: true,
        );
        final f = picked?.files.single;
        if (f == null) return;
        final bytes = f.bytes;
        if (bytes == null || bytes.isEmpty) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'Tidak bisa membaca file gambar. Coba file lain (JPEG/PNG).',
                ),
              ),
            );
          }
          return;
        }
        setState(() {
          _fotoBytes = bytes;
          _fotoName = f.name.isNotEmpty ? f.name : 'foto.jpg';
          _fotoFile = null;
        });
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Gagal pilih gambar: $e')));
        }
      }
      return;
    }

    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.gallery);

    if (pickedFile != null) {
      setState(() {
        _fotoFile = File(pickedFile.path);
        _fotoBytes = null;
        _fotoName = null;
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
              // No. Order (service & custom — muat dari server)
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
                      textInputAction: TextInputAction.search,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        hintText: 'Nomor nota service / custom',
                      ),
                      onFieldSubmitted: (_) {
                        _loadOrderFromOrderNumberField();
                      },
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'No. Order wajib diisi';
                        }
                        return null;
                      },
                    ),
                  ),
                  const SizedBox(width: 4),
                  IconButton(
                    onPressed: _loadingOrderLookup
                        ? null
                        : _loadOrderFromOrderNumberField,
                    icon: _loadingOrderLookup
                        ? SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: cs.primary,
                            ),
                          )
                        : Icon(Icons.search, color: cs.primary),
                    tooltip: 'Muat data order service/custom',
                  ),
                  IconButton(
                    onPressed: _loadingOrderLookup ? null : _scanQRCode,
                    icon: const Icon(Icons.qr_code_scanner),
                    tooltip: 'Scan QR Code',
                    color: cs.primary,
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.only(left: 128, top: 4),
                child: Text(
                  'Ketik nomor nota lalu Enter atau ikon cari — data diambil dari order Service & Custom.',
                  style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                ),
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
              // Total tagihan + DP (read-only, dari server)
              Row(
                children: [
                  const SizedBox(
                    width: 120,
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text('Total tagihan'),
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
              // Selisih = Total tagihan − Uang muka (Kurang Bayar vs Sisa Uang Muka)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(
                    width: 120,
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text('Kurang /\nSisa Uang Muka'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Builder(
                      builder: (context) {
                        final total = _parseLooseAmount(
                          _estimasiBiayaController.text,
                        );
                        final dp = _parseLooseAmount(_dpController.text);
                        final diff = total - dp;
                        final absStr = _fmtRpDots(diff.abs());
                        final scheme = Theme.of(context).colorScheme;
                        final (String caption, Color valueColor) = diff > 0
                            ? ('Kurang Bayar', scheme.error)
                            : diff < 0
                            ? ('Sisa Uang Muka', scheme.tertiary)
                            : ('Lunas', scheme.onSurfaceVariant);
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            InputDecorator(
                              decoration: const InputDecoration(
                                border: OutlineInputBorder(),
                                prefixText: 'Rp ',
                              ),
                              child: Text(
                                absStr,
                                style: Theme.of(context).textTheme.titleMedium
                                    ?.copyWith(
                                      fontWeight: FontWeight.w700,
                                      color: valueColor,
                                    ),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '$caption · = Total tagihan − Uang muka',
                              style: TextStyle(
                                fontSize: 12,
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        );
                      },
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
                      icon: Icon(kIsWeb ? Icons.upload_file : Icons.photo),
                      label: Text(kIsWeb ? 'Pilih file gambar' : 'Pilih Foto'),
                    ),
                  ),
                ],
              ),
              if (_hasFoto)
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
                        child: _fotoBytes != null
                            ? Image.memory(_fotoBytes!, fit: BoxFit.cover)
                            : Image.file(_fotoFile!, fit: BoxFit.cover),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 24),

              OutlinedButton.icon(
                onPressed: _isLoading ? null : _printPickupFaktur,
                icon: const Icon(Icons.print_outlined),
                label: const Text('Cetak faktur pengambilan (AMBIL)'),
              ),
              const SizedBox(height: 12),

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
                                ? cs.surfaceContainerHighest.withValues(
                                    alpha: 0.45,
                                  )
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
                            DataCell(Text('${item['berat'] ?? '—'} gr')),
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
                                  DataColumn(
                                    label: dataTableColumnLabel('No. Order'),
                                  ),
                                  DataColumn(
                                    label: dataTableColumnLabel('Pelanggan'),
                                  ),
                                  DataColumn(
                                    label: dataTableColumnLabel('Item'),
                                  ),
                                  DataColumn(
                                    label: dataTableColumnLabel('Berat'),
                                  ),
                                  DataColumn(
                                    label: dataTableColumnLabel('No. HP'),
                                  ),
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

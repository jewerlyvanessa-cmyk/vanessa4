import 'package:flutter/material.dart';
import 'dart:convert';
import 'dart:math' as math;
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:io';
import 'dart:async';
import 'package:http_parser/http_parser.dart';
import '../../../utils/network_config.dart';
import '../../../utils/logger.dart';
import '../../../utils/pembulatan.dart';
import 'customers_page.dart';
import '../../../providers/order_today_provider.dart';
import 'package:vanessa3/providers/cs_daily_orders_refresh_provider.dart';
import 'faktur_page.dart';
import 'package:vanessa3/providers/user_state_provider.dart';
import 'package:vanessa3/utils/order_item_kategori_jenis.dart';

import 'package:cross_file/cross_file.dart';
import 'package:vanessa3/widgets/qr_scan_route.dart';
import 'package:vanessa3/core/theme/app_typography.dart';
import 'package:vanessa3/shared_widgets/cs_order_photo_field.dart';
import 'package:vanessa3/utils/cs_order_photo_picker.dart';
import 'package:vanessa3/utils/responsive_layout.dart';

class BuybackPage extends ConsumerStatefulWidget {
  const BuybackPage({super.key, this.client});

  final http.Client? client;

  @override
  ConsumerState<BuybackPage> createState() => _BuybackPageState();
}

class _BuybackPageState extends ConsumerState<BuybackPage> {
  final _formKey = GlobalKey<FormState>();

  // Controllers untuk form
  final TextEditingController _customerController = TextEditingController();
  final TextEditingController _customerPhoneController =
      TextEditingController();
  final TextEditingController _customerAddressController =
      TextEditingController();
  final TextEditingController _namaItemController = TextEditingController();
  final TextEditingController _beratController = TextEditingController();
  final TextEditingController _quantityController = TextEditingController(
    text: '1',
  );
  final TextEditingController _materialController = TextEditingController();
  final TextEditingController _kadarController = TextEditingController();
  final TextEditingController _hargaBeliController = TextEditingController();
  String _untungRugi = 'UNTUNG';
  final TextEditingController _kategoriController = TextEditingController();
  final TextEditingController _jenisController = TextEditingController();
  final TextEditingController _tipeController = TextEditingController();
  // Nota lama (untuk lookup order jual sebelumnya)
  final TextEditingController _notaLamaController = TextEditingController();
  // Kode produk (untuk disimpan di order_items buyback)
  final TextEditingController _kodeProdukController = TextEditingController();
  final TextEditingController _notaOrderController = TextEditingController();
  final TextEditingController _nomorNotaController = TextEditingController();
  final TextEditingController _scannedQrController = TextEditingController();

  // Controllers untuk kondisi barang
  final TextEditingController _penyesuaianBeratController =
      TextEditingController();
  final TextEditingController _hargaPerGramController = TextEditingController();
  final TextEditingController _potonganKondisiController =
      TextEditingController();
  final TextEditingController _nilaiResaleController = TextEditingController();
  final TextEditingController _catatanKondisiController =
      TextEditingController();
  final TextEditingController _nilaiUntungRugiController =
      TextEditingController();

  Map<String, dynamic>? _selectedCustomer;
  XFile? _fotoXFile;
  Uint8List? _fotoBytes;
  String? _fotoName;
  bool _isSubmitting = false;
  String _modeToko = 'TOKO';

  // State untuk item yang dipilih dari lookup
  Map<String, dynamic>? _selectedItem;
  bool _isLookingUpItem = false;

  // Flag untuk menandai apakah data material/kadar berasal dari order_items
  bool _isDataFromOrderItems = false;

  // Jika lookup nota lama tidak ditemukan, user bisa isi manual
  bool _isManualEntry = false;
  bool _isCustomerLockedFromLookup = false;

  // State untuk kondisi barang
  String _kondisiFisik = 'BAIK';
  String _notaJual = 'ADA';
  String? _selectedTipeBarang;

  final List<String> _materialSuggestions = [
    'Emas',
    'Perak',
    'Berlian',
    'Platinum',
    'Ruby',
    'Safir',
    'Zamrud',
    'Mutiara',
  ];

  final List<String> _kadarSuggestions = [
    '24K',
    '22K',
    '21K',
    '18K',
    '14K',
    '10K',
    '70%',
    '75%',
    '80%',
    '85%',
    '90%',
    '95%',
    '99%',
  ];

  @override
  void dispose() {
    _customerController.dispose();
    _customerPhoneController.dispose();
    _customerAddressController.dispose();
    _namaItemController.dispose();
    _beratController.dispose();
    _quantityController.dispose();
    _materialController.dispose();
    _kadarController.dispose();
    _hargaBeliController.dispose();
    _kategoriController.dispose();
    _jenisController.dispose();
    _tipeController.dispose();
    _notaLamaController.dispose();
    _kodeProdukController.dispose();
    _notaOrderController.dispose();
    _nomorNotaController.dispose();
    _scannedQrController.dispose();
    // Dispose kondisi barang controllers
    _penyesuaianBeratController.dispose();
    _hargaPerGramController.dispose();
    _potonganKondisiController.dispose();
    _nilaiResaleController.dispose();
    _catatanKondisiController.dispose();
    _nilaiUntungRugiController.dispose();
    super.dispose();
  }

  void _calculateNilaiUntungRugi() {
    final tipeBarang = _tipeController.text.trim().toLowerCase();
    final penyesuaianBerat =
        double.tryParse(_penyesuaianBeratController.text) ?? 0.0;
    double nilai = 0.0;

    if (tipeBarang == 'biasa') {
      if (_untungRugi == 'UNTUNG') {
        nilai = 10000 * penyesuaianBerat;
      } else if (_untungRugi == 'RUGI') {
        nilai = -10000 * penyesuaianBerat;
      }
    } else if (tipeBarang == 'gress') {
      if (_untungRugi == 'UNTUNG') {
        nilai = 12000 * penyesuaianBerat;
      } else if (_untungRugi == 'RUGI') {
        nilai = -12000 * penyesuaianBerat;
      }
    }

    _nilaiUntungRugiController.text = nilai.toStringAsFixed(0);
    _calculateNilaiResale(); // Recalculate resale when untung/rugi changes
  }

  void _calculateNilaiResale() {
    final hargaPerGram = double.tryParse(_hargaPerGramController.text) ?? 0.0;
    final penyesuaianBerat =
        double.tryParse(_penyesuaianBeratController.text) ?? 0.0;
    final nilaiUntungRugi =
        double.tryParse(_nilaiUntungRugiController.text) ?? 0.0;
    final potonganKondisi =
        double.tryParse(_potonganKondisiController.text) ?? 0.0;

    final nilaiResale =
        (hargaPerGram * penyesuaianBerat) + nilaiUntungRugi - potonganKondisi;
    // Pembulatan: round UP ke kelipatan 5.000 (konsisten dengan backend).
    final rounded = pembulatan(nilaiResale.ceil());
    _nilaiResaleController.text = rounded.toString();
  }

  @override
  void initState() {
    super.initState();
    // Fetch customers when page loads
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(customersProvider.notifier).fetchCustomers();
    });

    // Add listeners for automatic calculation
    _tipeController.addListener(_calculateNilaiUntungRugi);
    _penyesuaianBeratController.addListener(() {
      _calculateNilaiUntungRugi();
      _calculateNilaiResale();
    });
    _hargaPerGramController.addListener(_calculateNilaiResale);
    _potonganKondisiController.addListener(_calculateNilaiResale);
  }

  void _applyPhotoPick(CsOrderPhotoPickResult? result) {
    if (result == null || !result.hasPhoto) return;
    setState(() {
      if (result.bytes != null) {
        _fotoBytes = result.bytes;
        _fotoName = result.fileName;
        _fotoXFile = null;
      } else if (result.file != null) {
        _fotoXFile = XFile(result.file!.path);
        _fotoBytes = null;
        _fotoName = null;
      }
    });
  }

  void _snackPhotoPickError([String? detail]) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          detail ??
              'Tidak bisa membaca file gambar. Coba file lain (JPEG/PNG).',
        ),
      ),
    );
  }

  Future<void> _pickFoto() async {
    try {
      final result = await CsOrderPhotoPicker.pickFromCamera();
      if (!mounted) return;
      if (result == null) return;
      if (!result.hasPhoto) {
        _snackPhotoPickError();
        return;
      }
      _applyPhotoPick(result);
    } catch (e) {
      _snackPhotoPickError('Gagal ambil foto: $e');
    }
  }

  Future<void> _pickFotoFromGallery() async {
    try {
      final result = await CsOrderPhotoPicker.pickFromGallery();
      if (!mounted) return;
      if (result == null) return;
      if (!result.hasPhoto) {
        _snackPhotoPickError();
        return;
      }
      _applyPhotoPick(result);
    } catch (e) {
      _snackPhotoPickError('Gagal pilih gambar: $e');
    }
  }

  MediaType _detectImageMediaType(String filePath) {
    final lower = filePath.toLowerCase();
    if (lower.endsWith('.png')) return MediaType('image', 'png');
    if (lower.endsWith('.webp')) return MediaType('image', 'webp');
    // default to jpeg for .jpg/.jpeg or unknown (we compress to jpg)
    return MediaType('image', 'jpeg');
  }

  void _generateOrderNumber() {
    final userState = ref.read(userStateProvider);

    // Get branch initial from branch initials field
    String branchInitial = 'X'; // Default fallback
    if (userState.branch.isNotEmpty && userState.branches.isNotEmpty) {
      try {
        final found = userState.branches.firstWhere(
          (b) => b['branch_id'].toString() == userState.branch,
        );
        // Use initials field if available, otherwise fallback to first character of name
        final initials = found['initials'];
        if (initials != null && initials.toString().isNotEmpty) {
          branchInitial = initials.toString().toUpperCase();
        } else {
          final branchName = found['name'] ?? userState.branch;
          if (branchName.isNotEmpty) {
            branchInitial = branchName[0].toUpperCase();
          }
        }
      } catch (e) {
        // If branch not found, use first character of branch ID or default
        branchInitial = userState.branch.isNotEmpty
            ? userState.branch[0].toUpperCase()
            : 'X';
      }
    }

    // Generate unique 8 digit number (using timestamp for uniqueness)
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final uniqueNumber = (timestamp % 100000000).toString().padLeft(8, '0');

    // Format: BRANCH_INITIAL + "B" + 8_DIGIT_NUMBER (B for Buyback)
    final orderNumber = '$branchInitial${'B'}$uniqueNumber';

    setState(() {
      _notaOrderController.text = orderNumber;
    });
  }

  void _switchToManualEntryMode() {
    _isManualEntry = true;
    _isDataFromOrderItems = false;
    _selectedItem = null;
    _nomorNotaController.clear();
    _isCustomerLockedFromLookup = false;
    _selectedCustomer = null;
    _customerController.clear();
    _customerPhoneController.clear();
    _customerAddressController.clear();
  }

  /// Normalisasi isi field / hasil scan (QR sering menambah newline).
  String _normalizeNotaInput(String raw) {
    return raw.replaceAll(RegExp(r'[\r\n\t]+'), '').trim();
  }

  Future<void> _lookupItem() async {
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    final notaLama = _normalizeNotaInput(_notaLamaController.text);

    if (notaLama.isEmpty) {
      scaffoldMessenger.showSnackBar(
        const SnackBar(content: Text('Masukkan nota lama terlebih dahulu')),
      );
      return;
    }

    setState(() {
      _isLookingUpItem = true;
      _isManualEntry = false;
    });

    try {
      final baseUrl = NetworkConfig.baseUrl;
      final headers = NetworkConfig.defaultHeaders;

      Future<http.Response> getOrders(Map<String, String> qp) async {
        final uri = Uri.parse('$baseUrl/orders').replace(queryParameters: qp);
        final c = widget.client;
        if (c != null) return c.get(uri, headers: headers);
        return http.get(uri, headers: headers);
      }

      Map<String, dynamic>? decodeOrderMap(http.Response response) {
        if (response.statusCode != 200) return null;
        final decoded = jsonDecode(response.body);
        if (decoded == null) return null;
        if (decoded is Map<String, dynamic>) return decoded;
        if (decoded is Map) return Map<String, dynamic>.from(decoded);
        return null;
      }

      Map<String, dynamic>? orderData = decodeOrderMap(
        await getOrders({'order_number': notaLama}),
      );

      // QR faktur: jika nomor nota kosong saat cetak, QR berisi order_id (angka) — GET /orders?order_id=
      if (orderData == null && RegExp(r'^\d+$').hasMatch(notaLama)) {
        orderData = decodeOrderMap(await getOrders({'order_id': notaLama}));
      }

      Logger.logInfo('Order data received: $orderData');

      if (orderData == null || orderData.isEmpty) {
        scaffoldMessenger.showSnackBar(
          const SnackBar(
            content: Text(
              'Nota lama tidak ditemukan. Silakan isi data secara manual.',
            ),
          ),
        );
        setState(() {
          _switchToManualEntryMode();
        });
        return;
      }

      final Map<String, dynamic> resolved = orderData;

      // Check if order is eligible for buyback (must be completed sale)
      if (resolved['order_type'] != 'jual' ||
          resolved['status'] != 'completed') {
        scaffoldMessenger.showSnackBar(
          const SnackBar(
            content: Text(
              'Order tidak valid untuk buyback (harus order jual yang completed)',
            ),
          ),
        );
        setState(() {
          _switchToManualEntryMode();
        });
        return;
      }

      // Set customer data from order
      setState(() {
        _selectedCustomer = {
          'customer_id': resolved['customer_id'],
          'name': resolved['customer_name'],
          'phone': resolved['customer_phone'],
          'address': resolved['customer_address'],
        };
        _customerController.text = resolved['customer_name'] ?? '';
        _customerPhoneController.text = resolved['customer_phone'] ?? '';
        _customerAddressController.text = resolved['customer_address'] ?? '';
        _nomorNotaController.text =
            resolved['order_number'] ?? resolved['nota_order'] ?? '';
        _isCustomerLockedFromLookup = true;
      });

      // Get valid items from order
      final validItems = resolved['items'] as List<dynamic>? ?? [];

      if (validItems.isEmpty) {
        scaffoldMessenger.showSnackBar(
          const SnackBar(content: Text('Order tidak memiliki item yang valid')),
        );
        setState(() {
          _switchToManualEntryMode();
        });
        return;
      }

      // Jika hanya 1 item, langsung isi field tanpa dialog
      if (validItems.length == 1) {
        await _selectItem(validItems[0]);
      } else {
        // Jika multiple items, tampilkan dialog untuk memilih
        await _showItemSelectionDialog(validItems);
      }
    } catch (e) {
      scaffoldMessenger.showSnackBar(
        SnackBar(content: Text('Error looking up item: $e')),
      );
      setState(() {
        _switchToManualEntryMode();
      });
    } finally {
      setState(() {
        _isLookingUpItem = false;
      });
    }
  }

  Future<void> _showItemSelectionDialog(List<dynamic> items) async {
    final selectedItem = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (dialogContext) {
        final cs = Theme.of(dialogContext).colorScheme;
        final dataRows = <DataRow>[];
        for (var i = 0; i < items.length; i++) {
          final item = items[i] as Map<String, dynamic>;
          final picked = Map<String, dynamic>.from(item);
          dataRows.add(
            DataRow(
              color: WidgetStateProperty.resolveWith((s) {
                if (s.contains(WidgetState.hovered)) {
                  return cs.primary.withValues(alpha: 0.06);
                }
                return i.isOdd
                    ? cs.surfaceContainerHighest.withValues(alpha: 0.45)
                    : null;
              }),
              onSelectChanged: (_) => Navigator.of(dialogContext).pop(picked),
              cells: [
                DataCell(Text('${item['name'] ?? 'Unknown Item'}')),
                DataCell(Text('${item['kode_produk'] ?? '—'}')),
              ],
            ),
          );
        }
        return AlertDialog(
          title: const Text('Pilih Item'),
          content: SizedBox(
            width: double.maxFinite,
            height: math.min(
              360.0,
              MediaQuery.sizeOf(dialogContext).height * 0.5,
            ),
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
                  child: DataTable(
                    headingRowColor: WidgetStateProperty.all(
                      cs.surfaceContainerHigh,
                    ),
                    dataRowMinHeight: 40,
                    columnSpacing: 12,
                    horizontalMargin: 12,
                    showCheckboxColumn: false,
                    columns: [
                      DataColumn(label: dataTableColumnLabel('Item')),
                      DataColumn(label: dataTableColumnLabel('Kode')),
                    ],
                    rows: dataRows,
                  ),
                ),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Batal'),
            ),
          ],
        );
      },
    );

    if (selectedItem != null) {
      await _selectItem(selectedItem);
    }
  }

  Future<void> _selectItem(Map<String, dynamic> item) async {
    Logger.logInfo('Selecting item: $item');
    Logger.logInfo('Item material: ${item['material']}');
    Logger.logInfo('Item purity: ${item['purity']}');

    // Auto-fill form fields dari item yang dipilih
    final namaItem =
        item['nama_item'] ?? item['item_name'] ?? item['name'] ?? '';
    final berat = (item['weight'] ?? item['item_weight'] ?? 0).toString();
    // Prefer order_items snapshot; fallback to items if legacy orders didn't store it.
    final material =
        ((item['material'] ?? '').toString().trim().isNotEmpty
                ? item['material']
                : item['item_material'] ?? '')
            .toString();
    final kadar =
        ((item['purity'] ?? '').toString().trim().isNotEmpty
                ? item['purity']
                : item['item_purity'] ?? '')
            .toString();
    final kategori = item['kategori'] ?? item['item_kategori'] ?? '';
    final jenis = item['jenis'] ?? item['item_jenis'] ?? '';
    final tipe = item['tipe'] ?? item['item_tipe'] ?? '';
    final selectedTipeBarang = item['tipe'] ?? item['item_tipe'];
    final quantity = (item['qty'] ?? item['quantity'] ?? 1).toString();
    final hargaBeli =
        (item['total'] ?? item['harga_per_gram'] ?? item['harga_beli'] ?? 0)
            .toString();
    final hargaPerGram = (item['harga_per_gram'] ?? 0).toString();
    final kodeProduk = item['kode_produk'] ?? item['item_kode'] ?? '';

    setState(() {
      _selectedItem = item;
      _notaJual = _nomorNotaController.text.isNotEmpty ? 'ADA' : 'TIDAK_ADA';
      _isDataFromOrderItems = true; // material/kadar sourced from order_items
      _isManualEntry = false;

      // Fill all controllers
      _namaItemController.text = namaItem;
      _beratController.text = berat;
      _materialController.text = material;
      _kadarController.text = kadar;
      _kategoriController.text = kategori;
      _jenisController.text = jenis;
      _tipeController.text = tipe;
      _selectedTipeBarang = selectedTipeBarang;
      _quantityController.text = quantity;
      _hargaBeliController.text = hargaBeli;
      _hargaPerGramController.text = hargaPerGram;
      _kodeProdukController.text = kodeProduk.toString();
    });

    Logger.logInfo('Form fields updated:');
    Logger.logInfo('nama_item: ${_namaItemController.text}');
    Logger.logInfo('berat: ${_beratController.text}');
    Logger.logInfo('material: ${_materialController.text}');
    Logger.logInfo('kadar: ${_kadarController.text}');
    Logger.logInfo('kategori: ${_kategoriController.text}');
    Logger.logInfo('jenis: ${_jenisController.text}');
    Logger.logInfo('tipe: ${_tipeController.text}');
    Logger.logInfo('quantity: ${_quantityController.text}');
    Logger.logInfo('harga: ${_hargaBeliController.text}');

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Item "${item['nama_item'] ?? item['item_name'] ?? item['name']}" berhasil dipilih dan field terisi otomatis',
          ),
        ),
      );
    }
  }

  Future<void> _showAddCustomerDialog(
    String initialName,
    TextEditingController controller,
  ) async {
    final nameController = TextEditingController(text: initialName);
    final emailController = TextEditingController();
    final phoneController = TextEditingController();
    final addressController = TextEditingController();

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Tambah Customer Baru'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: const InputDecoration(labelText: 'Nama'),
            ),
            TextField(
              controller: emailController,
              decoration: const InputDecoration(
                labelText: 'Email (opsional)',
              ),
              keyboardType: TextInputType.emailAddress,
            ),
            TextField(
              controller: phoneController,
              decoration: const InputDecoration(
                labelText: 'No. Telepon (opsional)',
              ),
            ),
            TextField(
              controller: addressController,
              decoration: const InputDecoration(labelText: 'Alamat'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Batal'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Simpan'),
          ),
        ],
      ),
    );

    if (result == true) {
      try {
        final baseUrl = NetworkConfig.baseUrl;
        final response = await http.post(
          Uri.parse('$baseUrl/api/customers'),
          headers: NetworkConfig.defaultHeaders,
          body: jsonEncode({
            'name': nameController.text,
            'email': emailController.text.trim().isEmpty
                ? null
                : emailController.text.trim(),
            'phone': phoneController.text.trim().isEmpty
                ? null
                : phoneController.text.trim(),
            'address': addressController.text.trim().isEmpty
                ? null
                : addressController.text.trim(),
          }),
        );

        if (response.statusCode == 201) {
          final data = jsonDecode(response.body);
          setState(() {
            _selectedCustomer = data;
            controller.text = data['name'] ?? data['nama'] ?? '';
            _customerPhoneController.text =
                data['phone'] ?? data['no_hp'] ?? '';
            _customerAddressController.text =
                data['address'] ?? data['alamat'] ?? '';
          });
          ref.invalidate(customersProvider);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Customer berhasil ditambahkan')),
            );
          }
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Error: $e')));
        }
      }
    }
  }

  Future<void> _scanAndFill(
    TextEditingController controller, {
    Future<void> Function(String scanned)? onScanned,
  }) async {
    final v = await pushQrScanPage(context);
    if (!mounted || v == null) return;
    final scanned = _normalizeNotaInput(v);
    if (scanned.isEmpty) return;
    controller.text = scanned;
    if (onScanned != null) {
      await onScanned(scanned);
    }
  }

  Future<void> _submitBuyback() async {
    final scaffoldMessenger = ScaffoldMessenger.of(context);

    if (!_formKey.currentState!.validate()) return;

    if (_selectedCustomer == null) {
      scaffoldMessenger.showSnackBar(
        const SnackBar(content: Text('Pilih customer terlebih dahulu')),
      );
      return;
    }

    // Allow manual entry when nota lama not found.
    // When lookup succeeds, _selectedItem is filled and will be used for item_id (if any).

    if (_fotoXFile == null && _fotoBytes == null) {
      scaffoldMessenger.showSnackBar(
        const SnackBar(content: Text('Foto barang wajib diupload')),
      );
      return;
    }

    setState(() {
      _isSubmitting = true;
    });

    try {
      final baseUrl = NetworkConfig.baseUrl;
      final userState = ref.read(userStateProvider);

      // Prepare order data
      final orderData = {
        'order_type': 'buyback',
        'order_number': _notaOrderController.text.isNotEmpty
            ? _notaOrderController.text
            : null,
        'nota_lama': _notaLamaController.text.trim().isEmpty
            ? null
            : _notaLamaController.text.trim(),
        'reference_order_number': _nomorNotaController.text.trim().isEmpty
            ? (_notaLamaController.text.trim().isEmpty
                  ? null
                  : _notaLamaController.text.trim())
            : _nomorNotaController.text.trim(),
        'customer_id': _selectedCustomer!['customer_id'],
        'branch_id': int.parse(
          userState.branch.isNotEmpty ? userState.branch : '1',
        ),
        'user_id': userState.userId ?? 1,
        'mode': 'TOKO',
        'diskon': 0,
        'order_items': [
          {
            'item_id':
                _selectedItem?['item_id'], // Include item_id if selected from lookup
            'nama_item': _namaItemController.text.trim(),
            'weight': double.tryParse(_beratController.text.trim()) ?? 0,
            'material': _materialController.text.trim(),
            'purity': _kadarController.text.trim(),
            'harga_per_gram':
                double.tryParse(_hargaPerGramController.text.trim()) ?? 0,
            'kategori': _kategoriController.text.trim(),
            'jenis': _jenisController.text.trim(),
            'tipe': _notaJual == 'TIDAK_ADA'
                ? (_selectedTipeBarang ?? '')
                : _tipeController.text.trim(),
            'kode_produk': _kodeProdukController.text.trim(),
            'qty': int.tryParse(_quantityController.text.trim()) ?? 1,
            'subtotal':
                (double.tryParse(_hargaBeliController.text.trim()) ?? 0) *
                (int.tryParse(_quantityController.text.trim()) ?? 1),
            'total':
                (double.tryParse(_hargaBeliController.text.trim()) ?? 0) *
                (int.tryParse(_quantityController.text.trim()) ?? 1),
            'diskon': 0,
            'kondisi_barang': {
              'kondisi_fisik': _kondisiFisik,
              'berat_akhir': double.tryParse(_beratController.text.trim()),
              'penyesuaian_berat':
                  double.tryParse(_penyesuaianBeratController.text.trim()) ?? 0,
              'harga_per_gram':
                  double.tryParse(_hargaPerGramController.text.trim()) ?? 0,
              'nilai_untung_rugi': _nilaiUntungRugiController.text.trim(),
              'nota_jual': _nomorNotaController.text.trim().isEmpty
                  ? _notaLamaController.text.trim()
                  : _nomorNotaController.text.trim(),
              'nota_jual_status': _notaJual,
              'potongan_kondisi':
                  double.tryParse(_potonganKondisiController.text.trim()) ?? 0,
              'nilai_resale':
                  double.tryParse(_nilaiResaleController.text.trim()) ?? 0,
              'harga_beli':
                  double.tryParse(_hargaBeliController.text.trim()) ?? 0,
              'untung_rugi': _untungRugi,
              'catatan_kondisi': _catatanKondisiController.text.trim(),
            },
          },
        ],
      };

      final uri = Uri.parse('$baseUrl/orders');

      final request = http.MultipartRequest('POST', uri);
      // IMPORTANT: MultipartRequest tidak otomatis membawa header Authorization
      // dari NetworkConfig.defaultHeaders (yang biasa dipakai untuk JSON request).
      // Untuk multipart, biarkan Content-Type di-handle oleh MultipartRequest,
      // tapi tetap kirim token auth.
      final token = NetworkConfig.authToken;
      if (token != null && token.isNotEmpty) {
        request.headers['Authorization'] = 'Bearer $token';
      }
      request.headers['Accept'] = 'application/json';

      // Add JSON data
      request.fields['order_data'] = jsonEncode(orderData);

      // Add image file (required)
      if (kIsWeb) {
        final bytes = _fotoBytes ?? await _fotoXFile!.readAsBytes();
        final name = _fotoName ?? _fotoXFile!.name;
        request.files.add(
          http.MultipartFile.fromBytes(
            'photo',
            bytes,
            filename: name,
            contentType: _detectImageMediaType(name),
          ),
        );
      } else {
        request.files.add(
          await http.MultipartFile.fromPath(
            'photo',
            _fotoXFile!.path,
            contentType: _detectImageMediaType(_fotoXFile!.path),
          ),
        );
      }

      final response = await request.send();
      final responseData = await response.stream.bytesToString();

      if (response.statusCode == 401) {
        NetworkConfig.notifyUnauthorized();
      }
      if (response.statusCode == 201) {
        final jsonResponse = jsonDecode(responseData);

        // Refresh "order hari ini" list + stats
        ref.invalidate(todayOrdersProvider);
        ref.invalidate(orderTodayStatsProvider);
        bumpCsDailyOrdersListRevision(ref);

        // Navigate to faktur page
        if (mounted) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (context) => FakturPage(orderData: jsonResponse),
            ),
          );
        }
      } else {
        final errorResponse = jsonDecode(responseData);
        throw Exception(
          errorResponse['error'] ?? 'Failed to create buyback order',
        );
      }
    } catch (e) {
      scaffoldMessenger.showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      setState(() {
        _isSubmitting = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final customerList = ref.watch(customersProvider);
    final userState = ref.watch(userStateProvider);

    // Listen to user state changes to regenerate order number when branch changes
    ref.listen(userStateProvider, (previous, next) {
      if (next.branch.isNotEmpty && next.branches.isNotEmpty) {
        _generateOrderNumber();
      }
    });

    // Generate order number on first build if user state is ready
    if (userState.branch.isNotEmpty &&
        userState.branches.isNotEmpty &&
        _notaOrderController.text.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _generateOrderNumber();
      });
    }

    return Scaffold(
      resizeToAvoidBottomInset: true,
      appBar: AppBar(title: const Text('Form Order Buyback')),
      body: ResponsiveLayout.scrollableForm(
        context: context,
        formKey: _formKey,
        children: [
              // ==================== HEADER SECTION ====================
              // 1. Mode (TOKO/ONLINE)
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Container(
                    width: 100,
                    alignment: Alignment.centerLeft,
                    child: const Text('Mode'),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Wrap(
                      spacing: 8.0,
                      children: [
                        ChoiceChip(
                          label: const Text('TOKO'),
                          selected: _modeToko == 'TOKO',
                          onSelected: (selected) {
                            setState(() {
                              _modeToko = 'TOKO';
                            });
                          },
                        ),
                        ChoiceChip(
                          label: const Text('ONLINE'),
                          selected: _modeToko == 'ONLINE',
                          onSelected: (selected) {
                            setState(() {
                              _modeToko = 'ONLINE';
                            });
                          },
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Order Number
              Row(
                children: [
                  const SizedBox(
                    width: 100,
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text('Order Number'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextFormField(
                      controller: _notaOrderController,
                      readOnly: true,
                      decoration: InputDecoration(
                        border: const OutlineInputBorder(),
                        hintText: 'Nomor nota otomatis',
                        filled: true,
                        fillColor: Colors.grey[100],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12.0),

              // ==================== ITEM LOOKUP SECTION ====================
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 16),
                  // Nota Lama Lookup
                  Row(
                    children: [
                      const SizedBox(
                        width: 100,
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Row(
                            children: [
                              Text('Nota Lama'),
                              Tooltip(
                                message:
                                    'Masukkan nomor nota lama untuk mencari item dari penjualan sebelumnya',
                                child: Icon(
                                  Icons.info_outline,
                                  size: 16,
                                  color: Colors.grey,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Autocomplete<String>(
                          optionsBuilder: (textEditingValue) {
                            // Untuk sementara, return empty list
                            // Nanti bisa diisi dengan order numbers dari API
                            return const Iterable<String>.empty();
                          },
                          fieldViewBuilder:
                              (
                                context,
                                controller,
                                focusNode,
                                onFieldSubmitted,
                              ) {
                                return TextFormField(
                                  controller: _notaLamaController,
                                  focusNode: focusNode,
                                  decoration: InputDecoration(
                                    hintText: 'Masukkan nomor nota lama...',
                                    suffixIcon: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        IconButton(
                                          icon: const Icon(Icons.search),
                                          onPressed: _isLookingUpItem
                                              ? null
                                              : _lookupItem,
                                          tooltip: 'Cari berdasarkan nota lama',
                                        ),
                                        IconButton(
                                          icon: const Icon(
                                            Icons.qr_code_scanner,
                                          ),
                                          onPressed: _isLookingUpItem
                                              ? null
                                              : () => _scanAndFill(
                                                  _notaLamaController,
                                                  onScanned: (_) =>
                                                      _lookupItem(),
                                                ),
                                          tooltip: 'Scan QR nota lama',
                                        ),
                                      ],
                                    ),
                                  ),
                                  onChanged: (_) => setState(() {}),
                                  onFieldSubmitted: (value) =>
                                      onFieldSubmitted(),
                                );
                              },
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Nota Jual
              Row(
                children: [
                  const SizedBox(width: 100, child: Text('Nota Jual')),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextFormField(
                      controller: _nomorNotaController,
                      readOnly: !_isManualEntry,
                      decoration: InputDecoration(
                        border: const OutlineInputBorder(),
                        hintText: 'Nomor nota jual akan muncul setelah lookup',
                        filled: !_isManualEntry,
                        fillColor: !_isManualEntry ? Colors.grey[100] : null,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // ==================== CUSTOMER SECTION ====================
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 16),
                  // Customer Search
                  Row(
                    children: [
                      const SizedBox(
                        width: 100,
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Row(
                            children: [
                              Text('Customer'),
                              Tooltip(
                                message:
                                    'Cari berdasarkan nama atau nomor telepon (minimal 2 karakter)',
                                child: Icon(
                                  Icons.info_outline,
                                  size: 16,
                                  color: Colors.grey,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child:
                            _isCustomerLockedFromLookup &&
                                _selectedCustomer != null
                            ? Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  TextFormField(
                                    controller: _customerController,
                                    readOnly: true,
                                    decoration: InputDecoration(
                                      hintText: 'Customer dari order jual',
                                      border: const OutlineInputBorder(),
                                      filled: true,
                                      fillColor: Colors.grey[100],
                                      suffixIcon: const Tooltip(
                                        message:
                                            'Customer otomatis dari nota lama',
                                        child: Icon(Icons.lock_outline),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Phone: ${_selectedCustomer!['phone'] ?? _selectedCustomer!['no_hp'] ?? 'N/A'} | Address: ${_selectedCustomer!['address'] ?? _selectedCustomer!['alamat'] ?? 'N/A'}',
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey,
                                    ),
                                  ),
                                ],
                              )
                            : StatefulBuilder(
                                builder: (context, setFieldState) {
                                  return Row(
                                    children: [
                                      Expanded(
                                        child: customerList.isLoading
                                            ? const TextField(
                                                decoration: InputDecoration(
                                                  labelText:
                                                      'Loading customers...',
                                                ),
                                                enabled: false,
                                              )
                                            : Autocomplete<
                                                Map<String, dynamic>
                                              >(
                                                initialValue:
                                                    _selectedCustomer != null
                                                    ? TextEditingValue(
                                                        text:
                                                            _selectedCustomer!['name'] ??
                                                            _selectedCustomer!['nama'] ??
                                                            '',
                                                      )
                                                    : null,
                                                optionsBuilder:
                                                    (
                                                      TextEditingValue
                                                      textEditingValue,
                                                    ) {
                                                      if (textEditingValue
                                                              .text ==
                                                          '') {
                                                        return const Iterable<
                                                          Map<String, dynamic>
                                                        >.empty();
                                                      }
                                                      final input =
                                                          textEditingValue.text
                                                              .toLowerCase();
                                                      final suggestions = customerList
                                                          .customers
                                                          .where((c) {
                                                            final name =
                                                                (c['name'] ??
                                                                        c['nama'] ??
                                                                        '')
                                                                    .toString()
                                                                    .toLowerCase();
                                                            return name
                                                                .contains(
                                                                  input,
                                                                );
                                                          })
                                                          .toList();
                                                      return suggestions;
                                                    },
                                                displayStringForOption:
                                                    (option) =>
                                                        option['name'] ??
                                                        option['nama'] ??
                                                        '',
                                                onSelected: (customer) {
                                                  setState(() {
                                                    _customerPhoneController
                                                            .text =
                                                        customer['phone'] ??
                                                        customer['no_hp'] ??
                                                        '';
                                                    _customerAddressController
                                                            .text =
                                                        customer['address'] ??
                                                        customer['alamat'] ??
                                                        '';
                                                    _selectedCustomer =
                                                        customer;
                                                    _isCustomerLockedFromLookup =
                                                        false;
                                                  });
                                                },
                                                fieldViewBuilder:
                                                    (
                                                      context,
                                                      controller,
                                                      focusNode,
                                                      onFieldSubmitted,
                                                    ) {
                                                      return Column(
                                                        crossAxisAlignment:
                                                            CrossAxisAlignment
                                                                .start,
                                                        children: [
                                                          Row(
                                                            children: [
                                                              Expanded(
                                                                child: TextFormField(
                                                                  controller:
                                                                      controller,
                                                                  focusNode:
                                                                      focusNode,
                                                                  decoration: const InputDecoration(
                                                                    hintText:
                                                                        'Cari customer...',
                                                                    border:
                                                                        OutlineInputBorder(),
                                                                    contentPadding: EdgeInsets.symmetric(
                                                                      vertical:
                                                                          12,
                                                                      horizontal:
                                                                          12,
                                                                    ),
                                                                  ),
                                                                  onChanged: (_) =>
                                                                      setState(
                                                                        () {},
                                                                      ),
                                                                  onFieldSubmitted:
                                                                      (value) =>
                                                                          onFieldSubmitted(),
                                                                  validator: (value) {
                                                                    if (value ==
                                                                            null ||
                                                                        value
                                                                            .isEmpty) {
                                                                      return 'Customer wajib dipilih';
                                                                    }
                                                                    return null;
                                                                  },
                                                                ),
                                                              ),
                                                              Builder(
                                                                builder: (context) {
                                                                  final input =
                                                                      controller
                                                                          .text
                                                                          .trim()
                                                                          .toLowerCase();
                                                                  final exists = ref
                                                                      .read(
                                                                        customersProvider,
                                                                      )
                                                                      .customers
                                                                      .any((c) {
                                                                        final name =
                                                                            (c['name'] ??
                                                                                    c['nama'] ??
                                                                                    '')
                                                                                .toString()
                                                                                .toLowerCase();
                                                                        return name ==
                                                                                input &&
                                                                            input.isNotEmpty;
                                                                      });
                                                                  if (!exists &&
                                                                      input
                                                                          .isNotEmpty) {
                                                                    return Row(
                                                                      mainAxisSize:
                                                                          MainAxisSize
                                                                              .min,
                                                                      children: [
                                                                        IconButton(
                                                                          icon: const Icon(
                                                                            Icons.person_add,
                                                                            size:
                                                                                20,
                                                                          ),
                                                                          tooltip:
                                                                              'Tambah Customer',
                                                                          onPressed: () => _showAddCustomerDialog(
                                                                            controller.text,
                                                                            controller,
                                                                          ),
                                                                          padding:
                                                                              EdgeInsets.zero,
                                                                          constraints:
                                                                              const BoxConstraints(),
                                                                        ),
                                                                        IconButton(
                                                                          icon: const Icon(
                                                                            Icons.qr_code_scanner,
                                                                            size:
                                                                                20,
                                                                          ),
                                                                          tooltip:
                                                                              'Scan QR Customer',
                                                                          onPressed: () => _scanAndFill(
                                                                            controller,
                                                                          ),
                                                                          padding:
                                                                              EdgeInsets.zero,
                                                                          constraints:
                                                                              const BoxConstraints(),
                                                                        ),
                                                                      ],
                                                                    );
                                                                  } else {
                                                                    return Row(
                                                                      mainAxisSize:
                                                                          MainAxisSize
                                                                              .min,
                                                                      children: [
                                                                        IconButton(
                                                                          icon: const Icon(
                                                                            Icons.person_add,
                                                                            size:
                                                                                20,
                                                                          ),
                                                                          tooltip:
                                                                              'Tambah Customer',
                                                                          onPressed: () => _showAddCustomerDialog(
                                                                            controller.text,
                                                                            controller,
                                                                          ),
                                                                          padding:
                                                                              EdgeInsets.zero,
                                                                          constraints:
                                                                              const BoxConstraints(),
                                                                        ),
                                                                        IconButton(
                                                                          icon: const Icon(
                                                                            Icons.qr_code_scanner,
                                                                            size:
                                                                                20,
                                                                          ),
                                                                          tooltip:
                                                                              'Scan QR Customer',
                                                                          onPressed: () => _scanAndFill(
                                                                            controller,
                                                                          ),
                                                                          padding:
                                                                              EdgeInsets.zero,
                                                                          constraints:
                                                                              const BoxConstraints(),
                                                                        ),
                                                                      ],
                                                                    );
                                                                  }
                                                                },
                                                              ),
                                                            ],
                                                          ),
                                                          if (_selectedCustomer !=
                                                              null) ...[
                                                            const SizedBox(
                                                              height: 4,
                                                            ),
                                                            Text(
                                                              'Phone: ${_selectedCustomer!['phone'] ?? _selectedCustomer!['no_hp'] ?? 'N/A'} | Address: ${_selectedCustomer!['address'] ?? _selectedCustomer!['alamat'] ?? 'N/A'}',
                                                              style:
                                                                  const TextStyle(
                                                                    fontSize:
                                                                        12,
                                                                    color: Colors
                                                                        .grey,
                                                                  ),
                                                            ),
                                                          ],
                                                        ],
                                                      );
                                                    },
                                              ),
                                      ),
                                    ],
                                  );
                                },
                              ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                ],
              ),
              const SizedBox(height: 16),

              // ==================== ITEM DETAILS SECTION ====================
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 16),
                  // Kode Produk (boleh manual / terisi dari lookup)
                  Row(
                    children: [
                      const SizedBox(width: 100, child: Text('Kode Produk')),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextFormField(
                          controller: _kodeProdukController,
                          decoration: const InputDecoration(
                            hintText: 'Kode produk (opsional)',
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  // Kategori
                  Row(
                    children: [
                      const SizedBox(width: 100, child: Text('Kategori')),
                      const SizedBox(width: 8),
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          initialValue: _kategoriController.text.isNotEmpty
                              ? _kategoriController.text
                              : null,
                          decoration: const InputDecoration(
                            hintText: 'Kategori',
                          ),
                          items: const [
                            DropdownMenuItem(
                              value: 'PERHIASAN',
                              child: Text('PERHIASAN'),
                            ),
                            DropdownMenuItem(
                              value: 'AKSESORIES',
                              child: Text('AKSESORIES'),
                            ),
                            DropdownMenuItem(
                              value: 'LOGAM MULIA',
                              child: Text('LOGAM MULIA'),
                            ),
                          ],
                          onChanged: (value) {
                            setState(() {
                              _kategoriController.text = value ?? '';
                              _jenisController.clear();
                            });
                          },
                          validator: (value) {
                            if (value == null || value.isEmpty) {
                              return 'Kategori wajib dipilih';
                            }
                            return null;
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  // Jenis
                  Row(
                    children: [
                      const SizedBox(width: 100, child: Text('Jenis')),
                      const SizedBox(width: 8),
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          initialValue: _jenisController.text.isNotEmpty
                              ? _jenisController.text
                              : null,
                          decoration: const InputDecoration(hintText: 'Jenis'),
                          items:
                              orderItemJenisOptionsForKategori(
                                    _kategoriController.text,
                                  )
                                  .map(
                                    (jenis) => DropdownMenuItem(
                                      value: jenis,
                                      child: Text(jenis),
                                    ),
                                  )
                                  .toList(),
                          onChanged: (value) {
                            _jenisController.text = value ?? '';
                          },
                          validator: (value) {
                            if (value == null || value.isEmpty) {
                              return 'Jenis wajib dipilih';
                            }
                            return null;
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  // Tipe Barang
                  Row(
                    children: [
                      const SizedBox(width: 100, child: Text('Tipe Barang')),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _notaJual == 'TIDAK_ADA'
                            ? DropdownButtonFormField<String>(
                                initialValue: _selectedTipeBarang,
                                decoration: const InputDecoration(
                                  hintText: 'Pilih Tipe Barang',
                                ),
                                items: const [
                                  DropdownMenuItem(
                                    value: 'BIASA',
                                    child: Text('BIASA'),
                                  ),
                                  DropdownMenuItem(
                                    value: 'GRESS',
                                    child: Text('GRESS'),
                                  ),
                                ],
                                onChanged: (value) {
                                  setState(() {
                                    _selectedTipeBarang = value;
                                  });
                                },
                              )
                            : TextFormField(
                                controller: _tipeController,
                                decoration: const InputDecoration(
                                  hintText: 'Tipe Barang',
                                ),
                              ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  // Nama Item
                  Row(
                    children: [
                      const SizedBox(width: 100, child: Text('Nama Item')),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextFormField(
                          controller: _namaItemController,
                          decoration: const InputDecoration(
                            hintText: 'Nama item',
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
                  const SizedBox(height: 16),
                  // Material
                  Row(
                    children: [
                      const SizedBox(width: 100, child: Text('Material')),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Autocomplete<String>(
                          optionsBuilder: (textEditingValue) {
                            return _materialSuggestions.where(
                              (material) => material.toLowerCase().contains(
                                textEditingValue.text.toLowerCase(),
                              ),
                            );
                          },
                          onSelected: (String selection) {
                            _materialController.text = selection;
                          },
                          fieldViewBuilder:
                              (
                                context,
                                controller,
                                focusNode,
                                onFieldSubmitted,
                              ) {
                                return TextFormField(
                                  controller: _materialController,
                                  focusNode: focusNode,
                                  readOnly: _isDataFromOrderItems,
                                  decoration: InputDecoration(
                                    hintText: 'Material',
                                    filled: _isDataFromOrderItems,
                                    fillColor: _isDataFromOrderItems
                                        ? const Color(0xFFF5F5F5)
                                        : null,
                                  ),
                                  validator: (value) {
                                    if (value == null || value.isEmpty) {
                                      return 'Material wajib diisi';
                                    }
                                    return null;
                                  },
                                );
                              },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  // Kadar
                  Row(
                    children: [
                      const SizedBox(width: 100, child: Text('Kadar')),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Autocomplete<String>(
                          optionsBuilder: (textEditingValue) {
                            return _kadarSuggestions.where(
                              (kadar) => kadar.toLowerCase().contains(
                                textEditingValue.text.toLowerCase(),
                              ),
                            );
                          },
                          onSelected: (String selection) {
                            _kadarController.text = selection;
                          },
                          fieldViewBuilder:
                              (
                                context,
                                controller,
                                focusNode,
                                onFieldSubmitted,
                              ) {
                                return TextFormField(
                                  controller: _kadarController,
                                  focusNode: focusNode,
                                  readOnly: _isDataFromOrderItems,
                                  decoration: InputDecoration(
                                    hintText: 'Kadar',
                                    filled: _isDataFromOrderItems,
                                    fillColor: _isDataFromOrderItems
                                        ? const Color(0xFFF5F5F5)
                                        : null,
                                  ),
                                  validator: (value) {
                                    if (value == null || value.isEmpty) {
                                      return 'Kadar wajib diisi';
                                    }
                                    return null;
                                  },
                                );
                              },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  // Berat
                  Row(
                    children: [
                      const SizedBox(width: 100, child: Text('Berat')),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextFormField(
                          controller: _beratController,
                          decoration: const InputDecoration(
                            hintText: 'Berat (gram)',
                          ),
                          keyboardType: TextInputType.number,
                          validator: (value) {
                            if (value == null || value.isEmpty) {
                              return 'Berat wajib diisi';
                            }
                            if (double.tryParse(value) == null) {
                              return 'Berat harus berupa angka';
                            }
                            return null;
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  // Quantity
                  Row(
                    children: [
                      const SizedBox(width: 100, child: Text('Quantity')),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextFormField(
                          controller: _quantityController,
                          decoration: const InputDecoration(
                            hintText: 'Quantity',
                          ),
                          keyboardType: TextInputType.number,
                          validator: (value) {
                            if (value == null || value.isEmpty) {
                              return 'Quantity wajib diisi';
                            }
                            if (int.tryParse(value) == null) {
                              return 'Quantity harus berupa angka';
                            }
                            return null;
                          },
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // ==================== PRICE ASSESSMENT SECTION ====================
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 16),
                  // Harga Awal
                  Row(
                    children: [
                      const SizedBox(width: 100, child: Text('Harga Awal')),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextFormField(
                          controller: _hargaBeliController,
                          decoration: const InputDecoration(
                            hintText: 'Harga Awal (Rp)',
                          ),
                          keyboardType: TextInputType.number,
                          validator: (value) {
                            if (value == null || value.isEmpty) {
                              return 'Harga awal wajib diisi';
                            }
                            if (double.tryParse(value) == null) {
                              return 'Harga awal harus berupa angka';
                            }
                            return null;
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  // Untung/Rugi
                  Row(
                    children: [
                      const SizedBox(width: 100, child: Text('Untung/Rugi')),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Wrap(
                          spacing: 8.0,
                          children: [
                            ChoiceChip(
                              label: const Text('UNTUNG'),
                              selected: _untungRugi == 'UNTUNG',
                              onSelected: (selected) {
                                setState(() {
                                  _untungRugi = 'UNTUNG';
                                  _calculateNilaiUntungRugi();
                                });
                              },
                            ),
                            ChoiceChip(
                              label: const Text('RUGI'),
                              selected: _untungRugi == 'RUGI',
                              onSelected: (selected) {
                                setState(() {
                                  _untungRugi = 'RUGI';
                                  _calculateNilaiUntungRugi();
                                });
                              },
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // ==================== CONDITION ASSESSMENT SECTION ====================
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 16),
                  // Kondisi Fisik
                  Row(
                    children: [
                      const SizedBox(width: 100, child: Text('Kondisi Fisik')),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Wrap(
                          spacing: 8.0,
                          children: [
                            ChoiceChip(
                              label: const Text('BAIK'),
                              selected: _kondisiFisik == 'BAIK',
                              onSelected: (selected) {
                                if (selected) {
                                  setState(() {
                                    _kondisiFisik = 'BAIK';
                                  });
                                }
                              },
                            ),
                            ChoiceChip(
                              label: const Text('RUSAK'),
                              selected: _kondisiFisik == 'RUSAK',
                              onSelected: (selected) {
                                if (selected) {
                                  setState(() {
                                    _kondisiFisik = 'RUSAK';
                                  });
                                }
                              },
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  // Catatan Kondisi
                  Row(
                    children: [
                      const SizedBox(
                        width: 100,
                        child: Text('Catatan Kondisi'),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextFormField(
                          controller: _catatanKondisiController,
                          decoration: const InputDecoration(
                            hintText: 'Catatan Kondisi',
                          ),
                          maxLines: 1,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  // Penyesuaian Berat
                  Row(
                    children: [
                      const SizedBox(
                        width: 100,
                        child: Text('Penyesuaian Berat'),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextFormField(
                          controller: _penyesuaianBeratController,
                          decoration: const InputDecoration(
                            hintText: 'Penyesuaian Berat',
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  // Harga Per Gram
                  Row(
                    children: [
                      const SizedBox(width: 100, child: Text('Harga Per Gram')),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextFormField(
                          controller: _hargaPerGramController,
                          decoration: const InputDecoration(
                            hintText: 'Harga Per Gram (Rp)',
                          ),
                          keyboardType: TextInputType.number,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  // Potongan Kondisi
                  Row(
                    children: [
                      const SizedBox(
                        width: 100,
                        child: Text('Potongan Kondisi'),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextFormField(
                          controller: _potonganKondisiController,
                          decoration: const InputDecoration(
                            hintText: 'Potongan Kondisi (Rp)',
                          ),
                          keyboardType: TextInputType.number,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  // Nilai Untung/Rugi
                  Row(
                    children: [
                      const SizedBox(
                        width: 100,
                        child: Text('Nilai Untung/Rugi'),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextFormField(
                          controller: _nilaiUntungRugiController,
                          readOnly: true,
                          decoration: const InputDecoration(
                            hintText: 'Nilai untung/rugi (otomatis)',
                            filled: true,
                            fillColor: Color(0xFFF5F5F5),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  // Nilai Resale
                  Row(
                    children: [
                      const SizedBox(width: 100, child: Text('Nilai Resale')),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextFormField(
                          controller: _nilaiResaleController,
                          readOnly: true,
                          decoration: const InputDecoration(
                            hintText: 'Nilai Resale (otomatis)',
                            filled: true,
                            fillColor: Color(0xFFF5F5F5),
                          ),
                          keyboardType: TextInputType.number,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  CsOrderPhotoField(
                    label: 'Foto Kondisi',
                    hasPhoto: _fotoXFile != null || _fotoBytes != null,
                    imageBytes: _fotoBytes,
                    imageFile:
                        _fotoXFile != null ? File(_fotoXFile!.path) : null,
                    onCamera: _pickFoto,
                    onGallery: _pickFotoFromGallery,
                    requiredMessage:
                        (_fotoXFile == null && _fotoBytes == null)
                            ? 'Foto barang wajib diupload'
                            : null,
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // Submit Button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isSubmitting ? null : _submitBuyback,
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    backgroundColor: Colors.purple,
                    foregroundColor: Colors.white,
                  ),
                  child: _isSubmitting
                      ? const CircularProgressIndicator(color: Colors.white)
                      : const Text('BUAT ORDER BUYBACK'),
                ),
              ),
        ],
      ),
    );
  }
}

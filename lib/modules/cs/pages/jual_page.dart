import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:io';
import 'dart:async';
import 'package:intl/intl.dart';
import '../../../utils/network_config.dart';
import '../../../utils/logger.dart';
import 'customers_page.dart';
import '../../../providers/order_today_provider.dart'; // Import todayOrdersProvider
import 'package:vanessa3/providers/cs_daily_orders_refresh_provider.dart';

import 'package:vanessa3/widgets/qr_scan_route.dart';
import 'faktur_page.dart';
import 'package:vanessa3/providers/user_state_provider.dart';
import 'package:vanessa3/utils/order_item_kategori_jenis.dart';
import 'package:vanessa3/shared_widgets/cs_order_photo_field.dart';
import 'package:vanessa3/utils/cs_order_photo_picker.dart';
import 'package:vanessa3/utils/responsive_layout.dart';

class JualPage extends ConsumerStatefulWidget {
  const JualPage({super.key, this.client});

  final http.Client? client;

  @override
  ConsumerState<JualPage> createState() => _JualPageState();
}

class _JualPageState extends ConsumerState<JualPage> {
  final _formKey = GlobalKey<FormState>();

  // Controllers untuk form
  final TextEditingController _customerController = TextEditingController();
  final TextEditingController _customerPhoneController =
      TextEditingController();
  final TextEditingController _customerAddressController =
      TextEditingController();
  final TextEditingController _namaItemController = TextEditingController();
  final TextEditingController _beratController = TextEditingController();
  final TextEditingController _materialController = TextEditingController();
  final TextEditingController _kadarController = TextEditingController();
  final TextEditingController _itemCodeController = TextEditingController();
  final TextEditingController _notaOrderController = TextEditingController();
  final TextEditingController _hargaPerGramController = TextEditingController();
  final TextEditingController _diskonController = TextEditingController();
  final TextEditingController _kategoriController = TextEditingController();
  final TextEditingController _jenisController = TextEditingController();
  final TextEditingController _tipeController = TextEditingController();
  final TextEditingController _qtyController = TextEditingController(
    text: '1',
  ); // New field for quantity
  final TextEditingController _jumlahController =
      TextEditingController(); // Calculated total amount

  Map<String, dynamic>? _selectedCustomer;
  int _autocompleteKey = 0; // Key to force rebuild Autocomplete
  File? _fotoFile;
  String _modeToko = 'TOKO'; // Mode selection: TOKO or ONLINE
  String _saleType = 'from_stock'; // from_stock, unregistered, qsr
  List<Map<String, dynamic>> _itemSuggestions = [];
  bool _isLoadingSuggestions = false;
  Map<String, dynamic>? _selectedItem;
  bool _isSubmitting = false; // Loading state for submit
  Timer? _itemSearchTimer; // Timer for debouncing item search

  /// Web: isi dari [FilePicker] (stub [ImagePicker] di web selalu null).
  Uint8List? _fotoBytes;
  String? _fotoName;

  bool get _hasFoto =>
      (_fotoBytes != null && _fotoBytes!.isNotEmpty) || _fotoFile != null;

  // Material choice UI for UNREGISTERED/QSR mode.
  // Value will be mirrored into _materialController for payload consistency.
  String _materialChoice = 'EMAS'; // EMAS, PERAK, LAINNYA

  // Controller yang dipakai field Autocomplete "Kode Produk"
  // (berbeda dengan _itemCodeController yang menyimpan nilai untuk payload).
  TextEditingController? _itemAutocompleteFieldController;

  double _roundToNearest5000(double amount) {
    final modulo10000 = amount % 10000;

    if (modulo10000 == 5000) {
      // Exactly 5000, keep as is
      return amount;
    } else if (modulo10000 < 5000) {
      // Below 5000, round up to 5000
      return amount - modulo10000 + 5000;
    } else {
      // Above 5000, round up to next 10000
      return amount - modulo10000 + 10000;
    }
  }

  String _formatNumberWithSeparators(String value) {
    if (value.isEmpty) return value;

    // Remove existing separators and Rp prefix
    final cleanValue = value
        .replaceAll(',', '')
        .replaceAll('Rp ', '')
        .replaceAll('Rp', '');
    final number = int.tryParse(cleanValue) ?? double.tryParse(cleanValue);
    if (number == null) return value;

    // Format with thousand separators and Rp prefix, no decimals
    final formatter = NumberFormat.currency(
      locale: 'id_ID',
      symbol: 'Rp ',
      decimalDigits: 0,
    );
    return formatter.format(number);
  }

  double _parseNumberWithSeparators(String value) {
    if (value.isEmpty) return 0.0;

    // Remove separators and Rp prefix
    final cleanValue = value
        .replaceAll(',', '')
        .replaceAll('Rp ', '')
        .replaceAll('Rp', '');
    return int.tryParse(cleanValue)?.toDouble() ??
        double.tryParse(cleanValue) ??
        0.0;
  }

  void _calculateJumlah() {
    final qty = int.tryParse(_qtyController.text) ?? 0;
    final weight = double.tryParse(_beratController.text) ?? 0.0;
    final hargaPerGram = _parseNumberWithSeparators(
      _hargaPerGramController.text,
    );
    final diskonPersen = double.tryParse(_diskonController.text) ?? 0.0;

    final subtotal = qty * weight * hargaPerGram;
    final diskonAmount = subtotal * diskonPersen / 100;
    final jumlah = subtotal - diskonAmount;
    final roundedJumlah = _roundToNearest5000(jumlah);

    // Format with thousand separators and Rp prefix, no decimals
    final formatter = NumberFormat.currency(
      locale: 'id_ID',
      symbol: 'Rp ',
      decimalDigits: 0,
    );
    _jumlahController.text = formatter.format(roundedJumlah);
  }

  @override
  void initState() {
    super.initState();
    // Fetch customers when page loads
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(customersProvider.notifier).fetchCustomers();
    });

    // Default material for new/unregistered sales
    _materialController.text = _materialChoice;
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

    // Format: BRANCH_INITIAL + "J" + 8_DIGIT_NUMBER
    final orderNumber = '$branchInitial${'J'}$uniqueNumber';

    setState(() {
      _notaOrderController.text = orderNumber;
    });
  }

  MediaType _detectImageMediaType(String filePath) {
    final lower = filePath.toLowerCase();
    if (lower.endsWith('.png')) return MediaType('image', 'png');
    if (lower.endsWith('.webp')) return MediaType('image', 'webp');
    // default to jpeg for .jpg/.jpeg or unknown (we compress to jpg)
    return MediaType('image', 'jpeg');
  }

  Future<String?> _uploadProductPhoto() async {
    if (!_hasFoto) return null;

    try {
      final baseUrl = NetworkConfig.storageUrl;
      debugPrint('Uploading foto to: $baseUrl/upload');

      final uri = Uri.parse('$baseUrl/upload');
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
        request.files.add(
          await http.MultipartFile.fromPath(
            'file',
            foto.path,
            contentType: _detectImageMediaType(foto.path),
          ),
        );
      }

      final response = await request.send();
      debugPrint('Upload response status: ${response.statusCode}');

      if (response.statusCode == 200) {
        final respStr = await response.stream.bytesToString();
        debugPrint('Upload response: $respStr');

        final data = jsonDecode(respStr);
        // Handle both full URL and relative path responses
        final url = data['url'] ?? data['fileUrl'] ?? data['path'];
        if (url != null) {
          // If URL is relative path, prepend with storage base URL
          if (url.startsWith('/')) {
            final fullUrl = '$baseUrl$url';
            debugPrint('Final photo URL: $fullUrl');
            return fullUrl;
          }
          debugPrint('Final photo URL: $url');
          return url;
        }
      } else {
        debugPrint('Upload failed with status: ${response.statusCode}');
        final errorBody = await response.stream.bytesToString();
        debugPrint('Error response: $errorBody');
      }
    } catch (e) {
      debugPrint('Error uploading foto: $e');
    }

    return null;
  }

  void _applyPhotoPick(CsOrderPhotoPickResult? result) {
    if (result == null || !result.hasPhoto) return;
    setState(() {
      if (result.bytes != null) {
        _fotoBytes = result.bytes;
        _fotoName = result.fileName;
        _fotoFile = null;
      } else if (result.file != null) {
        _fotoFile = result.file;
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

  Future<void> _scanAndFill(
    TextEditingController controller, {
    VoidCallback? onFilled,
  }) async {
    final v = await pushQrScanPage(context);
    if (!mounted || v == null) return;
    controller.text = v;
    onFilled?.call();
  }

  Future<void> _tryAutoSelectItemByCode(String code) async {
    final query = code.trim();
    if (query.isEmpty) return;

    try {
      // Try to resolve an item from stock by code.
      // If found, we switch to from_stock and auto-fill fields.
      final baseUrl = NetworkConfig.baseUrl;
      final userState = ref.read(userStateProvider);
      final branchId = userState.branch;

      Future<List<Map<String, dynamic>>> fetchExact({String? status}) async {
        final uri = Uri.parse(
          '$baseUrl/items?item_code=$query&limit=5'
          '${branchId.isNotEmpty ? '&branch_id=$branchId' : ''}'
          '${status != null ? '&status=$status' : ''}',
        );
        final resp = await http.get(uri, headers: NetworkConfig.defaultHeaders);
        if (resp.statusCode != 200) return [];
        final List<dynamic> data = jsonDecode(resp.body);
        return data.map((e) => e as Map<String, dynamic>).toList();
      }

      Future<List<Map<String, dynamic>>> fetchSellableOnly() async {
        final uri = Uri.parse(
          '$baseUrl/items?item_code=$query&sellable_only=true&limit=5'
          '${branchId.isNotEmpty ? '&branch_id=$branchId' : ''}',
        );
        final resp = await http.get(uri, headers: NetworkConfig.defaultHeaders);
        if (resp.statusCode != 200) return [];
        final List<dynamic> data = jsonDecode(resp.body);
        return data.map((e) => e as Map<String, dynamic>).toList();
      }

      List<Map<String, dynamic>> suggestions = [];
      // Hanya stok layak jual (bukan buyback / servis / custom).
      suggestions = await fetchExact(status: 'ready');
      if (suggestions.isEmpty) {
        suggestions = await fetchExact(status: 'available');
      }
      if (suggestions.isEmpty) {
        suggestions = await fetchSellableOnly();
      }
      // If still empty, fallback to search (hanya stok layak jual).
      if (suggestions.isEmpty) {
        suggestions = await _fetchItemSuggestions(query);
      }
      if (!mounted) return;

      final normalized = query.toLowerCase();
      Map<String, dynamic>? exact;

      for (final item in suggestions) {
        final itemCode = (item['kode_produk'] ?? item['item_code'] ?? '')
            .toString()
            .trim()
            .toLowerCase();
        if (itemCode == normalized) {
          exact = item;
          break;
        }
      }

      if (exact == null) return;
      final Map<String, dynamic> selected = exact;

      _applySelectedStockItem(selected);
    } catch (_) {
      // best-effort: jangan ganggu flow user kalau gagal
    }
  }

  bool _isSellableStockStatus(String? raw) {
    final s = (raw ?? '').toString().trim().toLowerCase();
    return s == 'ready' || s == 'available' || s == 'reserved';
  }

  void _applySelectedStockItem(Map<String, dynamic> item) {
    if (!_isSellableStockStatus(item['status']?.toString())) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Barang status "${item['status']}" tidak boleh dijual langsung '
              '(mis. buyback — kirim ke warehouse dulu setelah diproses).',
            ),
          ),
        );
      }
      return;
    }
    setState(() {
      _saleType = 'from_stock';
      _selectedItem = item;
      _itemCodeController.text = item['kode_produk'] ?? item['item_code'] ?? '';
      _namaItemController.text = item['name'] ?? '';
      _beratController.text = item['weight']?.toString() ?? '';
      _materialController.text = (item['material'] ?? '').toString();
      _kadarController.text = (item['purity'] ?? '').toString();
      _kategoriController.text = item['kategori'] ?? '';
      _jenisController.text = item['jenis'] ?? '';
      _tipeController.text = item['tipe'] ?? '';
      _qtyController.text = '1';
    });

    _calculateJumlah();
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
          if (mounted) {
            setState(() {
              _selectedCustomer = data['data'];
              _customerController.text =
                  data['data']['name'] ?? data['data']['nama'] ?? '';
              _customerPhoneController.text =
                  data['data']['phone'] ?? data['data']['no_hp'] ?? '';
              _customerAddressController.text =
                  data['data']['address'] ?? data['data']['alamat'] ?? '';
              _autocompleteKey++; // Force rebuild Autocomplete
            });
          }
          // Force another rebuild to ensure UI updates
          if (mounted) {
            setState(() {});
          }
          // Refresh customers list
          WidgetsBinding.instance.addPostFrameCallback((_) {
            ref.read(customersProvider.notifier).fetchCustomers();
          });
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

  Future<void> _submitOrder() async {
    if (!_formKey.currentState!.validate()) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Mohon isi semua field yang wajib!')),
        );
      }
      return;
    }

    if (_selectedCustomer == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Pilih customer terlebih dahulu!')),
        );
      }
      return;
    }

    // Validasi kategori untuk UNREGISTERED dan QSR
    if ((_saleType == 'unregistered' || _saleType == 'qsr') &&
        _kategoriController.text.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Pilih kategori item terlebih dahulu!')),
        );
      }
      return;
    }

    // Validasi foto untuk QSR
    if (_saleType == 'qsr' && !_hasFoto) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Foto WAJIB untuk Quick Stock Registration (QSR)!'),
          ),
        );
      }
      return;
    }

    setState(() {
      _isSubmitting = true;
    });

    final userState = ref.read(userStateProvider);
    final branchId = int.tryParse(userState.branch);
    final userId = userState.userId;

    if (userId == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('User belum login. Silakan login ulang.'),
          ),
        );
      }
      setState(() {
        _isSubmitting = false;
      });
      return;
    }

    String? fotoUrl;
    if (_hasFoto) {
      debugPrint('Foto file exists, uploading...');
      fotoUrl = await _uploadProductPhoto();
      debugPrint('Foto URL result: $fotoUrl');
    } else {
      debugPrint('No foto file to upload');
    }

    // If user picked a photo but upload failed, stop here.
    if (_hasFoto && (fotoUrl == null || fotoUrl.toString().trim().isEmpty)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Upload foto gagal. Coba ambil foto ulang atau pilih dari galeri (JPEG/PNG).',
            ),
          ),
        );
      }
      setState(() {
        _isSubmitting = false;
      });
      return;
    }

    // Pastikan order_items.photo_produk terisi:
    // - Jika ambil dari stok dan item belum punya foto, maka foto wajib diupload.
    if (_saleType == 'from_stock' && !_hasFoto) {
      final existingPhoto =
          (_selectedItem?['photo_url'] ?? _selectedItem?['photo_produk'] ?? '')
              .toString()
              .trim();
      if (existingPhoto.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Foto produk WAJIB diisi untuk item stok tanpa foto.',
              ),
            ),
          );
        }
        setState(() {
          _isSubmitting = false;
        });
        return;
      }
    }

    // Prepare order data according to new schema (tabel2.txt)
    Map<String, dynamic> orderData = {
      'order_type': 'jual',
      'order_number': _notaOrderController.text.isNotEmpty
          ? _notaOrderController.text
          : null,
      'branch_id': branchId,
      'user_id': userId,
      'mode': _modeToko,
      'customer_id': _selectedCustomer!['customer_id'],
      'diskon': double.tryParse(_diskonController.text) ?? 0.0,
    };

    // Handle different sale types according to perubahan.txt
    if (_saleType == 'from_stock') {
      // Ambil dari stok: ready → reserved → sold, inventory, is_quick_registered=false
      if (_selectedItem == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Pilih item dari stok terlebih dahulu!'),
            ),
          );
        }
        return;
      }
      orderData['item_id'] = _selectedItem!['item_id'];
    } else {
      // For unregistered or QSR - create new item
      Map<String, dynamic> itemData = {
        'name': _namaItemController.text,
        'weight': double.tryParse(_beratController.text),
        'kategori': _kategoriController.text,
        'jenis': _jenisController.text,
        'tipe': _tipeController.text,
        'photo_url': fotoUrl,
        'branch_id': branchId,
        'source': 'manual',
      };

      final material = _materialController.text.trim();
      final kadar = _kadarController.text.trim();
      if (material.isNotEmpty) itemData['material'] = material;
      if (kadar.isNotEmpty) itemData['purity'] = kadar;

      if (_saleType == 'qsr') {
        // QSR: Daftarkan & jual sekarang
        // is_quick_registered = true, ownership = toko, stock_type = inventory, status = reserved → sold
        itemData['is_quick_registered'] = true;
        itemData['ownership'] = 'toko';
        itemData['stock_type'] = 'inventory';
        itemData['status'] = 'reserved'; // Will become sold after order
      } else {
        // Barang belum terdaftar: unregistered → sold, non_inventory
        itemData['ownership'] = 'unknown';
        itemData['stock_type'] = 'non_inventory';
        itemData['status'] = 'unregistered'; // Will become sold after order
      }

      orderData['item_data'] = itemData;
    }

    // Prepare order_items data according to new schema
    List<Map<String, dynamic>> orderItems = [];

    if (_saleType == 'from_stock' && _selectedItem != null) {
      // For stock items
      final existingPhoto =
          (_selectedItem?['photo_url'] ??
                  _selectedItem?['photo_produk'] ??
                  _selectedItem?['photo'] ??
                  '')
              .toString()
              .trim();
      final photoProduk = (fotoUrl?.toString().trim().isNotEmpty ?? false)
          ? fotoUrl
          : (existingPhoto.isNotEmpty ? existingPhoto : null);
      debugPrint('Order item photo_produk (from_stock): $photoProduk');

      orderItems.add({
        'item_id': _selectedItem!['item_id'],
        'nama_item': _selectedItem!['name'] ?? _namaItemController.text,
        'kode_produk':
            _selectedItem!['kode_produk'] ?? _selectedItem!['item_code'],
        'weight':
            double.tryParse(_beratController.text) ?? _selectedItem!['weight'],
        'qty': int.tryParse(_qtyController.text) ?? 1,
        'harga_per_gram': _parseNumberWithSeparators(
          _hargaPerGramController.text,
        ),
        'photo_produk': photoProduk,
        'kategori': _selectedItem!['kategori'] ?? _kategoriController.text,
        'jenis': _selectedItem!['jenis'] ?? _jenisController.text,
        'tipe': _selectedItem!['tipe'] ?? _tipeController.text,
      });

      final material = _materialController.text.trim();
      final kadar = _kadarController.text.trim();
      if (material.isNotEmpty) orderItems.last['material'] = material;
      if (kadar.isNotEmpty) orderItems.last['purity'] = kadar;
    } else {
      // For new/unregistered items
      debugPrint('Order item photo_produk (new item): $fotoUrl');

      orderItems.add({
        'nama_item': _namaItemController.text,
        'kode_produk': _itemCodeController.text.isNotEmpty
            ? _itemCodeController.text
            : null,
        'weight': double.tryParse(_beratController.text),
        'qty': int.tryParse(_qtyController.text) ?? 1,
        'harga_per_gram': _parseNumberWithSeparators(
          _hargaPerGramController.text,
        ),
        'photo_produk': fotoUrl,
        'kategori': _kategoriController.text,
        'jenis': _jenisController.text,
        'tipe': _tipeController.text,
      });

      final material = _materialController.text.trim();
      final kadar = _kadarController.text.trim();
      if (material.isNotEmpty) orderItems.last['material'] = material;
      if (kadar.isNotEmpty) orderItems.last['purity'] = kadar;
    }

    orderData['order_items'] = orderItems;

    debugPrint('Submitting order payload with ${orderItems.length} item(s)');

    try {
      final baseUrl = NetworkConfig.baseUrl;
      debugPrint('Submitting order to: $baseUrl/orders');

      final response = await http.post(
        Uri.parse('$baseUrl/orders'),
        headers: NetworkConfig.defaultHeaders,
        body: jsonEncode(orderData),
      );

      if (response.statusCode == 201 || response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final fakturData = <String, dynamic>{
          ...(data is Map<String, dynamic> ? data : <String, dynamic>{}),
          // Ensure customer fields are present for immediate Faktur display
          'customer_name':
              (data is Map<String, dynamic> &&
                  (data['customer_name']?.toString().trim().isNotEmpty ??
                      false))
              ? data['customer_name']
              : _customerController.text,
          'customer_phone':
              (data is Map<String, dynamic> &&
                  (data['customer_phone']?.toString().trim().isNotEmpty ??
                      false))
              ? data['customer_phone']
              : _customerPhoneController.text,
          'customer_address':
              (data is Map<String, dynamic> &&
                  (data['customer_address']?.toString().trim().isNotEmpty ??
                      false))
              ? data['customer_address']
              : _customerAddressController.text,
        };

        // Refresh order hari ini (stats + list) — bundle dipicu dari stats provider.
        if (mounted) {
          ref.invalidate(orderTodayStatsProvider);
          ref.invalidate(todayOrdersProvider);
          bumpCsDailyOrdersListRevision(ref);
        }

        if (mounted) {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (context) => FakturPage(orderData: fakturData),
            ),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Gagal menyimpan order: ${response.body}')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Terjadi error: $e')));
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }

  Future<List<Map<String, dynamic>>> _fetchItemSuggestions(String query) async {
    if (query.isEmpty) return [];

    try {
      final baseUrl = NetworkConfig.baseUrl;
      final userState = ref.read(userStateProvider);
      final branchId = userState.branch;
      final isFromStock = _saleType == 'from_stock';

      final uri = Uri.parse(
        '$baseUrl/items?search=$query&limit=10'
        '${branchId.isNotEmpty ? '&branch_id=$branchId' : ''}'
        '${isFromStock ? '&sellable_only=true' : ''}',
      );
      final response = await http.get(
        uri,
        headers: NetworkConfig.defaultHeaders,
      );

      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        return data.map((item) => item as Map<String, dynamic>).toList();
      }
      return [];
    } catch (e) {
      return [];
    }
  }

  void _updateItemSuggestions(String query) {
    if (query.isEmpty) {
      setState(() {
        _itemSuggestions = List<Map<String, dynamic>>.from(
          [],
        ); // Create new empty list
        _isLoadingSuggestions = false;
      });
      return;
    }

    setState(() {
      _isLoadingSuggestions = true;
    });

    // Cancel previous timer
    _itemSearchTimer?.cancel();

    // Debounce the search
    _itemSearchTimer = Timer(const Duration(milliseconds: 300), () async {
      try {
        final suggestions = await _fetchItemSuggestions(query);
        if (mounted) {
          setState(() {
            _itemSuggestions = List<Map<String, dynamic>>.from(
              suggestions,
            ); // Create new list
            _isLoadingSuggestions = false;
          });

          // Autofill when user typed an exact code (no need to tap a suggestion).
          final normalized = query.trim().toLowerCase();
          if (normalized.isNotEmpty) {
            for (final item in suggestions) {
              final code = (item['kode_produk'] ?? item['item_code'] ?? '')
                  .toString()
                  .trim()
                  .toLowerCase();
              if (code == normalized) {
                _applySelectedStockItem(item);
                break;
              }
            }
          }
        }
      } catch (e) {
        if (mounted) {
          setState(() {
            _itemSuggestions = List<Map<String, dynamic>>.from(
              [],
            ); // Create new empty list
            _isLoadingSuggestions = false;
          });
        }
      }
    });
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
      appBar: AppBar(title: const Text('Form Order Jual')),
      body: ResponsiveLayout.scrollableForm(
        context: context,
        formKey: _formKey,
        children: [
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
              const SizedBox(height: 12.0),

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

              // 2. Customer Section
              Row(
                children: [
                  const SizedBox(
                    width: 100,
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text('Customer'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: StatefulBuilder(
                      builder: (context, setFieldState) {
                        return Row(
                          children: [
                            Expanded(
                              child: customerList.isLoading
                                  ? const TextField(
                                      decoration: InputDecoration(
                                        border: OutlineInputBorder(),
                                        hintText: 'Loading customers...',
                                      ),
                                      enabled: false,
                                    )
                                  : customerList.error != null
                                  ? TextField(
                                      decoration: InputDecoration(
                                        border: OutlineInputBorder(),
                                        hintText: 'Error loading customers',
                                        errorText: customerList.error,
                                      ),
                                      enabled: false,
                                    )
                                  : (() {
                                      Logger.logInfo(
                                        'DEBUG: Showing Autocomplete - isLoading: ${customerList.isLoading}, error: ${customerList.error}, customers count: ${customerList.customers.length}',
                                      );
                                      return Autocomplete<Map<String, dynamic>>(
                                        key: ValueKey(_autocompleteKey),
                                        optionsBuilder: (TextEditingValue textEditingValue) {
                                          Logger.logInfo(
                                            'DEBUG: Autocomplete optionsBuilder called with text: "${textEditingValue.text}"',
                                          );
                                          Logger.logInfo(
                                            'DEBUG: customerList.customers length: ${customerList.customers.length}',
                                          );
                                          Logger.logInfo(
                                            'DEBUG: customerList.customers: ${customerList.customers}',
                                          );
                                          if (textEditingValue.text == '') {
                                            return const Iterable<
                                              Map<String, dynamic>
                                            >.empty();
                                          }
                                          final input = textEditingValue.text
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
                                                Logger.logInfo(
                                                  'DEBUG: Checking customer: $name against input: $input',
                                                );
                                                return name.contains(input);
                                              })
                                              .toList();
                                          Logger.logInfo(
                                            'DEBUG: Found ${suggestions.length} suggestions',
                                          );
                                          return suggestions; // Return new list each time
                                        },
                                        displayStringForOption: (option) =>
                                            option['name'] ??
                                            option['nama'] ??
                                            '',
                                        onSelected: (customer) {
                                          setState(() {
                                            _customerController.text =
                                                customer['name'] ??
                                                customer['nama'] ??
                                                '';
                                            _customerPhoneController.text =
                                                customer['phone'] ??
                                                customer['no_hp'] ??
                                                '';
                                            _customerAddressController.text =
                                                customer['address'] ??
                                                customer['alamat'] ??
                                                '';
                                            _selectedCustomer = customer;
                                          });
                                        },
                                        fieldViewBuilder:
                                            (
                                              context,
                                              controller,
                                              focusNode,
                                              onFieldSubmitted,
                                            ) {
                                              // Sync the autocomplete controller with our class-level controller
                                              if (controller.text !=
                                                  _customerController.text) {
                                                controller.text =
                                                    _customerController.text;
                                                controller.selection =
                                                    TextSelection.fromPosition(
                                                      TextPosition(
                                                        offset: controller
                                                            .text
                                                            .length,
                                                      ),
                                                    );
                                              }
                                              return Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Row(
                                                    children: [
                                                      Expanded(
                                                        child: TextFormField(
                                                          controller:
                                                              controller, // Use the autocomplete controller
                                                          focusNode: focusNode,
                                                          decoration: const InputDecoration(
                                                            border:
                                                                OutlineInputBorder(),
                                                            contentPadding:
                                                                EdgeInsets.symmetric(
                                                                  vertical: 12,
                                                                  horizontal:
                                                                      12,
                                                                ),
                                                          ),
                                                          onChanged: (value) {
                                                            // Sync back to class-level controller
                                                            _customerController
                                                                    .text =
                                                                value;
                                                            setState(() {});
                                                          },
                                                          onFieldSubmitted:
                                                              (value) =>
                                                                  onFieldSubmitted(),
                                                          validator: (value) {
                                                            if (value == null ||
                                                                value.isEmpty) {
                                                              return 'Nama customer wajib diisi';
                                                            }
                                                            return null;
                                                          },
                                                        ),
                                                      ),
                                                      Builder(
                                                        builder: (context) {
                                                          final input =
                                                              controller.text
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
                                                                    input
                                                                        .isNotEmpty;
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
                                                                    Icons
                                                                        .person_add,
                                                                  ),
                                                                  tooltip:
                                                                      'Tambah Customer',
                                                                  onPressed: () =>
                                                                      _showAddCustomerDialog(
                                                                        controller
                                                                            .text,
                                                                        controller,
                                                                      ),
                                                                ),
                                                                IconButton(
                                                                  icon: const Icon(
                                                                    Icons
                                                                        .qr_code_scanner,
                                                                  ),
                                                                  tooltip:
                                                                      'Scan QR Customer',
                                                                  onPressed: () =>
                                                                      _scanAndFill(
                                                                        controller,
                                                                      ),
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
                                                                    Icons
                                                                        .person_add,
                                                                  ),
                                                                  tooltip:
                                                                      'Tambah Customer',
                                                                  onPressed: () =>
                                                                      _showAddCustomerDialog(
                                                                        controller
                                                                            .text,
                                                                        controller,
                                                                      ),
                                                                ),
                                                                IconButton(
                                                                  icon: const Icon(
                                                                    Icons
                                                                        .qr_code_scanner,
                                                                  ),
                                                                  tooltip:
                                                                      'Scan QR Customer',
                                                                  onPressed: () =>
                                                                      _scanAndFill(
                                                                        controller,
                                                                      ),
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
                                                    const SizedBox(height: 4),
                                                    Text(
                                                      'Phone: ${_selectedCustomer!['phone'] ?? _selectedCustomer!['no_hp'] ?? 'N/A'} | Address: ${_selectedCustomer!['address'] ?? _selectedCustomer!['alamat'] ?? 'N/A'}',
                                                      style: const TextStyle(
                                                        fontSize: 12,
                                                        color: Colors.grey,
                                                      ),
                                                    ),
                                                  ],
                                                ],
                                              );
                                            },
                                      );
                                    })(),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12.0),

              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Tipe Stok'),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8.0,
                    runSpacing: 8.0,
                    children: [
                      ChoiceChip(
                        label: const Text('STOK'),
                        selected: _saleType == 'from_stock',
                        onSelected: (selected) {
                          setState(() {
                            _saleType = 'from_stock';
                            _selectedItem = null;
                            _namaItemController.clear();
                            _beratController.clear();
                            _materialController.clear();
                            _materialChoice = 'EMAS';
                            _kadarController.clear();
                            _itemCodeController.clear();
                            _itemAutocompleteFieldController?.clear();
                            _kategoriController.clear();
                            _jenisController.clear();
                            _tipeController.clear();
                            _qtyController.text = '1'; // Keep qty as 1
                          });
                        },
                      ),
                      ChoiceChip(
                        label: const Text('UNREGISTERED'),
                        selected: _saleType == 'unregistered',
                        onSelected: (selected) {
                          setState(() {
                            _saleType = 'unregistered';
                            _selectedItem = null;
                            if (_kategoriController.text.isEmpty) {
                              _kategoriController.text = 'PERHIASAN';
                            }
                            // Clear jenis so user must select from appropriate buttons
                            _jenisController.clear();
                            if (_tipeController.text.isEmpty) {
                              _tipeController.text = 'PERHIASAN';
                            }
                            // Default material selection for unregistered
                            _materialChoice = 'EMAS';
                            _materialController.text = _materialChoice;
                            _qtyController.text = '1'; // Keep qty as 1
                          });
                        },
                      ),
                      ChoiceChip(
                        label: const Text('QSR (Cepat)'),
                        selected: _saleType == 'qsr',
                        onSelected: (selected) {
                          setState(() {
                            _saleType = 'qsr';
                            _selectedItem = null;
                            if (_kategoriController.text.isEmpty) {
                              _kategoriController.text = 'PERHIASAN';
                            }
                            // Clear jenis so user must select from appropriate buttons
                            _jenisController.clear();
                            if (_tipeController.text.isEmpty) {
                              _tipeController.text = 'PERHIASAN';
                            }
                            // Default material selection for QSR
                            _materialChoice = 'EMAS';
                            _materialController.text = _materialChoice;
                            _qtyController.text = '1'; // Keep qty as 1
                          });
                        },
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 8.0),
              if (_saleType == 'qsr') ...[
                Container(
                  padding: const EdgeInsets.all(8.0),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(8.0),
                    border: Border.all(color: Colors.blue.shade200),
                  ),
                  child: Text(
                    'QSR (Quick Stock Registration): Daftarkan barang baru ke stok dan jual langsung. Foto wajib diisi.',
                    style: TextStyle(fontSize: 12, color: Colors.blue.shade800),
                  ),
                ),
              ],
              const SizedBox(height: 12.0),

              // 5. Item Information Section

              // Kode Produk
              Row(
                children: [
                  const SizedBox(
                    width: 100,
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text('Kode Produk'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Row(
                      children: [
                        Expanded(
                          child: Autocomplete<Map<String, dynamic>>(
                            initialValue: _selectedItem != null
                                ? TextEditingValue(
                                    text:
                                        _selectedItem!['kode_produk'] ??
                                        _selectedItem!['item_code'] ??
                                        '',
                                  )
                                : null,
                            optionsBuilder:
                                (TextEditingValue textEditingValue) {
                                  // Always trigger search when text changes
                                  _updateItemSuggestions(textEditingValue.text);
                                  return _itemSuggestions;
                                },
                            displayStringForOption: (option) {
                              final code =
                                  option['kode_produk'] ??
                                  option['item_code'] ??
                                  '';
                              final name = option['name'] ?? '';
                              return '$code - $name';
                            },
                            onSelected: (item) {
                              setState(() {
                                _saleType =
                                    'from_stock'; // Auto-switch to stock mode
                                _selectedItem = item;
                                _itemCodeController.text =
                                    item['kode_produk'] ??
                                    item['item_code'] ??
                                    '';
                                _namaItemController.text = item['name'] ?? '';
                                _beratController.text =
                                    item['weight']?.toString() ?? '';
                                _materialController.text =
                                    (item['material'] ?? '').toString();
                                _kadarController.text = (item['purity'] ?? '')
                                    .toString();
                                _kategoriController.text =
                                    item['kategori'] ?? '';
                                _jenisController.text = item['jenis'] ?? '';
                                _tipeController.text = item['tipe'] ?? '';
                                _qtyController.text =
                                    '1'; // Default qty for stock items
                              });

                              // Calculate jumlah after item selection
                              _calculateJumlah();

                              if (mounted) {
                                WidgetsBinding.instance.addPostFrameCallback((
                                  _,
                                ) {
                                  if (mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          'Item "${item['name']}" dipilih. Mode diubah ke STOK',
                                        ),
                                        backgroundColor: Colors.green,
                                      ),
                                    );
                                  }
                                });
                              }
                            },
                            fieldViewBuilder:
                                (
                                  context,
                                  controller,
                                  focusNode,
                                  onFieldSubmitted,
                                ) {
                                  _itemAutocompleteFieldController = controller;
                                  return TextFormField(
                                    controller: controller,
                                    focusNode: focusNode,
                                    decoration: InputDecoration(
                                      border: const OutlineInputBorder(),
                                      hintText: 'Kode produk item',
                                      suffixIcon: _isLoadingSuggestions
                                          ? const SizedBox(
                                              width: 20,
                                              height: 20,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                              ),
                                            )
                                          : null,
                                    ),
                                    onChanged: (value) {
                                      // Update controller when text changes
                                      _itemCodeController.text = value;
                                      // Trigger search
                                      _updateItemSuggestions(value);
                                    },
                                    onFieldSubmitted: (value) async {
                                      onFieldSubmitted();
                                      await _tryAutoSelectItemByCode(value);
                                    },
                                    onEditingComplete: () async {
                                      final code = controller.text;
                                      await _tryAutoSelectItemByCode(code);
                                    },
                                  );
                                },
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.qr_code_scanner),
                          tooltip: 'Scan QR Kode Produk',
                          onPressed: () => _scanAndFill(
                            _itemAutocompleteFieldController ??
                                _itemCodeController,
                            onFilled: () async {
                              final code =
                                  (_itemAutocompleteFieldController ??
                                          _itemCodeController)
                                      .text;
                              _itemCodeController.text = code;
                              _updateItemSuggestions(code);
                              await _tryAutoSelectItemByCode(code);
                              if (mounted) setState(() {});
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12.0),

              // Kategori (untuk from_stock, tampilkan di atas jenis)
              if (_saleType == 'from_stock')
                Row(
                  children: [
                    const SizedBox(
                      width: 100,
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text('Kategori'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextFormField(
                        controller: _kategoriController,
                        readOnly: true,
                        decoration: InputDecoration(
                          border: const OutlineInputBorder(),
                          hintText: 'Otomatis dari item',
                          filled: true,
                          fillColor: Colors.grey[100],
                        ),
                      ),
                    ),
                  ],
                ),
              if (_saleType == 'from_stock') const SizedBox(height: 12.0),

              // Field kategori, jenis, tipe - read-only untuk from_stock, wajib untuk item baru
              // Kategori (hanya tampilkan untuk non-from_stock)
              if (_saleType != 'from_stock')
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_saleType == 'from_stock' ? 'Kategori' : 'Kategori *'),
                    const SizedBox(height: 8),
                    if (_saleType == 'from_stock')
                      TextFormField(
                        controller: _kategoriController,
                        readOnly: true,
                        decoration: InputDecoration(
                          border: const OutlineInputBorder(),
                          hintText: 'Otomatis dari item',
                          filled: true,
                          fillColor: Colors.grey[100],
                        ),
                      )
                    else if (_saleType == 'unregistered' || _saleType == 'qsr')
                      Wrap(
                        spacing: 8.0,
                        runSpacing: 8.0,
                        children: [
                          ChoiceChip(
                            label: const Text('PERHIASAN'),
                            selected: _kategoriController.text == 'PERHIASAN',
                            onSelected: (selected) {
                              if (selected) {
                                setState(() {
                                  _kategoriController.text = 'PERHIASAN';
                                  _jenisController
                                      .clear(); // Clear jenis when kategori changes
                                });
                              }
                            },
                          ),
                          ChoiceChip(
                            label: const Text('AKSESORIES'),
                            selected: _kategoriController.text == 'AKSESORIES',
                            onSelected: (selected) {
                              if (selected) {
                                setState(() {
                                  _kategoriController.text = 'AKSESORIES';
                                  _jenisController
                                      .clear(); // Clear jenis when kategori changes
                                });
                              }
                            },
                          ),
                          ChoiceChip(
                            label: const Text('LOGAM MULIA'),
                            selected: _kategoriController.text == 'LOGAM MULIA',
                            onSelected: (selected) {
                              if (selected) {
                                setState(() {
                                  _kategoriController.text = 'LOGAM MULIA';
                                  _jenisController
                                      .clear(); // Clear jenis when kategori changes
                                });
                              }
                            },
                          ),
                        ],
                      )
                    else
                      TextFormField(
                        controller: _kategoriController,
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                          hintText: 'Kategori item',
                        ),
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Kategori wajib diisi';
                          }
                          return null;
                        },
                      ),
                  ],
                ),
              if (_saleType != 'from_stock') const SizedBox(height: 12.0),

              // Jenis
              _saleType == 'from_stock'
                  ? Row(
                      children: [
                        SizedBox(
                          width: 100,
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: Text('Jenis'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextFormField(
                            controller: _jenisController,
                            readOnly: true,
                            decoration: InputDecoration(
                              border: const OutlineInputBorder(),
                              hintText: 'Otomatis dari item',
                              filled: true,
                              fillColor: Colors.grey[100],
                            ),
                          ),
                        ),
                      ],
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Jenis *'),
                        const SizedBox(height: 8),
                        (_saleType == 'unregistered' || _saleType == 'qsr')
                            ? Wrap(
                                spacing: 8.0,
                                runSpacing: 8.0,
                                children:
                                    orderItemJenisOptionsForKategori(
                                          _kategoriController.text,
                                        )
                                        .map(
                                          (jenis) => ChoiceChip(
                                            label: Text(jenis),
                                            selected:
                                                _jenisController.text == jenis,
                                            onSelected: (selected) {
                                              if (selected) {
                                                setState(() {
                                                  _jenisController.text = jenis;
                                                });
                                              }
                                            },
                                          ),
                                        )
                                        .toList(),
                              )
                            : TextFormField(
                                controller: _jenisController,
                                decoration: const InputDecoration(
                                  border: OutlineInputBorder(),
                                  hintText: 'Jenis item',
                                ),
                                validator: (value) {
                                  if (value == null || value.isEmpty) {
                                    return 'Jenis wajib diisi';
                                  }
                                  return null;
                                },
                              ),
                      ],
                    ),
              const SizedBox(height: 12.0),

              // Tipe
              Row(
                children: [
                  SizedBox(
                    width: 100,
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        _saleType == 'from_stock'
                            ? 'Tipe Barang'
                            : 'Tipe Barang *',
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _saleType == 'from_stock'
                        ? TextFormField(
                            controller: _tipeController,
                            readOnly: true,
                            decoration: InputDecoration(
                              border: const OutlineInputBorder(),
                              hintText: 'Otomatis dari item',
                              filled: true,
                              fillColor: Colors.grey[100],
                            ),
                          )
                        : Wrap(
                            spacing: 8.0,
                            runSpacing: 8.0,
                            children: [
                              ChoiceChip(
                                label: const Text('BIASA'),
                                selected: _tipeController.text == 'BIASA',
                                onSelected: (selected) {
                                  if (selected) {
                                    setState(() {
                                      _tipeController.text = 'BIASA';
                                    });
                                  }
                                },
                              ),
                              ChoiceChip(
                                label: const Text('GRESS'),
                                selected: _tipeController.text == 'GRESS',
                                onSelected: (selected) {
                                  if (selected) {
                                    setState(() {
                                      _tipeController.text = 'GRESS';
                                    });
                                  }
                                },
                              ),
                            ],
                          ),
                  ),
                ],
              ),
              const SizedBox(height: 12.0),

              // Nama Item
              Row(
                children: [
                  const SizedBox(
                    width: 100,
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
                        hintText: 'Contoh: Gelang Emas',
                      ),
                      readOnly: _saleType == 'from_stock',
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
              const SizedBox(height: 12.0),

              // Material (opsional)
              Row(
                children: [
                  const SizedBox(
                    width: 100,
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text('Material'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _saleType == 'from_stock'
                        ? TextFormField(
                            controller: _materialController,
                            decoration: const InputDecoration(
                              border: OutlineInputBorder(),
                              hintText: 'Otomatis dari item (opsional)',
                            ),
                            readOnly: true,
                          )
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  ChoiceChip(
                                    label: const Text('EMAS'),
                                    selected: _materialChoice == 'EMAS',
                                    onSelected: (selected) {
                                      if (!selected) return;
                                      setState(() {
                                        _materialChoice = 'EMAS';
                                        _materialController.text = 'EMAS';
                                      });
                                    },
                                  ),
                                  ChoiceChip(
                                    label: const Text('PERAK'),
                                    selected: _materialChoice == 'PERAK',
                                    onSelected: (selected) {
                                      if (!selected) return;
                                      setState(() {
                                        _materialChoice = 'PERAK';
                                        _materialController.text = 'PERAK';
                                      });
                                    },
                                  ),
                                  ChoiceChip(
                                    label: const Text('Lainnya'),
                                    selected: _materialChoice == 'LAINNYA',
                                    onSelected: (selected) {
                                      if (!selected) return;
                                      setState(() {
                                        _materialChoice = 'LAINNYA';
                                        _materialController.clear();
                                      });
                                    },
                                  ),
                                ],
                              ),
                              if (_materialChoice == 'LAINNYA') ...[
                                const SizedBox(height: 8),
                                TextFormField(
                                  controller: _materialController,
                                  decoration: const InputDecoration(
                                    border: OutlineInputBorder(),
                                    hintText:
                                        'Tulis material (contoh: PLATINA)',
                                  ),
                                ),
                              ],
                            ],
                          ),
                  ),
                ],
              ),
              const SizedBox(height: 12.0),

              // Kadar (opsional)
              Row(
                children: [
                  const SizedBox(
                    width: 100,
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text('Kadar'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextFormField(
                      controller: _kadarController,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        hintText: 'Contoh: 70%, 22K (opsional)',
                      ),
                      readOnly: _saleType == 'from_stock',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12.0),

              // Berat
              Row(
                children: [
                  const SizedBox(
                    width: 100,
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text('Berat'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextFormField(
                      controller: _beratController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        hintText: 'gram',
                      ),
                      readOnly: _saleType == 'from_stock',
                      onChanged: _saleType != 'from_stock'
                          ? (value) {
                              WidgetsBinding.instance.addPostFrameCallback((_) {
                                _calculateJumlah();
                              });
                            }
                          : null,
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Berat wajib diisi';
                        }
                        final weight = double.tryParse(value);
                        if (weight == null || weight <= 0) {
                          return 'Berat harus angka positif';
                        }
                        return null;
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12.0),

              // Quantity
              Row(
                children: [
                  const SizedBox(
                    width: 100,
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text('Qty'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextFormField(
                      controller: _qtyController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        hintText: 'Jumlah item',
                      ),
                      onChanged: (value) {
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          _calculateJumlah();
                        });
                      },
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Qty wajib diisi';
                        }
                        final qty = int.tryParse(value);
                        if (qty == null || qty <= 0) {
                          return 'Qty harus angka positif';
                        }
                        return null;
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12.0),

              // Detail Penjualan (Order Items)

              // Harga Per Gram
              Row(
                children: [
                  const SizedBox(
                    width: 100,
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text('Harga/gram'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextFormField(
                      controller: _hargaPerGramController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        hintText: 'Rp per gram',
                      ),
                      onChanged: (value) {
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          _calculateJumlah();
                        });
                      },
                      onEditingComplete: () {
                        // Format with thousand separators when user finishes editing
                        final formatted = _formatNumberWithSeparators(
                          _hargaPerGramController.text,
                        );
                        _hargaPerGramController.text = formatted;
                      },
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Harga per gram wajib diisi';
                        }
                        final price = _parseNumberWithSeparators(value);
                        if (price <= 0) {
                          return 'Harga per gram harus lebih dari 0';
                        }
                        return null;
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12.0),

              // Diskon
              Row(
                children: [
                  const SizedBox(
                    width: 100,
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text('Diskon (%)'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextFormField(
                      controller: _diskonController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        hintText: 'Diskon dalam persen',
                      ),
                      onChanged: (value) {
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          _calculateJumlah();
                        });
                      },
                      validator: (value) {
                        if (value != null && value.isNotEmpty) {
                          final discount = double.tryParse(value);
                          if (discount == null ||
                              discount < 0 ||
                              discount > 100) {
                            return 'Diskon harus antara 0-100';
                          }
                        }
                        return null;
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12.0),

              // Jumlah (Total Amount after discount)
              Row(
                children: [
                  const SizedBox(
                    width: 100,
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text('Jumlah'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextFormField(
                      controller: _jumlahController,
                      readOnly: true,
                      decoration: InputDecoration(
                        border: const OutlineInputBorder(),
                        hintText: 'Total otomatis',
                        filled: true,
                        fillColor: Colors.grey[100],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12.0),

              CsOrderPhotoField(
                hasPhoto: _hasFoto,
                imageBytes: _fotoBytes,
                imageFile: _fotoFile,
                onCamera: _pickFoto,
                onGallery: _pickFotoFromGallery,
                requiredMessage: _saleType == 'qsr' && !_hasFoto
                    ? 'Foto WAJIB untuk QSR'
                    : null,
              ),
              const SizedBox(height: 24.0),

              // Informasi Order Tambahan
              const SizedBox(height: 24.0),

              // Submit Button
              Center(
                child: ElevatedButton(
                  onPressed: _isSubmitting ? null : _submitOrder,
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      vertical: 12,
                      horizontal: 24,
                    ),
                    backgroundColor: _isSubmitting
                        ? Colors.grey
                        : Colors.orange,
                  ),
                  child: _isSubmitting
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              Colors.white,
                            ),
                          ),
                        )
                      : const Text(
                          'SUBMIT PENJUALAN',
                          style: TextStyle(fontSize: 16, color: Colors.white),
                        ),
                ),
              ),
              const SizedBox(height: 12),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _itemSearchTimer?.cancel(); // Cancel timer to prevent memory leaks
    _customerController.dispose();
    _customerPhoneController.dispose();
    _customerAddressController.dispose();
    _namaItemController.dispose();
    _beratController.dispose();
    _materialController.dispose();
    _kadarController.dispose();
    _itemCodeController.dispose();
    _notaOrderController.dispose();
    _hargaPerGramController.dispose();
    _diskonController.dispose();
    _kategoriController.dispose();
    _jenisController.dispose();
    _tipeController.dispose();
    _qtyController.dispose();
    super.dispose();
  }
}

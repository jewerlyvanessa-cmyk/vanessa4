import 'package:flutter/material.dart';
import 'dart:convert';
import 'dart:math' as math;
import 'package:vanessa3/core/network/api_client.dart';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:io';
import 'customers_page.dart';
import 'faktur_page.dart';

// Conditional imports for platform-specific packages
import 'package:image_picker/image_picker.dart'
    if (dart.library.html) '../../../utils/image_picker_stub.dart';
import 'package:vanessa3/widgets/qr_scan_route.dart';
import 'package:vanessa3/providers/user_state_provider.dart';
import 'package:vanessa3/providers/order_today_provider.dart';
import 'package:vanessa3/providers/cs_daily_orders_refresh_provider.dart';
import 'package:vanessa3/core/theme/app_typography.dart';
import 'package:vanessa3/widgets/pickup_branch_field.dart';
import 'package:vanessa3/shared_widgets/cs_order_photo_field.dart';
import 'package:vanessa3/utils/cs_order_photo_picker.dart';
import 'package:vanessa3/utils/cs_order_photo_upload.dart';
import 'package:vanessa3/utils/app_date_picker.dart';
import 'package:vanessa3/utils/responsive_layout.dart';
import 'package:vanessa3/services/cs_order_submit_service.dart';

int? toInt(dynamic value) {
  if (value is int) return value;
  if (value is String) return int.tryParse(value);
  return null;
}

class ServicePage extends ConsumerStatefulWidget {
  const ServicePage({super.key, this.client});

  final http.Client? client;

  @override
  ConsumerState<ServicePage> createState() => _ServicePageState();
}

class _ServicePageState extends ConsumerState<ServicePage> {
  final _formKey = GlobalKey<FormState>();

  // Controllers untuk form
  final TextEditingController _customerController = TextEditingController();
  final TextEditingController _customerPhoneController =
      TextEditingController();
  final TextEditingController _customerAddressController =
      TextEditingController();
  final TextEditingController _notaOrderController = TextEditingController();
  final TextEditingController _notaLamaController = TextEditingController();
  final TextEditingController _namaItemController = TextEditingController();
  final TextEditingController _beratController = TextEditingController();
  final TextEditingController _materialController = TextEditingController();
  final TextEditingController _kadarController = TextEditingController();
  final TextEditingController _keteranganServiceController =
      TextEditingController();
  final TextEditingController _estimasiSelesaiController =
      TextEditingController();
  final TextEditingController _totalBiayaController = TextEditingController();
  final TextEditingController _uangMukaController = TextEditingController();

  Map<String, dynamic>? _selectedCustomer;

  /// Referensi ke controller teks yang dipakai [Autocomplete] customer (bukan [_customerController]).
  TextEditingController? _customerAutocompleteController;
  XFile? _fotoXFile;
  Uint8List? _fotoBytes;
  String? _fotoName;
  String _modeToko = 'TOKO'; // Mode selection: TOKO or ONLINE
  String _jenisService =
      'Patri'; // Service type: Patri, Cuci, Sambung, Ubah Ukuran, Ganti Batu, Lainnya
  String _jenisBarang =
      'KALUNG'; // Item type: KALUNG, GELANG, ANTING, CINCIN, LIONTIN
  /// `null` = sama dengan cabang order (tidak kirim `pickup_branch_id`).
  int? _pickupBranchId;
  final Map<String, bool> _kelengkapan = {
    'Barang': true, // Default checked
    'Surat': false,
    'Identitas': false,
  }; // Completeness checklist

  Future<String?> _uploadFoto() async {
    if (_fotoXFile == null && _fotoBytes == null) return null;
    if (kIsWeb) {
      final bytes = _fotoBytes ?? await _fotoXFile!.readAsBytes();
      return CsOrderPhotoUpload.upload(
        bytes: bytes,
        fileName: _fotoName ?? _fotoXFile!.name,
      );
    }
    return CsOrderPhotoUpload.upload(
      file: File(_fotoXFile!.path),
      fileName: _fotoXFile!.name,
    );
  }

  double _parseMoney(String raw) {
    final s = raw.replaceAll(RegExp(r'[^0-9]'), '');
    final v = double.tryParse(s);
    return (v == null || v.isNaN || v.isInfinite) ? 0 : v;
  }

  /// Pastikan ada customer_id untuk POST /orders (backend menolak null).
  /// Cocokkan nama ke [customersProvider] bila user mengetik tanpa memilih opsi / nota tanpa ID.
  int? _resolveCustomerIdForSubmit() {
    final fromMap = toInt(_selectedCustomer?['customer_id']);
    if (fromMap != null && fromMap > 0) return fromMap;

    final name = _customerController.text.trim().isNotEmpty
        ? _customerController.text.trim()
        : (_selectedCustomer?['name'] ?? _selectedCustomer?['nama'] ?? '')
              .toString()
              .trim();
    if (name.isEmpty) return null;

    final lower = name.toLowerCase();
    for (final c in ref.read(customersProvider).customers) {
      final cn = (c['name'] ?? c['nama'] ?? '').toString().trim().toLowerCase();
      if (cn == lower) {
        final id = toInt(c['customer_id']);
        if (id != null && id > 0) return id;
      }
    }
    return null;
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

  Future<void> _scanAndFill(TextEditingController controller) async {
    final v = await pushQrScanPage(context);
    if (!mounted || v == null) return;
    controller.text = v;
  }

  /// Scan QR nomor nota lama lalu langsung cari order jual (isi customer + item).
  Future<void> _scanAndLookupNotaLama(TextEditingController controller) async {
    await _scanAndFill(controller);
    if (!mounted || controller.text.trim().isEmpty) return;
    await _lookupNotaLamaForService(controller);
  }

  Future<void> _showAddCustomerDialog(String initialName) async {
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
        final response = await ApiClient.post(
          '/api/customers',
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

  Future<void> _submitOrder() async {
    if (!_formKey.currentState!.validate()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Mohon isi semua field yang wajib!')),
      );
      return;
    }

    // Foto WAJIB untuk Service
    if (_fotoXFile == null && _fotoBytes == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Foto barang WAJIB untuk service!')),
      );
      return;
    }

    final userState = ref.read(userStateProvider);
    final branchId = int.tryParse(userState.branch);
    if (branchId == null || branchId <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Cabang tidak valid. Pilih cabang aktif lewat menu profil/cabang.',
          ),
        ),
      );
      return;
    }

    final customerId = _resolveCustomerIdForSubmit();
    if (customerId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Customer belum valid. Pilih nama dari daftar saran atau tambah customer baru.',
          ),
        ),
      );
      return;
    }

    final userId = userState.userId;

    if (userId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('User belum login. Silakan login ulang.')),
      );
      return;
    }

    String? fotoUrl;
    fotoUrl = await _uploadFoto();
    if (!mounted) return;
    if (fotoUrl == null || fotoUrl.toString().trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Upload foto gagal. Coba ambil foto ulang (JPEG/PNG).'),
        ),
      );
      return;
    }

    final weightVal = double.tryParse(_beratController.text.trim()) ?? 0;
    final totalBiayaVal = _parseMoney(_totalBiayaController.text);
    final uangMukaVal = _parseMoney(_uangMukaController.text);
    // Status awal selalu pending cabang: ada DP → kasir; tanpa DP → admin toko → workshop.
    final initialServiceStatus = 'pending';
    final generatedKodeProduk = _notaOrderController.text.trim().isNotEmpty
        ? _notaOrderController.text.trim()
        : 'SERV-${DateTime.now().millisecondsSinceEpoch}';

    final orderData = <String, dynamic>{
      'order_type': 'service',
      'status': initialServiceStatus,
      'order_number': _notaOrderController.text.isNotEmpty
          ? _notaOrderController.text
          : null,
      'branch_id': branchId,
      'user_id': userId,
      'mode': _modeToko.toLowerCase(),
      'customer_id': customerId,
      'service_estimated_total': totalBiayaVal,
      'service_dp_amount': uangMukaVal,
      'diskon': 0,
      'order_items': [
        {
          'nama_item': _namaItemController.text.trim(),
          'kode_produk': generatedKodeProduk,
          'weight': weightVal,
          'qty': 1,
          'harga_per_gram': 0,
          'manual_total': totalBiayaVal,
          'photo_produk': fotoUrl,
          'kategori': 'service',
          'jenis': _jenisBarang,
          'tipe': _jenisService,
          'material': _materialController.text.trim(),
          'purity': _kadarController.text.trim(),
        },
      ],
      // Extra fields (backend may ignore; kept for future use)
      'nota_lama': _notaLamaController.text.trim(),
      'reference_order_number': _notaLamaController.text.trim().isEmpty
          ? null
          : _notaLamaController.text.trim(),
      'kelengkapan': _kelengkapan,
      'keterangan': _keteranganServiceController.text.trim(),
      'estimasi_selesai': _estimasiSelesaiController.text.trim(),
      'customer_name': _customerController.text,
      'customer_phone': _customerPhoneController.text,
      'customer_address': _customerAddressController.text,
    };
    if (_pickupBranchId != null && _pickupBranchId != branchId) {
      orderData['pickup_branch_id'] = _pickupBranchId;
    }

    final fakturOverlay = <String, dynamic>{
      ...orderData,
      'customer_name': _customerController.text,
      'customer_phone': _customerPhoneController.text,
      'customer_address': _customerAddressController.text,
    };
    final itemsReq = orderData['order_items'];
    if (itemsReq is List && itemsReq.isNotEmpty && itemsReq.first is Map) {
      final first = Map<String, dynamic>.from(itemsReq.first as Map);
      final tipe = first['tipe']?.toString().trim();
      if (tipe != null && tipe.isNotEmpty) {
        fakturOverlay['jenis_service'] = tipe;
      }
    }
    if (uangMukaVal > 0) {
      fakturOverlay['service_dp_amount'] = uangMukaVal;
    }

    try {
      final result = await CsOrderSubmitService.submitJsonOrder(
        orderData: orderData,
        fakturOverlay: fakturOverlay,
      );

      if (!mounted) return;

      if (result.success && result.fakturData != null) {
        final data = Map<String, dynamic>.from(result.fakturData!);
        final createdOrderId = data['order_id'] ?? data['orderId'];

        if (result.offlineQueued) {
          CsOrderSubmitService.showOfflineQueuedSnackBar(
            context,
            offlineRef: result.offlineRef ?? '??????',
            dpNote: uangMukaVal > 0
                ? 'Uang muka akan dicatat setelah order tersinkron.'
                : null,
          );
        } else {
          if (uangMukaVal > 0 && createdOrderId != null) {
            try {
              await ApiClient.post(
                '/payments',
                body: jsonEncode({
                  'order_id': createdOrderId,
                  'amount': uangMukaVal,
                  'method': 'cash',
                  'status': 'pending',
                  'notes': 'Uang muka (service)',
                  'payment_kind': 'dp',
                }),
              );
            } catch (_) {}
          }
          ref.invalidate(todayOrdersProvider);
          ref.invalidate(orderTodayStatsProvider);
          bumpCsDailyOrdersListRevision(ref);
        }

        if (!mounted) return;
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => FakturPage(orderData: data),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result.errorMessage ?? 'Gagal menyimpan order'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Terjadi error: $e')),
        );
      }
    }
  }

  /// Mengisi form dari order jual [completed] berdasarkan nomor nota lama (untuk service).
  Future<void> _lookupNotaLamaForService(
    TextEditingController notaController,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final notaLama = notaController.text.trim();
    if (notaLama.isEmpty) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Masukkan nomor nota lama terlebih dahulu'),
        ),
      );
      return;
    }

    _notaLamaController.text = notaLama;

    try {
      final response = await ApiClient.get(
        '/orders',
        query: {'order_number': notaLama},
      );

      if (response.statusCode != 200) {
        messenger.showSnackBar(
          SnackBar(content: Text('Error: ${response.statusCode}')),
        );
        return;
      }

      final decoded = jsonDecode(response.body);
      if (decoded == null) {
        messenger.showSnackBar(
          const SnackBar(content: Text('Order tidak ditemukan')),
        );
        return;
      }
      if (decoded is! Map) {
        messenger.showSnackBar(
          const SnackBar(content: Text('Format order tidak valid')),
        );
        return;
      }
      final orderData = Map<String, dynamic>.from(decoded);

      if (orderData['order_type'] != 'jual' ||
          orderData['status'] != 'completed') {
        messenger.showSnackBar(
          const SnackBar(
            content: Text(
              'Nota harus dari order jual yang sudah selesai (completed)',
            ),
          ),
        );
        return;
      }

      String pickStr(dynamic a, dynamic b) {
        final s = a?.toString().trim() ?? '';
        if (s.isNotEmpty) return s;
        return b?.toString().trim() ?? '';
      }

      final custName = pickStr(orderData['customer_name'], orderData['name']);
      final custPhone = pickStr(
        orderData['customer_phone'],
        orderData['phone'],
      );
      final custAddr = pickStr(
        orderData['customer_address'],
        orderData['address'],
      );

      setState(() {
        _selectedCustomer = {
          'customer_id': orderData['customer_id'],
          'name': custName,
          'nama': custName,
          'phone': custPhone,
          'no_hp': custPhone,
          'address': custAddr,
          'alamat': custAddr,
        };
        _customerController.text = custName;
        _customerPhoneController.text = custPhone;
        _customerAddressController.text = custAddr;
        _customerAutocompleteController?.text = custName;
        _customerAutocompleteController?.selection = TextSelection.collapsed(
          offset: custName.length,
        );
      });

      final validItems = orderData['items'] as List<dynamic>? ?? [];
      if (validItems.isEmpty) {
        messenger.showSnackBar(
          const SnackBar(content: Text('Order tidak memiliki item yang valid')),
        );
        return;
      }

      if (validItems.length == 1) {
        _applyServiceItemFromOrder(
          Map<String, dynamic>.from(validItems.first as Map),
        );
      } else {
        final selected = await _showServiceItemPickDialog(validItems);
        if (selected != null) {
          _applyServiceItemFromOrder(selected);
        }
      }

      if (mounted) {
        messenger.showSnackBar(
          const SnackBar(content: Text('Data dari nota lama berhasil diisi')),
        );
      }
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Gagal mencari nota: $e')));
    }
  }

  void _applyServiceItemFromOrder(Map<String, dynamic> item) {
    final namaItem =
        item['nama_item'] ?? item['item_name'] ?? item['name'] ?? '';
    final berat = (item['weight'] ?? item['item_weight'] ?? 0).toString();
    final material =
        (item['material'] != null && item['material'].toString().isNotEmpty)
        ? item['material']
        : (item['item_material'] ?? '');
    final kadar =
        (item['purity'] != null && item['purity'].toString().isNotEmpty)
        ? item['purity']
        : (item['item_purity'] ?? '');

    setState(() {
      _namaItemController.text = namaItem.toString();
      _beratController.text = berat;
      _materialController.text = material.toString();
      _kadarController.text = kadar.toString();
    });
  }

  Future<Map<String, dynamic>?> _showServiceItemPickDialog(
    List<dynamic> items,
  ) async {
    return showDialog<Map<String, dynamic>>(
      context: context,
      builder: (dialogContext) {
        final cs = Theme.of(dialogContext).colorScheme;
        final dataRows = <DataRow>[];
        for (var i = 0; i < items.length; i++) {
          final item = items[i] as Map<String, dynamic>;
          final label =
              item['nama_item'] ?? item['item_name'] ?? item['name'] ?? '-';
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
                DataCell(Text(label.toString())),
                DataCell(Text('${item['kode_produk'] ?? '—'}')),
              ],
            ),
          );
        }
        return AlertDialog(
          title: const Text('Pilih item dari nota'),
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

    // Format: BRANCH_INITIAL + "S" + 8_DIGIT_NUMBER (S for Service)
    final orderNumber = '$branchInitial${'S'}$uniqueNumber';

    setState(() {
      _notaOrderController.text = orderNumber;
    });
  }

  @override
  void initState() {
    super.initState();
    // Set default estimasi selesai to today + 4 days
    final DateTime defaultDate = DateTime.now().add(const Duration(days: 4));
    _estimasiSelesaiController.text =
        '${defaultDate.day.toString().padLeft(2, '0')}/${defaultDate.month.toString().padLeft(2, '0')}/${(defaultDate.year % 100).toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final customerList = ref.watch(customersProvider);
    final userState = ref.watch(userStateProvider);

    // Listen to user state changes to regenerate order number when branch changes
    ref.listen(userStateProvider, (previous, next) {
      final branchChanged = previous == null || previous.branch != next.branch;
      if (branchChanged && mounted) {
        setState(() => _pickupBranchId = null);
      }
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
      appBar: AppBar(title: const Text('Form Order Service')),
      body: ResponsiveLayout.scrollableForm(
        context: context,
        formKey: _formKey,
        children: [
              // 1. Mode (TOKO/ONLINE)
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Container(
                    width: 120,
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
              PickupBranchField(
                orderBranchId: userState.branch,
                branches: userState.branches,
                value: _pickupBranchId,
                onChanged: (v) => setState(() => _pickupBranchId = v),
              ),
              const SizedBox(height: 12.0),
              // Order Number
              Row(
                children: [
                  const SizedBox(
                    width: 120,
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
                      decoration: const InputDecoration(
                        hintText: 'Order Number',
                        filled: true,
                        fillColor: Colors.grey,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12.0),
              // Bagian 1: Customer
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
                                  : Autocomplete<Map<String, dynamic>>(
                                      initialValue: _selectedCustomer != null
                                          ? TextEditingValue(
                                              text:
                                                  _selectedCustomer!['name'] ??
                                                  _selectedCustomer!['nama'] ??
                                                  '',
                                            )
                                          : null,
                                      optionsBuilder:
                                          (TextEditingValue textEditingValue) {
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
                                                  return name.contains(input);
                                                })
                                                .toList();
                                            return suggestions; // Return new list each time
                                          },
                                      displayStringForOption: (option) =>
                                          option['name'] ??
                                          option['nama'] ??
                                          '',
                                      onSelected: (customer) {
                                        setState(() {
                                          _customerPhoneController.text =
                                              customer['phone'] ??
                                              customer['no_hp'] ??
                                              '';
                                          _customerAddressController.text =
                                              customer['address'] ??
                                              customer['alamat'] ??
                                              '';
                                          _selectedCustomer = customer;
                                          final dn =
                                              customer['name'] ??
                                              customer['nama'] ??
                                              '';
                                          final nameStr = dn.toString();
                                          _customerController.text = nameStr;
                                          _customerAutocompleteController
                                                  ?.text =
                                              nameStr;
                                        });
                                      },
                                      fieldViewBuilder:
                                          (
                                            context,
                                            controller,
                                            focusNode,
                                            onFieldSubmitted,
                                          ) {
                                            _customerAutocompleteController =
                                                controller;
                                            return Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Row(
                                                  children: [
                                                    Expanded(
                                                      child: TextFormField(
                                                        controller: controller,
                                                        focusNode: focusNode,
                                                        decoration: const InputDecoration(
                                                          border:
                                                              OutlineInputBorder(),
                                                          contentPadding:
                                                              EdgeInsets.symmetric(
                                                                vertical: 12,
                                                                horizontal: 12,
                                                              ),
                                                        ),
                                                        onChanged: (_) {
                                                          _customerController
                                                                  .text =
                                                              controller.text;
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
                                                        final input = controller
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
                                                                  input
                                                                      .isNotEmpty;
                                                            });
                                                        if (!exists &&
                                                            input.isNotEmpty) {
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
                                                          return IconButton(
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
                                    ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12.0),
              // Nota Lama
              Row(
                children: [
                  const SizedBox(
                    width: 120,
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text('Nota Lama'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: StatefulBuilder(
                      builder: (context, setFieldState) {
                        return Autocomplete<String>(
                          optionsBuilder: (textEditingValue) {
                            // Untuk sementara, return empty list
                            // Nanti bisa diisi dengan order numbers dari API
                            return const Iterable<String>.empty();
                          },
                          onSelected: (String selection) {
                            _notaLamaController.text = selection;
                          },
                          fieldViewBuilder:
                              (
                                context,
                                controller,
                                focusNode,
                                onFieldSubmitted,
                              ) {
                                return Row(
                                  children: [
                                    Expanded(
                                      child: TextFormField(
                                        controller: controller,
                                        focusNode: focusNode,
                                        decoration: const InputDecoration(
                                          border: OutlineInputBorder(),
                                          hintText:
                                              'Masukkan nomor nota lama...',
                                          contentPadding: EdgeInsets.symmetric(
                                            vertical: 12,
                                            horizontal: 12,
                                          ),
                                        ),
                                        onChanged: (_) => setState(() {}),
                                        onFieldSubmitted: (value) =>
                                            onFieldSubmitted(),
                                      ),
                                    ),
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        IconButton(
                                          icon: const Icon(Icons.search),
                                          onPressed: () =>
                                              _lookupNotaLamaForService(
                                                controller,
                                              ),
                                          tooltip: 'Cari berdasarkan nota lama',
                                        ),
                                        IconButton(
                                          icon: const Icon(
                                            Icons.qr_code_scanner,
                                          ),
                                          onPressed: () =>
                                              _scanAndLookupNotaLama(
                                                controller,
                                              ),
                                          tooltip: 'Scan QR nota lama',
                                        ),
                                      ],
                                    ),
                                  ],
                                );
                              },
                        );
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12.0),
              Row(
                children: [
                  const SizedBox(
                    width: 120,
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text('Jenis'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Wrap(
                      spacing: 8.0,
                      runSpacing: 8.0,
                      children: [
                        ChoiceChip(
                          label: const Text('KALUNG'),
                          selected: _jenisBarang == 'KALUNG',
                          onSelected: (selected) {
                            setState(() {
                              _jenisBarang = 'KALUNG';
                            });
                          },
                        ),
                        ChoiceChip(
                          label: const Text('GELANG'),
                          selected: _jenisBarang == 'GELANG',
                          onSelected: (selected) {
                            setState(() {
                              _jenisBarang = 'GELANG';
                            });
                          },
                        ),
                        ChoiceChip(
                          label: const Text('ANTING'),
                          selected: _jenisBarang == 'ANTING',
                          onSelected: (selected) {
                            setState(() {
                              _jenisBarang = 'ANTING';
                            });
                          },
                        ),
                        ChoiceChip(
                          label: const Text('CINCIN'),
                          selected: _jenisBarang == 'CINCIN',
                          onSelected: (selected) {
                            setState(() {
                              _jenisBarang = 'CINCIN';
                            });
                          },
                        ),
                        ChoiceChip(
                          label: const Text('LIONTIN'),
                          selected: _jenisBarang == 'LIONTIN',
                          onSelected: (selected) {
                            setState(() {
                              _jenisBarang = 'LIONTIN';
                            });
                          },
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // Bagian 3: Detail Item
              Row(
                children: [
                  const SizedBox(
                    width: 120,
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text('Nama Barang'),
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
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Nama barang wajib diisi';
                        }
                        return null;
                      },
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
                      child: Text('Berat (gram)'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextFormField(
                      controller: _beratController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
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
                      child: Text('Material'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextFormField(
                      controller: _materialController,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        hintText: 'Contoh: Emas, Perak, Tembaga',
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
                      child: Text('Kadar Kemurnian'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextFormField(
                      controller: _kadarController,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        hintText: 'Contoh: 70%, 22K',
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
                      child: Text('Estimasi Biaya'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextFormField(
                      controller: _totalBiayaController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        prefixText: 'Rp ',
                        hintText: 'Contoh: 150000',
                      ),
                      validator: (value) {
                        final raw = (value ?? '').trim();
                        if (raw.isEmpty) return 'Estimasi biaya wajib diisi';
                        final v = _parseMoney(raw);
                        if (v < 0) return 'Estimasi biaya tidak valid';
                        return null;
                      },
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
                      child: Text('Uang Muka'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextFormField(
                      controller: _uangMukaController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        prefixText: 'Rp ',
                        hintText: 'Opsional (boleh 0)',
                      ),
                      validator: (value) {
                        final dp = _parseMoney(value ?? '');
                        final total = _parseMoney(_totalBiayaController.text);
                        if (dp < 0) return 'Uang muka tidak valid';
                        if (dp > total) return 'Uang muka melebihi total biaya';
                        return null;
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              const Text(
                'KETERANGAN',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  const SizedBox(
                    width: 120,
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text('Jenis Service'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Wrap(
                      spacing: 8.0,
                      runSpacing: 8.0,
                      children: [
                        ChoiceChip(
                          label: const Text('Patri'),
                          selected: _jenisService == 'Patri',
                          onSelected: (selected) {
                            setState(() {
                              _jenisService = 'Patri';
                            });
                          },
                        ),
                        ChoiceChip(
                          label: const Text('Cuci'),
                          selected: _jenisService == 'Cuci',
                          onSelected: (selected) {
                            setState(() {
                              _jenisService = 'Cuci';
                            });
                          },
                        ),
                        ChoiceChip(
                          label: const Text('Sambung'),
                          selected: _jenisService == 'Sambung',
                          onSelected: (selected) {
                            setState(() {
                              _jenisService = 'Sambung';
                            });
                          },
                        ),
                        ChoiceChip(
                          label: const Text('Ubah Ukuran'),
                          selected: _jenisService == 'Ubah Ukuran',
                          onSelected: (selected) {
                            setState(() {
                              _jenisService = 'Ubah Ukuran';
                            });
                          },
                        ),
                        ChoiceChip(
                          label: const Text('Ganti Batu'),
                          selected: _jenisService == 'Ganti Batu',
                          onSelected: (selected) {
                            setState(() {
                              _jenisService = 'Ganti Batu';
                            });
                          },
                        ),
                        ChoiceChip(
                          label: const Text('Lainnya'),
                          selected: _jenisService == 'Lainnya',
                          onSelected: (selected) {
                            setState(() {
                              _jenisService = 'Lainnya';
                            });
                          },
                        ),
                      ],
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
                      child: Text('Kelengkapan'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        CheckboxListTile(
                          title: const Text('Barang'),
                          value: _kelengkapan['Barang'] ?? false,
                          onChanged: (bool? value) {
                            setState(() {
                              _kelengkapan['Barang'] = value ?? false;
                            });
                          },
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                        ),
                        CheckboxListTile(
                          title: const Text('Surat'),
                          value: _kelengkapan['Surat'] ?? false,
                          onChanged: (bool? value) {
                            setState(() {
                              _kelengkapan['Surat'] = value ?? false;
                            });
                          },
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                        ),
                        CheckboxListTile(
                          title: const Text('Identitas'),
                          value: _kelengkapan['Identitas'] ?? false,
                          onChanged: (bool? value) {
                            setState(() {
                              _kelengkapan['Identitas'] = value ?? false;
                            });
                          },
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // Bagian 4: Catatan service (opsional)
              const Text(
                'Catatan (opsional)',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _keteranganServiceController,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Keluhan / Keterangan Perbaikan',
                  border: OutlineInputBorder(),
                  hintText:
                      'Contoh: Rusak, Bengkok, Gemuk, dll (boleh dikosongkan)',
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  const SizedBox(
                    width: 120,
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text('Estimasi Selesai'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextFormField(
                      controller: _estimasiSelesaiController,
                      readOnly: true,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        hintText: 'Tanggal estimasi selesai',
                      ),
                      onTap: () async {
                        final DateTime? picked = await showAppDatePicker(
                          context: context,
                          initialDate: DateTime.now().add(
                            const Duration(days: 4),
                          ),
                          firstDate: DateTime.now(),
                          lastDate: DateTime.now().add(
                            const Duration(days: 365),
                          ),
                        );
                        if (picked != null) {
                          setState(() {
                            _estimasiSelesaiController.text =
                                '${picked.day.toString().padLeft(2, '0')}/${picked.month.toString().padLeft(2, '0')}/${(picked.year % 100).toString().padLeft(2, '0')}';
                          });
                        }
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              CsOrderPhotoField(
                hasPhoto: _fotoXFile != null || _fotoBytes != null,
                imageBytes: _fotoBytes,
                imageFile:
                    _fotoXFile != null ? File(_fotoXFile!.path) : null,
                onCamera: _pickFoto,
                onGallery: _pickFotoFromGallery,
                requiredMessage: (_fotoXFile == null && _fotoBytes == null)
                    ? 'Foto barang WAJIB untuk service'
                    : null,
              ),
              const SizedBox(height: 24),

              // Tombol Submit
              ElevatedButton(
                onPressed: _submitOrder,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  backgroundColor: Colors.green,
                ),
                child: const Text(
                  'SUBMIT SERVICE',
                  style: TextStyle(fontSize: 16, color: Colors.white),
                ),
              ),
              const SizedBox(height: 12),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _customerController.dispose();
    _customerPhoneController.dispose();
    _customerAddressController.dispose();
    _notaOrderController.dispose();
    _notaLamaController.dispose();
    _namaItemController.dispose();
    _beratController.dispose();
    _materialController.dispose();
    _kadarController.dispose();
    _keteranganServiceController.dispose();
    _estimasiSelesaiController.dispose();
    _totalBiayaController.dispose();
    _uangMukaController.dispose();
    super.dispose();
  }
}

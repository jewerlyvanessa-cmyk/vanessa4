import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:vanessa3/core/network/api_client.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:io';
import 'package:vanessa3/providers/customers_provider.dart';
import 'faktur_page.dart';

import 'package:image_picker/image_picker.dart'
    if (dart.library.html) '../../../utils/image_picker_stub.dart';
import 'package:vanessa3/widgets/qr_scan_route.dart';
import 'package:vanessa3/providers/user_state_provider.dart';
import 'package:vanessa3/providers/order_today_provider.dart';
import 'package:vanessa3/providers/cs_daily_orders_refresh_provider.dart';
import 'package:vanessa3/utils/cs_order_photo_picker.dart';
import 'package:vanessa3/utils/cs_order_photo_upload.dart';
import 'package:vanessa3/utils/responsive_layout.dart';
import 'package:vanessa3/services/cs_order_submit_service.dart';
import 'package:vanessa3/modules/cs/logic/cs_form_utils.dart';
import 'package:vanessa3/modules/cs/logic/cs_order_item_selection_dialog.dart';
import 'package:vanessa3/modules/cs/logic/jual_add_customer.dart';
import 'package:vanessa3/modules/cs/logic/service_item_form.dart';
import 'package:vanessa3/modules/cs/logic/service_order_lookup.dart';
import 'package:vanessa3/modules/cs/logic/service_order_payload.dart';
import 'package:vanessa3/modules/cs/widgets/service_customer_field.dart';
import 'package:vanessa3/modules/cs/widgets/service_detail_section.dart';
import 'package:vanessa3/modules/cs/widgets/service_header_section.dart';
import 'package:vanessa3/modules/cs/widgets/service_item_pricing_section.dart';
import 'package:vanessa3/modules/cs/widgets/service_nota_lookup_field.dart';

class ServicePage extends ConsumerStatefulWidget {
  const ServicePage({super.key});

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

  double _parseMoney(String raw) => csParseMoney(raw);

  int? _resolveCustomerIdForSubmit() {
    final fromMap = csToInt(_selectedCustomer?['customer_id']);
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
        final id = csToInt(c['customer_id']);
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

  Future<void> _addCustomer(String initialName) async {
    final customer = await JualAddCustomer.showDialogAndCreate(
      context: context,
      ref: ref,
      initialName: initialName,
      syncController: _customerAutocompleteController ?? _customerController,
    );
    if (customer != null && mounted) {
      setState(() {
        _selectedCustomer = customer;
        _customerPhoneController.text =
            customer['phone'] ?? customer['no_hp'] ?? '';
        _customerAddressController.text =
            customer['address'] ?? customer['alamat'] ?? '';
        final nameStr =
            customer['name']?.toString() ?? customer['nama']?.toString() ?? '';
        _customerController.text = nameStr;
        _customerAutocompleteController?.text = nameStr;
      });
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
    final generatedKodeProduk = _notaOrderController.text.trim().isNotEmpty
        ? _notaOrderController.text.trim()
        : 'SERV-${DateTime.now().millisecondsSinceEpoch}';

    final orderData = ServiceOrderPayloadBuilder.build(
      ServiceOrderFormInput(
        modeToko: _modeToko,
        orderNumber: _notaOrderController.text,
        branchId: branchId,
        userId: userId,
        customerId: customerId,
        namaItem: _namaItemController.text.trim(),
        generatedKodeProduk: generatedKodeProduk,
        weightVal: weightVal,
        totalBiayaVal: totalBiayaVal,
        uangMukaVal: uangMukaVal,
        fotoUrl: fotoUrl,
        jenisBarang: _jenisBarang,
        jenisService: _jenisService,
        material: _materialController.text.trim(),
        kadar: _kadarController.text.trim(),
        notaLama: _notaLamaController.text.trim(),
        kelengkapan: _kelengkapan,
        keterangan: _keteranganServiceController.text.trim(),
        estimasiSelesai: _estimasiSelesaiController.text.trim(),
        customerName: _customerController.text,
        customerPhone: _customerPhoneController.text,
        customerAddress: _customerAddressController.text,
        pickupBranchId: _pickupBranchId,
      ),
    );

    final fakturOverlay = ServiceOrderPayloadBuilder.buildFakturOverlay(
      orderData: orderData,
      uangMukaVal: uangMukaVal,
    );

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
      final orderData = await ServiceOrderLookup.fetchOrder(notaLama);

      if (orderData == null || orderData.isEmpty) {
        messenger.showSnackBar(
          const SnackBar(content: Text('Order tidak ditemukan')),
        );
        return;
      }

      if (!ServiceOrderLookup.isEligible(orderData)) {
        messenger.showSnackBar(
          const SnackBar(
            content: Text(
              'Nota harus dari order jual yang sudah selesai (completed)',
            ),
          ),
        );
        return;
      }

      final customer = ServiceOrderLookup.customerFromOrder(orderData);
      final custName = customer['name']?.toString() ?? '';

      setState(() {
        _selectedCustomer = customer;
        _customerController.text = custName;
        _customerPhoneController.text = customer['phone']?.toString() ?? '';
        _customerAddressController.text = customer['address']?.toString() ?? '';
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
        if (!mounted) return;
        final selected = await CsOrderItemSelectionDialog.show(
          context,
          validItems,
          title: 'Pilih item dari nota',
        );
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
    final snapshot = ServiceItemFormSnapshot.fromOrderItem(item);
    setState(() {
      _namaItemController.text = snapshot.namaItem;
      _beratController.text = snapshot.berat;
      _materialController.text = snapshot.material;
      _kadarController.text = snapshot.kadar;
    });
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
              ServiceHeaderSection(
                modeToko: _modeToko,
                notaOrderController: _notaOrderController,
                orderBranchId: userState.branch,
                branches: userState.branches,
                pickupBranchId: _pickupBranchId,
                onModeChanged: (mode) => setState(() => _modeToko = mode),
                onPickupBranchChanged: (v) => setState(() => _pickupBranchId = v),
              ),
              ServiceCustomerField(
                customerController: _customerController,
                selectedCustomer: _selectedCustomer,
                onCustomerSelected: (customer) {
                  setState(() {
                    _customerPhoneController.text =
                        customer['phone'] ?? customer['no_hp'] ?? '';
                    _customerAddressController.text =
                        customer['address'] ?? customer['alamat'] ?? '';
                    _selectedCustomer = customer;
                    final nameStr = (customer['name'] ?? customer['nama'] ?? '')
                        .toString();
                    _customerController.text = nameStr;
                    _customerAutocompleteController?.text = nameStr;
                  });
                },
                onFieldChanged: () => setState(() {}),
                onAutocompleteControllerReady: (controller) {
                  _customerAutocompleteController = controller;
                },
                onAddCustomer: _addCustomer,
                onScanQr: _scanAndFill,
              ),
              const SizedBox(height: 12),
              ServiceNotaLookupField(
                notaLamaController: _notaLamaController,
                onLookup: _lookupNotaLamaForService,
                onScanAndLookup: _scanAndLookupNotaLama,
                onChanged: () => setState(() {}),
              ),
              const SizedBox(height: 12),
              ServiceItemPricingSection(
                jenisBarang: _jenisBarang,
                onJenisBarangChanged: (jenis) =>
                    setState(() => _jenisBarang = jenis),
                namaItemController: _namaItemController,
                beratController: _beratController,
                materialController: _materialController,
                kadarController: _kadarController,
                totalBiayaController: _totalBiayaController,
                uangMukaController: _uangMukaController,
              ),
              ServiceDetailSection(
                jenisService: _jenisService,
                onJenisServiceChanged: (jenis) =>
                    setState(() => _jenisService = jenis),
                kelengkapan: _kelengkapan,
                onKelengkapanChanged: (key, value) {
                  setState(() => _kelengkapan[key] = value);
                },
                keteranganController: _keteranganServiceController,
                estimasiSelesaiController: _estimasiSelesaiController,
                onEstimasiSelesaiChanged: (formatted) {
                  setState(() => _estimasiSelesaiController.text = formatted);
                },
                fotoXFile: _fotoXFile,
                fotoBytes: _fotoBytes,
                onPickFotoCamera: _pickFoto,
                onPickFotoGallery: _pickFotoFromGallery,
              ),

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

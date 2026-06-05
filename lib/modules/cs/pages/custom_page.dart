import 'package:flutter/material.dart';
import 'dart:convert';
import 'dart:typed_data';
import 'package:vanessa3/core/network/api_client.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:io';
import 'package:vanessa3/modules/cs/logic/cs_form_utils.dart';
import 'package:vanessa3/modules/cs/logic/custom_order_number.dart';
import 'package:vanessa3/modules/cs/logic/custom_order_payload.dart';
import 'package:vanessa3/modules/cs/logic/jual_add_customer.dart';
import 'package:vanessa3/modules/cs/widgets/custom_customer_field.dart';
import 'package:vanessa3/modules/cs/widgets/custom_header_section.dart';
import 'package:vanessa3/modules/cs/widgets/custom_spec_section.dart';
import 'package:vanessa3/providers/customers_provider.dart';
import 'faktur_page.dart';
import 'package:vanessa3/providers/user_state_provider.dart';
import 'package:vanessa3/providers/order_today_provider.dart';
import 'package:vanessa3/providers/cs_daily_orders_refresh_provider.dart';
import 'package:vanessa3/shared_widgets/cs_order_photo_field.dart';
import 'package:vanessa3/utils/cs_order_photo_picker.dart';
import 'package:vanessa3/utils/cs_order_photo_upload.dart';
import 'package:vanessa3/utils/responsive_layout.dart';
import 'package:vanessa3/widgets/qr_scan_route.dart';
import 'package:vanessa3/services/cs_order_submit_service.dart';

class CustomPage extends ConsumerStatefulWidget {
  const CustomPage({super.key});

  @override
  ConsumerState<CustomPage> createState() => _CustomPageState();
}

class _CustomPageState extends ConsumerState<CustomPage> {
  final _formKey = GlobalKey<FormState>();

  final TextEditingController _customerController = TextEditingController();
  final TextEditingController _customerPhoneController =
      TextEditingController();
  final TextEditingController _customerAddressController =
      TextEditingController();
  final TextEditingController _notaOrderController = TextEditingController();
  final TextEditingController _namaItemController = TextEditingController();
  final TextEditingController _spesifikasiController = TextEditingController();
  final TextEditingController _beratTargetController = TextEditingController();
  final TextEditingController _materialController = TextEditingController();
  final TextEditingController _materialTambahanController =
      TextEditingController();
  final TextEditingController _kadarController = TextEditingController();
  final TextEditingController _estimasiWaktuController =
      TextEditingController();
  final TextEditingController _totalBiayaController = TextEditingController();
  final TextEditingController _uangMukaController = TextEditingController();

  Map<String, dynamic>? _selectedCustomer;
  File? _fotoFile;
  Uint8List? _fotoBytes;
  String? _fotoName;
  String _modeToko = 'TOKO';
  String _jenisBarang = 'KALUNG';
  String _asalMaterial = 'TOKO';
  String _asalTambahan = 'TOKO';
  int? _pickupBranchId;

  bool get _hasFoto =>
      (_fotoBytes != null && _fotoBytes!.isNotEmpty) || _fotoFile != null;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(customersProvider.notifier).fetchCustomers();
    });
  }

  Future<String?> _uploadFoto() async {
    if (!_hasFoto) return null;
    return CsOrderPhotoUpload.upload(
      file: _fotoFile,
      bytes: _fotoBytes,
      fileName: _fotoName,
    );
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

  Future<void> _scanAndFill(TextEditingController controller) async {
    final v = await pushQrScanPage(context);
    if (!mounted || v == null) return;
    controller.text = v;
  }

  Future<void> _addCustomer(
    String initialName,
    TextEditingController controller,
  ) async {
    final customer = await JualAddCustomer.showDialogAndCreate(
      context: context,
      ref: ref,
      initialName: initialName,
      syncController: controller,
    );
    if (customer == null || !mounted) return;
    setState(() {
      _selectedCustomer = customer;
      _customerController.text =
          customer['name']?.toString() ?? customer['nama']?.toString() ?? '';
      _customerPhoneController.text =
          customer['phone']?.toString() ?? customer['no_hp']?.toString() ?? '';
      _customerAddressController.text =
          customer['address']?.toString() ??
          customer['alamat']?.toString() ??
          '';
    });
  }

  void _onCustomerSelected(Map<String, dynamic> customer) {
    setState(() {
      _selectedCustomer = customer;
      _customerPhoneController.text =
          customer['phone']?.toString() ?? customer['no_hp']?.toString() ?? '';
      _customerAddressController.text =
          customer['address']?.toString() ??
          customer['alamat']?.toString() ??
          '';
      _customerController.text =
          customer['name']?.toString() ?? customer['nama']?.toString() ?? '';
    });
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

    if (!_hasFoto) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Foto desain/referensi WAJIB untuk custom!'),
          ),
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

    final userState = ref.read(userStateProvider);
    final branchId = csToInt(userState.branch);
    final userId = csToInt(userState.userId);
    final customerId = csToInt(
      _selectedCustomer?['customer_id'] ?? _selectedCustomer?['id'],
    );

    if (userId == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('User belum login. Silakan login ulang.'),
          ),
        );
      }
      return;
    }
    if (branchId == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Cabang user tidak valid. Silakan login ulang.'),
          ),
        );
      }
      return;
    }
    if (customerId == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Customer belum valid. Pilih ulang customer dari daftar.',
            ),
          ),
        );
      }
      return;
    }

    String? fotoUrl;
    if (_hasFoto) {
      fotoUrl = await _uploadFoto();
    }
    if (_hasFoto && (fotoUrl == null || fotoUrl.trim().isEmpty)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Upload foto gagal. Coba ambil foto ulang (JPEG/PNG).',
            ),
          ),
        );
      }
      return;
    }

    final weightVal =
        double.tryParse(_beratTargetController.text.trim()) ?? 0;
    final totalBiayaVal = csParseMoney(_totalBiayaController.text);
    final uangMukaVal = csParseMoney(_uangMukaController.text);
    final orderNumber = _notaOrderController.text.trim();
    final generatedKodeProduk = orderNumber.isNotEmpty
        ? orderNumber
        : 'CUST-${DateTime.now().millisecondsSinceEpoch}';

    final input = CustomOrderFormInput(
      modeToko: _modeToko,
      orderNumber: orderNumber,
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
      material: _materialController.text.trim(),
      kadar: _kadarController.text.trim(),
      spesifikasi: _spesifikasiController.text.trim(),
      asalMaterial: _asalMaterial,
      materialTambahan: _materialTambahanController.text.trim(),
      asalTambahan: _asalTambahan,
      estimasiWaktu: _estimasiWaktuController.text.trim(),
      customerName: _customerController.text,
      customerPhone: _customerPhoneController.text,
      customerAddress: _customerAddressController.text,
      pickupBranchId: _pickupBranchId,
    );

    final orderData = CustomOrderPayloadBuilder.build(input);
    final fakturOverlay = CustomOrderPayloadBuilder.buildFakturOverlay(
      orderData: orderData,
      customerName: _customerController.text,
      customerPhone: _customerPhoneController.text,
      customerAddress: _customerAddressController.text,
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
                  'notes': 'Uang muka (custom)',
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

  void _generateOrderNumber() {
    final userState = ref.read(userStateProvider);
    setState(() {
      _notaOrderController.text = generateCustomOrderNumber(userState);
    });
  }

  @override
  Widget build(BuildContext context) {
    final userState = ref.watch(userStateProvider);

    ref.listen(userStateProvider, (previous, next) {
      final branchChanged = previous == null || previous.branch != next.branch;
      if (branchChanged && mounted) {
        setState(() => _pickupBranchId = null);
      }
      if (next.branch.isNotEmpty && next.branches.isNotEmpty) {
        _generateOrderNumber();
      }
    });

    if (userState.branch.isNotEmpty &&
        userState.branches.isNotEmpty &&
        _notaOrderController.text.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _generateOrderNumber();
      });
    }

    return Scaffold(
      resizeToAvoidBottomInset: true,
      appBar: AppBar(title: const Text('Form Order Custom')),
      body: ResponsiveLayout.scrollableForm(
        context: context,
        formKey: _formKey,
        children: [
          CustomHeaderSection(
            modeToko: _modeToko,
            onModeChanged: (v) => setState(() => _modeToko = v),
            orderBranchId: userState.branch,
            branches: userState.branches,
            pickupBranchId: _pickupBranchId,
            onPickupChanged: (v) => setState(() => _pickupBranchId = v),
            notaOrderController: _notaOrderController,
          ),
          const SizedBox(height: 12),
          CustomCustomerField(
            selectedCustomer: _selectedCustomer,
            onCustomerSelected: _onCustomerSelected,
            onFieldChanged: () => setState(() {}),
            onAddCustomer: _addCustomer,
            onScanQr: _scanAndFill,
          ),
          const SizedBox(height: 24),
          CustomSpecSection(
            jenisBarang: _jenisBarang,
            onJenisChanged: (v) => setState(() => _jenisBarang = v),
            asalMaterial: _asalMaterial,
            onAsalMaterialChanged: (v) => setState(() => _asalMaterial = v),
            asalTambahan: _asalTambahan,
            onAsalTambahanChanged: (v) => setState(() => _asalTambahan = v),
            totalBiayaController: _totalBiayaController,
            uangMukaController: _uangMukaController,
            namaItemController: _namaItemController,
            spesifikasiController: _spesifikasiController,
            materialController: _materialController,
            materialTambahanController: _materialTambahanController,
            kadarController: _kadarController,
            beratTargetController: _beratTargetController,
            estimasiWaktuController: _estimasiWaktuController,
          ),
          const SizedBox(height: 24),
          CsOrderPhotoField(
            hasPhoto: _hasFoto,
            imageBytes: _fotoBytes,
            imageFile: _fotoFile,
            onCamera: _pickFoto,
            onGallery: _pickFotoFromGallery,
            requiredMessage:
                !_hasFoto ? 'Foto desain/referensi WAJIB' : null,
          ),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: _submitOrder,
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 12),
              backgroundColor: Colors.green,
            ),
            child: const Text(
              'SUBMIT CUSTOM',
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
    _namaItemController.dispose();
    _spesifikasiController.dispose();
    _beratTargetController.dispose();
    _materialController.dispose();
    _materialTambahanController.dispose();
    _kadarController.dispose();
    _estimasiWaktuController.dispose();
    _totalBiayaController.dispose();
    _uangMukaController.dispose();
    super.dispose();
  }
}

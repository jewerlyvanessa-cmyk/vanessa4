import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:io';
import 'dart:async';
import '../../../utils/logger.dart';
import '../../../utils/pembulatan.dart';
import 'package:vanessa3/providers/customers_provider.dart';
import '../../../providers/order_today_provider.dart';
import 'package:vanessa3/services/cs_order_submit_service.dart';
import 'package:vanessa3/utils/cs_order_photo_upload.dart';
import 'package:vanessa3/providers/cs_daily_orders_refresh_provider.dart';
import 'faktur_page.dart';
import 'package:vanessa3/providers/user_state_provider.dart';
import 'package:vanessa3/modules/cs/logic/buyback_item_form.dart';
import 'package:vanessa3/modules/cs/logic/cs_order_item_selection_dialog.dart';
import 'package:vanessa3/modules/cs/logic/buyback_order_lookup.dart';
import 'package:vanessa3/modules/cs/logic/buyback_order_payload.dart';
import 'package:vanessa3/modules/cs/logic/jual_add_customer.dart';
import 'package:vanessa3/modules/cs/widgets/buyback_customer_field.dart';
import 'package:vanessa3/modules/cs/widgets/buyback_header_section.dart';
import 'package:vanessa3/modules/cs/widgets/buyback_item_details_section.dart';
import 'package:vanessa3/modules/cs/widgets/buyback_nota_lookup_section.dart';
import 'package:vanessa3/modules/cs/widgets/buyback_price_condition_section.dart';

import 'package:cross_file/cross_file.dart';
import 'package:vanessa3/widgets/qr_scan_route.dart';
import 'package:vanessa3/utils/cs_order_photo_picker.dart';
import 'package:vanessa3/utils/responsive_layout.dart';

class BuybackPage extends ConsumerStatefulWidget {
  const BuybackPage({super.key});

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
      final orderData =
          await BuybackOrderLookup.fetchByNotaOrOrderId(notaLama);

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

      if (!BuybackOrderLookup.isEligibleForBuyback(resolved)) {
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
    final selectedItem = await CsOrderItemSelectionDialog.show(context, items);
    if (selectedItem != null) {
      await _selectItem(selectedItem);
    }
  }

  Future<void> _selectItem(Map<String, dynamic> item) async {
    Logger.logInfo('Selecting item: $item');

    final snapshot = BuybackItemFormSnapshot.fromOrderItem(
      item,
      nomorNota: _nomorNotaController.text,
    );

    setState(() {
      _selectedItem = snapshot.selectedItem;
      _notaJual = snapshot.notaJual;
      _isDataFromOrderItems = true;
      _isManualEntry = false;
      _namaItemController.text = snapshot.namaItem;
      _beratController.text = snapshot.berat;
      _materialController.text = snapshot.material;
      _kadarController.text = snapshot.kadar;
      _kategoriController.text = snapshot.kategori;
      _jenisController.text = snapshot.jenis;
      _tipeController.text = snapshot.tipe;
      _selectedTipeBarang = snapshot.selectedTipeBarang;
      _quantityController.text = snapshot.quantity;
      _hargaBeliController.text = snapshot.hargaBeli;
      _hargaPerGramController.text = snapshot.hargaPerGram;
      _kodeProdukController.text = snapshot.kodeProduk;
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Item "${snapshot.namaItem}" berhasil dipilih dan field terisi otomatis',
          ),
        ),
      );
    }
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
    if (customer != null && mounted) {
      setState(() {
        _selectedCustomer = customer;
        _customerPhoneController.text =
            customer['phone'] ?? customer['no_hp'] ?? '';
        _customerAddressController.text =
            customer['address'] ?? customer['alamat'] ?? '';
        _isCustomerLockedFromLookup = false;
      });
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
      final userState = ref.read(userStateProvider);

      String? fotoUrl;
      if (kIsWeb) {
        fotoUrl = await CsOrderPhotoUpload.upload(
          bytes: _fotoBytes ?? await _fotoXFile?.readAsBytes(),
          fileName: _fotoName ?? _fotoXFile?.name,
        );
      } else if (_fotoXFile != null) {
        fotoUrl = await CsOrderPhotoUpload.upload(file: File(_fotoXFile!.path));
      } else if (_fotoBytes != null) {
        fotoUrl = await CsOrderPhotoUpload.upload(
          bytes: _fotoBytes,
          fileName: _fotoName,
        );
      }

      if (fotoUrl == null || fotoUrl.trim().isEmpty) {
        scaffoldMessenger.showSnackBar(
          const SnackBar(
            content: Text(
              'Upload foto gagal. Buyback memerlukan koneksi untuk upload foto barang.',
            ),
          ),
        );
        return;
      }

      final qty = int.tryParse(_quantityController.text.trim()) ?? 1;
      final hargaBeli = double.tryParse(_hargaBeliController.text.trim()) ?? 0;

      final orderData = BuybackOrderPayloadBuilder.build(
        BuybackOrderFormInput(
          orderNumber: _notaOrderController.text,
          notaLama: _notaLamaController.text.trim(),
          nomorNota: _nomorNotaController.text.trim(),
          customerId: _selectedCustomer!['customer_id'],
          branchId: int.parse(
            userState.branch.isNotEmpty ? userState.branch : '1',
          ),
          userId: userState.userId ?? 1,
          selectedItemId: _selectedItem?['item_id'],
          namaItem: _namaItemController.text.trim(),
          berat: _beratController.text.trim(),
          material: _materialController.text.trim(),
          kadar: _kadarController.text.trim(),
          hargaPerGram: _hargaPerGramController.text.trim(),
          kategori: _kategoriController.text.trim(),
          jenis: _jenisController.text.trim(),
          notaJual: _notaJual,
          selectedTipeBarang: _selectedTipeBarang,
          tipe: _tipeController.text.trim(),
          kodeProduk: _kodeProdukController.text.trim(),
          qty: qty,
          hargaBeli: hargaBeli,
          fotoUrl: fotoUrl,
          kondisiFisik: _kondisiFisik,
          penyesuaianBerat: _penyesuaianBeratController.text.trim(),
          nilaiUntungRugi: _nilaiUntungRugiController.text.trim(),
          notaJualStatus: _notaJual,
          potonganKondisi: _potonganKondisiController.text.trim(),
          nilaiResale: _nilaiResaleController.text.trim(),
          untungRugi: _untungRugi,
          catatanKondisi: _catatanKondisiController.text.trim(),
        ),
      );

      final fakturOverlay = <String, dynamic>{
        'customer_name': _customerController.text,
        'customer_phone': _customerPhoneController.text,
        'customer_address': _customerAddressController.text,
      };

      final result = await CsOrderSubmitService.submitJsonOrder(
        orderData: orderData,
        fakturOverlay: fakturOverlay,
      );

      if (!mounted) return;

      if (result.success && result.fakturData != null) {
        if (result.offlineQueued) {
          CsOrderSubmitService.showOfflineQueuedSnackBar(
            context,
            offlineRef: result.offlineRef ?? '??????',
          );
        } else {
          ref.invalidate(todayOrdersProvider);
          ref.invalidate(orderTodayStatsProvider);
          bumpCsDailyOrdersListRevision(ref);
        }

        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => FakturPage(orderData: result.fakturData!),
          ),
        );
      } else {
        throw Exception(result.errorMessage ?? 'Failed to create buyback order');
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
              BuybackHeaderSection(
                modeToko: _modeToko,
                notaOrderController: _notaOrderController,
                onModeChanged: (mode) => setState(() => _modeToko = mode),
              ),

              BuybackNotaLookupSection(
                notaLamaController: _notaLamaController,
                nomorNotaController: _nomorNotaController,
                isManualEntry: _isManualEntry,
                isLookingUpItem: _isLookingUpItem,
                onLookup: _lookupItem,
                onScanNotaLama: () => _scanAndFill(
                  _notaLamaController,
                  onScanned: (_) => _lookupItem(),
                ),
                onNotaLamaChanged: () => setState(() {}),
              ),
              const SizedBox(height: 16),

              BuybackCustomerField(
                customerController: _customerController,
                phoneController: _customerPhoneController,
                addressController: _customerAddressController,
                selectedCustomer: _selectedCustomer,
                isLockedFromLookup: _isCustomerLockedFromLookup,
                onCustomerSelected: (customer) {
                  setState(() {
                    _customerPhoneController.text =
                        customer['phone'] ?? customer['no_hp'] ?? '';
                    _customerAddressController.text =
                        customer['address'] ?? customer['alamat'] ?? '';
                    _selectedCustomer = customer;
                    _isCustomerLockedFromLookup = false;
                  });
                },
                onFieldChanged: () => setState(() {}),
                onAddCustomer: _addCustomer,
                onScanQr: (controller) => _scanAndFill(controller),
              ),
              const SizedBox(height: 16),

              BuybackItemDetailsSection(
                kodeProdukController: _kodeProdukController,
                kategoriController: _kategoriController,
                jenisController: _jenisController,
                notaJual: _notaJual,
                selectedTipeBarang: _selectedTipeBarang,
                tipeController: _tipeController,
                namaItemController: _namaItemController,
                materialController: _materialController,
                kadarController: _kadarController,
                beratController: _beratController,
                quantityController: _quantityController,
                isDataFromOrderItems: _isDataFromOrderItems,
                onKategoriChanged: (value) {
                  setState(() {
                    _kategoriController.text = value ?? '';
                    _jenisController.clear();
                  });
                },
                onTipeBarangChanged: (value) {
                  setState(() => _selectedTipeBarang = value);
                },
              ),
              const SizedBox(height: 16),

              BuybackPriceConditionSection(
                hargaBeliController: _hargaBeliController,
                untungRugi: _untungRugi,
                onUntungRugiChanged: (value) {
                  setState(() {
                    _untungRugi = value;
                    _calculateNilaiUntungRugi();
                  });
                },
                kondisiFisik: _kondisiFisik,
                onKondisiFisikChanged: (value) {
                  setState(() => _kondisiFisik = value);
                },
                catatanKondisiController: _catatanKondisiController,
                penyesuaianBeratController: _penyesuaianBeratController,
                hargaPerGramController: _hargaPerGramController,
                potonganKondisiController: _potonganKondisiController,
                nilaiUntungRugiController: _nilaiUntungRugiController,
                nilaiResaleController: _nilaiResaleController,
                fotoXFile: _fotoXFile,
                fotoBytes: _fotoBytes,
                onPickFotoCamera: _pickFoto,
                onPickFotoGallery: _pickFotoFromGallery,
              ),
              const SizedBox(height: 24),

              // Submit Button
              SizedBox(
                width: double.infinity,
                child: Semantics(
                  button: true,
                  label: 'Buat order buyback',
                  enabled: !_isSubmitting,
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
              ),
        ],
      ),
    );
  }
}

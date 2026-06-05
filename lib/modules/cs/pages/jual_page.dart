import 'package:flutter/material.dart';
import 'dart:typed_data';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:io';
import 'dart:async';
import 'package:vanessa3/providers/customers_provider.dart';
import '../../../providers/order_today_provider.dart';
import 'package:vanessa3/providers/cs_daily_orders_refresh_provider.dart';

import 'package:vanessa3/widgets/qr_scan_route.dart';
import 'faktur_page.dart';
import 'package:vanessa3/providers/user_state_provider.dart';
import 'package:vanessa3/utils/cs_order_photo_picker.dart';
import 'package:vanessa3/utils/cs_order_photo_upload.dart';
import 'package:vanessa3/utils/responsive_layout.dart';
import 'package:vanessa3/services/cs_order_submit_service.dart';
import 'package:vanessa3/services/cs_stock_cache_service.dart';
import 'package:vanessa3/modules/cs/logic/jual_add_customer.dart';
import 'package:vanessa3/modules/cs/logic/jual_form_utils.dart';
import 'package:vanessa3/modules/cs/logic/jual_order_payload.dart';
import 'package:vanessa3/modules/cs/logic/jual_stock_item.dart';
import 'package:vanessa3/modules/cs/widgets/jual_customer_field.dart';
import 'package:vanessa3/modules/cs/widgets/jual_header_section.dart';
import 'package:vanessa3/modules/cs/widgets/jual_item_code_field.dart';
import 'package:vanessa3/modules/cs/widgets/jual_item_form_section.dart';
import 'package:vanessa3/modules/cs/widgets/jual_pricing_section.dart';
import 'package:vanessa3/modules/cs/widgets/jual_stock_type_section.dart';
import 'package:vanessa3/providers/network_provider.dart';

class JualPage extends ConsumerStatefulWidget {
  const JualPage({super.key});

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

  double _roundToNearest5000(double amount) =>
      JualFormUtils.roundToNearest5000(amount);

  double _parseNumberWithSeparators(String value) =>
      JualFormUtils.parseNumberWithSeparators(value);

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
    _jumlahController.text = JualFormUtils.formatNumberWithSeparators(
      roundedJumlah.round().toString(),
    );
  }

  @override
  void initState() {
    super.initState();
    // Fetch customers when page loads
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(customersProvider.notifier).fetchCustomers();
      final branchId = ref.read(userStateProvider).branch;
      if (branchId.trim().isNotEmpty) {
        CsStockCacheService.prefetchSellable(branchId);
      }
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

  Future<String?> _uploadProductPhoto() async {
    if (!_hasFoto) return null;
    try {
      return await CsOrderPhotoUpload.upload(
        file: _fotoFile,
        bytes: _fotoBytes,
        fileName: _fotoName,
      );
    } catch (e) {
      debugPrint('Error uploading foto: $e');
      return null;
    }
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
      final userState = ref.read(userStateProvider);
      final branchId = userState.branch;
      final online = ref.read(networkStatusProvider).isBackendReachable;

      final suggestions = await CsStockCacheService.lookupByCode(
        branchId: branchId,
        code: query,
        online: online,
      );
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

      if (exact == null) {
        if (!online && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Offline: kode tidak ada di cache stok. Buka Jual saat online untuk refresh.',
              ),
            ),
          );
        }
        return;
      }
      _applySelectedStockItem(exact);
    } catch (_) {
      // best-effort: jangan ganggu flow user kalau gagal
    }
  }

  void _applySelectedStockItem(Map<String, dynamic> item) {
    final snapshot = JualStockItemSnapshot.fromStockItem(item);
    if (snapshot == null) {
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
      _selectedItem = snapshot.item;
      _itemCodeController.text = snapshot.itemCode;
      _namaItemController.text = snapshot.namaItem;
      _beratController.text = snapshot.berat;
      _materialController.text = snapshot.material;
      _kadarController.text = snapshot.kadar;
      _kategoriController.text = snapshot.kategori;
      _jenisController.text = snapshot.jenis;
      _tipeController.text = snapshot.tipe;
      _qtyController.text = '1';
    });
    _calculateJumlah();
  }

  void _onSaleTypeChanged(String type) {
    setState(() {
      _saleType = type;
      _selectedItem = null;
      if (type == 'from_stock') {
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
        _qtyController.text = '1';
      } else {
        if (_kategoriController.text.isEmpty) {
          _kategoriController.text = 'PERHIASAN';
        }
        _jenisController.clear();
        if (_tipeController.text.isEmpty) {
          _tipeController.text = 'PERHIASAN';
        }
        _materialChoice = 'EMAS';
        _materialController.text = _materialChoice;
        _qtyController.text = '1';
      }
    });
  }

  Future<void> _scanItemCode() async {
    final controller =
        _itemAutocompleteFieldController ?? _itemCodeController;
    await _scanAndFill(
      controller,
      onFilled: () async {
        final code = controller.text;
        _itemCodeController.text = code;
        _updateItemSuggestions(code);
        await _tryAutoSelectItemByCode(code);
        if (mounted) setState(() {});
      },
    );
  }

  Future<void> _showAddCustomerDialog(
    String initialName,
    TextEditingController controller,
  ) async {
    final customer = await JualAddCustomer.showDialogAndCreate(
      context: context,
      ref: ref,
      initialName: initialName,
      syncController: controller,
    );
    if (!mounted || customer == null) return;
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
      _autocompleteKey++;
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

    if (_saleType == 'from_stock') {
      if (_selectedItem == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Pilih item dari stok terlebih dahulu!'),
            ),
          );
        }
        setState(() => _isSubmitting = false);
        return;
      }
    }

    final orderData = JualOrderPayloadBuilder.build(
      JualOrderFormInput(
        saleType: _saleType,
        modeToko: _modeToko,
        branchId: branchId,
        userId: userId,
        customerId: _selectedCustomer!['customer_id'],
        orderNumber: _notaOrderController.text,
        diskonText: _diskonController.text,
        namaItem: _namaItemController.text,
        beratText: _beratController.text,
        material: _materialController.text,
        kadar: _kadarController.text,
        kategori: _kategoriController.text,
        jenis: _jenisController.text,
        tipe: _tipeController.text,
        itemCode: _itemCodeController.text,
        qtyText: _qtyController.text,
        hargaPerGramText: _hargaPerGramController.text,
        selectedItem: _selectedItem,
        fotoUrl: fotoUrl,
      ),
    );

    try {
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
          ref.invalidate(orderTodayStatsProvider);
          ref.invalidate(todayOrdersProvider);
          bumpCsDailyOrdersListRevision(ref);
        }

        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => FakturPage(orderData: result.fakturData!),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              result.errorMessage ?? 'Gagal menyimpan order',
            ),
          ),
        );
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

    final userState = ref.read(userStateProvider);
    final branchId = userState.branch;
    final online = ref.read(networkStatusProvider).isBackendReachable;
    final isFromStock = _saleType == 'from_stock';

    return CsStockCacheService.searchItems(
      branchId: branchId,
      query: query,
      online: online,
      sellableOnly: isFromStock,
      limit: 10,
    );
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
              JualHeaderSection(
                modeToko: _modeToko,
                notaOrderController: _notaOrderController,
                onModeChanged: (mode) => setState(() => _modeToko = mode),
              ),

                            JualCustomerField(
                autocompleteKey: _autocompleteKey,
                customerController: _customerController,
                phoneController: _customerPhoneController,
                addressController: _customerAddressController,
                selectedCustomer: _selectedCustomer,
                onCustomerSelected: (customer) {
                  setState(() {
                    _customerController.text =
                        customer['name'] ?? customer['nama'] ?? '';
                    _customerPhoneController.text =
                        customer['phone'] ?? customer['no_hp'] ?? '';
                    _customerAddressController.text =
                        customer['address'] ?? customer['alamat'] ?? '';
                    _selectedCustomer = customer;
                  });
                },
                onCustomerTextChanged: (_) => setState(() {}),
                onAddCustomer: _showAddCustomerDialog,
                onScanQr: _scanAndFill,
              ),
              const SizedBox(height: 12.0),

              JualStockTypeSection(
                saleType: _saleType,
                onSaleTypeChanged: _onSaleTypeChanged,
              ),

                            // 5. Item Information Section

              JualItemCodeField(
                selectedItem: _selectedItem,
                itemSuggestions: _itemSuggestions,
                isLoadingSuggestions: _isLoadingSuggestions,
                itemCodeController: _itemCodeController,
                onSearch: _updateItemSuggestions,
                onItemSelected: (item) {
                  _applySelectedStockItem(item);
                  if (mounted) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
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
                onAutocompleteControllerReady: (c) {
                  _itemAutocompleteFieldController = c;
                },
                onTryAutoSelect: _tryAutoSelectItemByCode,
                onScanQr: (_) => _scanItemCode(),
              ),
              const SizedBox(height: 12.0),

              JualItemFormSection(
                saleType: _saleType,
                kategoriController: _kategoriController,
                jenisController: _jenisController,
                tipeController: _tipeController,
                namaItemController: _namaItemController,
                materialController: _materialController,
                kadarController: _kadarController,
                beratController: _beratController,
                qtyController: _qtyController,
                materialChoice: _materialChoice,
                onKategoriChanged: (kategori) {
                  setState(() {
                    _kategoriController.text = kategori;
                    _jenisController.clear();
                  });
                },
                onJenisChanged: (jenis) {
                  setState(() => _jenisController.text = jenis);
                },
                onTipeChanged: (tipe) {
                  setState(() => _tipeController.text = tipe);
                },
                onMaterialChoiceChanged: (choice, {required clearMaterialText}) {
                  setState(() {
                    _materialChoice = choice;
                    if (clearMaterialText) {
                      _materialController.clear();
                    } else {
                      _materialController.text = choice;
                    }
                  });
                },
                onRecalculate: _calculateJumlah,
              ),

                            JualPricingSection(
                saleType: _saleType,
                hasFoto: _hasFoto,
                fotoBytes: _fotoBytes,
                fotoFile: _fotoFile,
                hargaPerGramController: _hargaPerGramController,
                diskonController: _diskonController,
                jumlahController: _jumlahController,
                onRecalculate: _calculateJumlah,
                onPickFotoCamera: _pickFoto,
                onPickFotoGallery: _pickFotoFromGallery,
              ),

              // Submit Button
              Center(
                child: Semantics(
                  button: true,
                  label: 'Simpan order jual',
                  enabled: !_isSubmitting,
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

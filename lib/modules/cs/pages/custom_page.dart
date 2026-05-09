import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:io';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'customers_page.dart';
import 'faktur_page.dart';
import 'package:vanessa3/providers/user_state_provider.dart';

// Conditional imports for platform-specific packages
import 'package:image_picker/image_picker.dart'
    if (dart.library.html) '../../../utils/image_picker_stub.dart';
import 'package:vanessa3/utils/network_config.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

int? toInt(dynamic value) {
  if (value is int) return value;
  if (value is String) return int.tryParse(value);
  return null;
}

class CustomPage extends ConsumerStatefulWidget {
  const CustomPage({super.key, this.client});

  final http.Client? client;

  @override
  ConsumerState<CustomPage> createState() => _CustomPageState();
}

class _CustomPageState extends ConsumerState<CustomPage> {
  final _formKey = GlobalKey<FormState>();

  // Controllers untuk form
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
  String _modeToko = 'TOKO'; // Mode selection: TOKO or ONLINE
  String _jenisBarang =
      'KALUNG'; // Item type: KALUNG, GELANG, CINCIN, ANTING, LIONTIN
  String _asalMaterial = 'TOKO'; // Material source: BAWA SENDIRI or TOKO
  String _asalTambahan =
      'TOKO'; // Additional material source: BAWA SENDIRI or TOKO

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(customersProvider.notifier).fetchCustomers();
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
    }
    final response = await request.send();
    if (response.statusCode == 200) {
      final respStr = await response.stream.bytesToString();
      final data = jsonDecode(respStr);
      final url = data['url'] ?? data['fileUrl'] ?? data['path'];
      if (url is String && url.startsWith('/')) {
        return '$storageUrl$url';
      }
      return url;
    }
    return null;
  }

  double _parseMoney(String raw) {
    final s = raw.replaceAll(RegExp(r'[^0-9]'), '');
    final v = double.tryParse(s);
    return (v == null || v.isNaN || v.isInfinite) ? 0 : v;
  }

  Future<void> _pickFoto() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.camera);
    if (pickedFile != null) {
      final compressedFile = await _compressFoto(File(pickedFile.path));
      setState(() {
        _fotoFile = compressedFile;
      });
    }
  }

  Future<File> _compressFoto(File file) async {
    // Always output JPEG so backend mime filter accepts it.
    final targetPath =
        '${file.parent.path}/foto_${DateTime.now().millisecondsSinceEpoch}.jpg';
    XFile? resultX = await FlutterImageCompress.compressAndGetFile(
      file.absolute.path,
      targetPath,
      minWidth: 800,
      minHeight: 800,
      quality: 90,
      format: CompressFormat.jpeg,
      keepExif: false,
    );
    if (resultX != null) {
      return File(resultX.path);
    }
    return file;
  }

  Future<void> _scanAndFill(TextEditingController controller) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => Scaffold(
          appBar: AppBar(title: const Text('Scan QR Code')),
          body: MobileScanner(
            onDetect: (capture) {
              final List<Barcode> barcodes = capture.barcodes;
              if (barcodes.isNotEmpty) {
                controller.text = barcodes.first.rawValue ?? '';
                Navigator.of(context).pop();
              }
            },
          ),
        ),
      ),
    );
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
              decoration: const InputDecoration(labelText: 'Email'),
              keyboardType: TextInputType.emailAddress,
            ),
            TextField(
              controller: phoneController,
              decoration: const InputDecoration(labelText: 'No. Telepon'),
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
            'phone': phoneController.text,
            'address': addressController.text,
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

  Future<void> _submitOrder() async {
    if (!_formKey.currentState!.validate()) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Mohon isi semua field yang wajib!')),
        );
      }
      return;
    }

    // Foto WAJIB untuk Custom (referensi/desain)
    if (_fotoFile == null) {
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
    final branchId = toInt(userState.branch);
    final userId = toInt(userState.userId);
    final customerId = toInt(
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
    if (_fotoFile != null) {
      fotoUrl = await _uploadFoto(_fotoFile);
    }
    if (_fotoFile != null && (fotoUrl == null || fotoUrl.toString().trim().isEmpty)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Upload foto gagal. Coba ambil foto ulang (JPEG/PNG).')),
        );
      }
      return;
    }

    final weightVal = double.tryParse(_beratTargetController.text.trim()) ?? 0;
    final totalBiayaVal = _parseMoney(_totalBiayaController.text);
    final uangMukaVal = _parseMoney(_uangMukaController.text);
    final initialCustomStatus =
        (totalBiayaVal > 0 && uangMukaVal > 0)
            ? 'pending'
            : 'sent-to-workshop';
    final generatedKodeProduk = _notaOrderController.text.trim().isNotEmpty
        ? _notaOrderController.text.trim()
        : 'CUST-${DateTime.now().millisecondsSinceEpoch}';

    final orderData = {
      'order_type': 'custom',
      'status': initialCustomStatus,
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
          'kategori': 'custom',
          'jenis': _jenisBarang,
          'tipe': 'custom',
          'material': _materialController.text.trim(),
          'purity': _kadarController.text.trim(),
        },
      ],
      // Extra fields (backend may ignore; kept for future use)
      'spesifikasi': _spesifikasiController.text.trim(),
      'asal_material': _asalMaterial,
      'material_tambahan': _materialTambahanController.text.trim(),
      'asal_tambahan': _asalTambahan,
      'estimasi_waktu': _estimasiWaktuController.text.trim(),
      'customer_name': _customerController.text,
      'customer_phone': _customerPhoneController.text,
      'customer_address': _customerAddressController.text,
    };

    try {
      final baseUrl = NetworkConfig.baseUrl;

      final response = await http.post(
        Uri.parse('$baseUrl/orders'),
        headers: NetworkConfig.defaultHeaders,
        body: jsonEncode(orderData),
      );

      if (response.statusCode == 201 || response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final createdOrderId = data['order_id'] ?? data['orderId'];

        if (uangMukaVal > 0 && createdOrderId != null) {
          try {
            await http.post(
              Uri.parse('$baseUrl/payments'),
              headers: NetworkConfig.defaultHeaders,
              body: jsonEncode({
                'order_id': createdOrderId,
                'amount': uangMukaVal,
                'method': 'cash',
                'status': 'pending',
                'notes': 'Uang muka (custom)',
                'payment_kind': 'dp',
              }),
            );
          } catch (_) {
            // best-effort
          }
        }
        if (mounted) {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (context) => FakturPage(orderData: data),
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

    // Format: BRANCH_INITIAL + "C" + 8_DIGIT_NUMBER (C for Custom)
    final orderNumber = '$branchInitial${'C'}$uniqueNumber';

    setState(() {
      _notaOrderController.text = orderNumber;
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
      appBar: AppBar(title: const Text('Form Order Custom')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: ListView(
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
              // Bagian 1: Customer
              Row(
                children: [
                  const SizedBox(
                    width: 120,
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
                    child: StatefulBuilder(
                      builder: (context, setFieldState) {
                        return Row(
                          children: [
                            Expanded(
                              child: customerList.isLoading
                                  ? const TextField(
                                      decoration: InputDecoration(
                                        labelText: 'Loading customers...',
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
                                          (
                                            TextEditingValue textEditingValue,
                                          ) {
                                            if (textEditingValue.text == '') {
                                              return const Iterable<
                                                Map<String, dynamic>
                                              >.empty();
                                            }
                                            final input = textEditingValue.text
                                                .toLowerCase();
                                            final suggestions =
                                                customerList.customers.where((c) {
                                              final name =
                                                  (c['name'] ?? c['nama'] ?? '')
                                                      .toString()
                                                      .toLowerCase();
                                              return name.contains(input);
                                            }).toList();
                                            return suggestions;
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
                                          _customerController.text =
                                              customer['name'] ??
                                              customer['nama'] ??
                                              '';
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
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Row(
                                                  children: [
                                                    Expanded(
                                                      child: TextFormField(
                                                        controller: controller,
                                                        focusNode: focusNode,
                                                        decoration: const InputDecoration(
                                                          hintText:
                                                              'Cari customer...',
                                                          border:
                                                              OutlineInputBorder(),
                                                          contentPadding:
                                                              EdgeInsets.symmetric(
                                                                vertical: 12,
                                                                horizontal: 12,
                                                              ),
                                                        ),
                                                        onChanged: (_) =>
                                                            setState(() {}),
                                                        onFieldSubmitted:
                                                            (value) =>
                                                                onFieldSubmitted(),
                                                        validator: (value) {
                                                          if (value == null ||
                                                              value.isEmpty) {
                                                            return 'Customer wajib dipilih';
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
                                                                  size: 20,
                                                                ),
                                                                tooltip:
                                                                    'Tambah Customer',
                                                                onPressed: () => _showAddCustomerDialog(
                                                                  controller
                                                                      .text,
                                                                  controller,
                                                                ),
                                                                padding:
                                                                    EdgeInsets
                                                                        .zero,
                                                                constraints:
                                                                    const BoxConstraints(),
                                                              ),
                                                              IconButton(
                                                                icon: const Icon(
                                                                  Icons
                                                                      .qr_code_scanner,
                                                                  size: 20,
                                                                ),
                                                                tooltip:
                                                                    'Scan QR Customer',
                                                                onPressed: () =>
                                                                    _scanAndFill(
                                                                      controller,
                                                                    ),
                                                                padding:
                                                                    EdgeInsets
                                                                        .zero,
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
                                                                  Icons
                                                                      .person_add,
                                                                  size: 20,
                                                                ),
                                                                tooltip:
                                                                    'Tambah Customer',
                                                                onPressed: () => _showAddCustomerDialog(
                                                                  controller
                                                                      .text,
                                                                  controller,
                                                                ),
                                                                padding:
                                                                    EdgeInsets
                                                                        .zero,
                                                                constraints:
                                                                    const BoxConstraints(),
                                                              ),
                                                              IconButton(
                                                                icon: const Icon(
                                                                  Icons
                                                                      .qr_code_scanner,
                                                                  size: 20,
                                                                ),
                                                                tooltip:
                                                                    'Scan QR Customer',
                                                                onPressed: () =>
                                                                    _scanAndFill(
                                                                      controller,
                                                                    ),
                                                                padding:
                                                                    EdgeInsets
                                                                        .zero,
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
              const SizedBox(height: 24),

              // Bagian 2: Spesifikasi Custom
              const Text(
                'SPESIFIKASI BARANG CUSTOM',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              const SizedBox(height: 12),
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
                          label: const Text('CINCIN'),
                          selected: _jenisBarang == 'CINCIN',
                          onSelected: (selected) {
                            setState(() {
                              _jenisBarang = 'CINCIN';
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
                        hintText: 'Contoh: 500000',
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
                        hintText: 'Contoh: Cincin Pernikahan Custom',
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
                      child: Text('Spesifikasi Detail'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextFormField(
                      controller: _spesifikasiController,
                      maxLines: 3,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        hintText:
                            'Contoh: Ukuran cincin 18, dengan batu mulia ruby, warna emas kuning',
                      ),
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Spesifikasi wajib diisi';
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
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Material wajib diisi';
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
                      child: Text('Asal Material'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Wrap(
                      spacing: 8.0,
                      children: [
                        ChoiceChip(
                          label: const Text('BAWA SENDIRI'),
                          selected: _asalMaterial == 'BAWA SENDIRI',
                          onSelected: (selected) {
                            setState(() {
                              _asalMaterial = 'BAWA SENDIRI';
                            });
                          },
                        ),
                        ChoiceChip(
                          label: const Text('TOKO'),
                          selected: _asalMaterial == 'TOKO',
                          onSelected: (selected) {
                            setState(() {
                              _asalMaterial = 'TOKO';
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
                      child: Text('Tambahan'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextFormField(
                      controller: _materialTambahanController,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        hintText: 'Contoh: Berlian, Ruby, Safir',
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
                      child: Text('Asal Tambahan'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Wrap(
                      spacing: 8.0,
                      children: [
                        ChoiceChip(
                          label: const Text('BAWA SENDIRI'),
                          selected: _asalTambahan == 'BAWA SENDIRI',
                          onSelected: (selected) {
                            setState(() {
                              _asalTambahan = 'BAWA SENDIRI';
                            });
                          },
                        ),
                        ChoiceChip(
                          label: const Text('TOKO'),
                          selected: _asalTambahan == 'TOKO',
                          onSelected: (selected) {
                            setState(() {
                              _asalTambahan = 'TOKO';
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
                      child: Text('Berat Target (gram)'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextFormField(
                      controller: _beratTargetController,
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
                      child: Text('Estimasi Waktu'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextFormField(
                      controller: _estimasiWaktuController,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        hintText: 'Contoh: 2 minggu, 3 hari, dll',
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // Bagian 3: Upload Foto (WAJIB - Referensi/Desain)
              const Text(
                'UPLOAD FOTO DESAIN/REFERENSI (WAJIB)',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                  color: Colors.red,
                ),
              ),
              const SizedBox(height: 12),
              if (_fotoFile != null)
                Container(
                  height: 200,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Image.file(_fotoFile!, fit: BoxFit.cover),
                ),
              const SizedBox(height: 12),
              ElevatedButton.icon(
                onPressed: _pickFoto,
                icon: const Icon(Icons.camera_alt),
                label: Text(_fotoFile == null ? 'Ambil Foto' : 'Ganti Foto'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  backgroundColor: Colors.blue,
                ),
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
                  'SUBMIT CUSTOM',
                  style: TextStyle(fontSize: 16, color: Colors.white),
                ),
              ),
              const SizedBox(height: 12),
            ],
          ),
        ),
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

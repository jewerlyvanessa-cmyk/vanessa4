import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:io';
import 'faktur_page.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

// Conditional imports for platform-specific packages
import 'package:image_picker/image_picker.dart'
    if (dart.library.html) '../../../utils/image_picker_stub.dart';
import 'package:vanessa3/main.dart';
import 'package:vanessa3/utils/network_config.dart';

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
  final TextEditingController _keteranganController = TextEditingController();

  File? _fotoFile;
  bool _isLoading = false;
  List<dynamic> _readyItems = [];
  bool _isLoadingItems = false;

  @override
  void dispose() {
    _orderNumberController.dispose();
    _customerController.dispose();
    _customerPhoneController.dispose();
    _namaItemController.dispose();
    _beratController.dispose();
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
          '$baseUrl/orders?branch_id=${userState.branch}&status=completed',
        ),
        headers: NetworkConfig.defaultHeaders,
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          _readyItems = data is List ? data : [];
        });
      }
    } catch (e) {
      debugPrint('Error loading ready items: $e');
    } finally {
      setState(() => _isLoadingItems = false);
    }
  }

  Future<void> _scanQRCode() async {
    final result = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (context) => const QRScannerPage()),
    );

    if (result != null && result.isNotEmpty) {
      setState(() {
        _orderNumberController.text = result;
      });
    }
  }

  Future<String?> _uploadFoto(File? foto) async {
    if (foto == null) return null;
    final baseUrl = NetworkConfig.baseUrl.replaceAll('3000', '4000');
    final uri = Uri.parse('$baseUrl/upload');
    final request = http.MultipartRequest('POST', uri)
      ..files.add(await http.MultipartFile.fromPath('file', foto.path));
    final response = await request.send();
    if (response.statusCode == 200) {
      final respStr = await response.stream.bytesToString();
      final data = jsonDecode(respStr);
      return data['url'] ?? data['fileUrl'] ?? data['path'];
    }
    return null;
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

      final orderData = {
        'branch_id': branchId,
        'order_number': _orderNumberController.text,
        'customer_name': _customerController.text,
        'customer_phone': _customerPhoneController.text,
        'nama_item': _namaItemController.text,
        'berat': _beratController.text,
        'keterangan': _keteranganController.text,
        'foto_new': fotoUrl,
        'user_id': userId,
        'order_type': 'ambil',
        'status': 'completed',
      };

      final baseUrl = NetworkConfig.baseUrl;
      final response = await (widget.client ?? http.Client()).post(
        Uri.parse('$baseUrl/orders'),
        headers: NetworkConfig.defaultHeaders,
        body: jsonEncode(orderData),
      );

      if (response.statusCode == 201) {
        final data = jsonDecode(response.body);
        if (mounted) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => FakturPage(orderData: data),
            ),
          );
        }
      } else {
        throw Exception('Failed to create order: ${response.statusCode}');
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('Ambil Barang'),
        backgroundColor: Colors.blue,
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
                    color: Colors.blue,
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
                          border: Border.all(color: Colors.grey),
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
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _submitForm,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  child: _isLoading
                      ? const CircularProgressIndicator(color: Colors.white)
                      : const Text(
                          'SIMPAN',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                ),
              ),
              const SizedBox(height: 24),

              // Daftar Barang Siap Ambil
              const Text(
                'DAFTAR BARANG SIAP AMBIL',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.blue,
                ),
              ),
              const SizedBox(height: 12),
              if (_isLoadingItems)
                const Center(child: CircularProgressIndicator())
              else if (_readyItems.isEmpty)
                const Center(
                  child: Text(
                    'Tidak ada barang siap ambil',
                    style: TextStyle(color: Colors.grey),
                  ),
                )
              else
                ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _readyItems.length,
                  itemBuilder: (context, index) {
                    final item = _readyItems[index];
                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.inventory, color: Colors.blue),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    '${item['order_number'] ?? ''} - ${item['customer_name'] ?? ''}',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Item: ${item['nama_item'] ?? ''}',
                              style: const TextStyle(fontSize: 12),
                            ),
                            Text(
                              'Berat: ${item['berat'] ?? ''} gr',
                              style: const TextStyle(fontSize: 12),
                            ),
                            Text(
                              'No. HP: ${item['customer_phone'] ?? ''}',
                              style: const TextStyle(fontSize: 12),
                            ),
                          ],
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

class QRScannerPage extends StatefulWidget {
  const QRScannerPage({super.key});

  @override
  State<QRScannerPage> createState() => _QRScannerPageState();
}

class _QRScannerPageState extends State<QRScannerPage> {
  MobileScannerController cameraController = MobileScannerController();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Scan QR Code'),
        backgroundColor: Colors.blue,
        actions: [
          IconButton(
            icon: const Icon(Icons.flash_on),
            onPressed: () => cameraController.toggleTorch(),
          ),
          IconButton(
            icon: const Icon(Icons.cameraswitch),
            onPressed: () => cameraController.switchCamera(),
          ),
        ],
      ),
      body: MobileScanner(
        controller: cameraController,
        onDetect: (capture) {
          final List<Barcode> barcodes = capture.barcodes;
          for (final barcode in barcodes) {
            if (barcode.rawValue != null) {
              Navigator.pop(context, barcode.rawValue);
              break;
            }
          }
        },
      ),
    );
  }

  @override
  void dispose() {
    cameraController.dispose();
    super.dispose();
  }
}

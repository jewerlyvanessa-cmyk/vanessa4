import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:convert';
import 'package:vanessa3/providers/user_state_provider.dart';
import 'package:vanessa3/core/network/api_client.dart';
import 'package:vanessa3/data/offline_queue.dart';
import 'package:vanessa3/providers/websocket_provider.dart';
import 'package:vanessa3/utils/cs_order_photo_picker.dart';
import 'package:vanessa3/utils/payment_proof_upload.dart';
import 'package:vanessa3/modules/kasir/kasir_order_display.dart';
import 'package:vanessa3/utils/responsive_layout.dart';

class PaymentPage extends ConsumerStatefulWidget {
  final Map<String, dynamic> order;

  const PaymentPage({super.key, required this.order});

  @override
  ConsumerState<PaymentPage> createState() => _PaymentPageState();
}

class _PaymentPageState extends ConsumerState<PaymentPage> {
  final _formKey = GlobalKey<FormState>();
  String _paymentMethod = 'cash';
  final TextEditingController _cashReceivedController = TextEditingController();
  final TextEditingController _amountController = TextEditingController();
  final TextEditingController _notesController = TextEditingController();
  bool _isProcessing = false;
  bool _proofPicking = false;
  bool _proofUploading = false;
  CsOrderPhotoPickResult? _proofPick;
  String? _proofUrl;

  @override
  void initState() {
    super.initState();
    _amountController.text = (widget.order['remaining_amount'] ?? widget.order['total'])
            ?.toString() ??
        '0';
    _cashReceivedController.text = _amountController.text;
  }

  bool _methodRequiresProof() {
    return _paymentMethod == 'transfer' ||
        _paymentMethod == 'qris' ||
        _paymentMethod == 'e-wallet';
  }

  Future<void> _pickProofFromCamera() async {
    setState(() => _proofPicking = true);
    try {
      final pick = await CsOrderPhotoPicker.pickFromCamera(imageQuality: 80);
      if (pick != null && mounted) {
        setState(() {
          _proofPick = pick;
          _proofUrl = null;
        });
      }
    } finally {
      if (mounted) setState(() => _proofPicking = false);
    }
  }

  Future<void> _pickProofFromGallery() async {
    setState(() => _proofPicking = true);
    try {
      final pick = await CsOrderPhotoPicker.pickFromGallery(imageQuality: 80);
      if (pick != null && mounted) {
        setState(() {
          _proofPick = pick;
          _proofUrl = null;
        });
      }
    } finally {
      if (mounted) setState(() => _proofPicking = false);
    }
  }

  Future<String?> _ensureProofUploaded() async {
    if (!_methodRequiresProof()) return null;
    if (_proofUrl != null && _proofUrl!.trim().isNotEmpty) return _proofUrl;
    final pick = _proofPick;
    if (pick == null || !pick.hasPhoto) return null;

    setState(() => _proofUploading = true);
    try {
      final token = ref.read(userStateProvider).authToken;
      final url = await PaymentProofUpload.upload(pick, token: token);
      if (url != null && url.trim().isNotEmpty && mounted) {
        setState(() => _proofUrl = url);
      }
      return url;
    } finally {
      if (mounted) setState(() => _proofUploading = false);
    }
  }

  Widget? _proofPreview() {
    final pick = _proofPick;
    if (pick == null) return null;
    if (pick.bytes != null && pick.bytes!.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Image.memory(
          pick.bytes!,
          width: 220,
          height: 220,
          fit: BoxFit.cover,
        ),
      );
    }
    if (!kIsWeb) {
      final file = pick.file;
      if (file != null) {
        return ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Image.file(
            file,
            width: 220,
            height: 220,
            fit: BoxFit.cover,
          ),
        );
      }
    }
    return null;
  }

  double _orderTotal() {
    final raw = widget.order['remaining_amount'] ?? widget.order['total'];
    final v = raw is num ? raw.toDouble() : double.tryParse(raw?.toString() ?? '');
    return (v == null || v.isNaN || v.isInfinite) ? 0 : v;
  }

  double _cashReceived() {
    final v = double.tryParse(_cashReceivedController.text.trim());
    return (v == null || v.isNaN || v.isInfinite) ? 0 : v;
  }

  double _cashChange() {
    return _cashReceived() - _orderTotal();
  }

  String _composeNotesForCash(String baseNotes) {
    final received = _cashReceived();
    final change = _cashChange();
    final parts = <String>[];
    if (baseNotes.trim().isNotEmpty) parts.add(baseNotes.trim());
    parts.add('Tunai: diterima=${received.toStringAsFixed(0)}, kembalian=${change.toStringAsFixed(0)}');
    return parts.join(' | ');
  }

  Future<void> _processPayment() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isProcessing = true;
    });

    try {
      final userState = ref.read(userStateProvider);
      final idempotencyKey = OfflineQueue.instance.newIdempotencyKey();

      final proofUrl = await _ensureProofUploaded();
      if (_methodRequiresProof() && (proofUrl == null || proofUrl.trim().isEmpty)) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Bukti pembayaran wajib. Ambil foto atau pilih dari galeri.',
              ),
            ),
          );
        }
        return;
      }

      final isCash = _paymentMethod == 'cash';
      final amountToRecord = isCash ? _orderTotal() : double.parse(_amountController.text);
      final notesToSend = isCash
          ? _composeNotesForCash(_notesController.text)
          : _notesController.text;

      final orderType =
          (widget.order['order_type'] ?? '').toString().toLowerCase();
      final hc = widget.order['has_completed_payment'];
      final hasCompleted =
          hc == true || hc == 1 || hc?.toString().toLowerCase() == 'true';
      final isServiceLike =
          orderType == 'service' || orderType == 'custom';
      final paymentKind =
          isServiceLike ? (hasCompleted ? 'settlement' : 'dp') : null;

      final paymentData = <String, dynamic>{
        'order_id': widget.order['order_id'],
        'amount': amountToRecord,
        'method': _paymentMethod,
        'notes': notesToSend,
        'proof_url': proofUrl,
        'user_id': userState.userId,
        'branch_id': userState.branch,
      };
      if (paymentKind != null) {
        paymentData['payment_kind'] = paymentKind;
      }

      final response = await ApiClient.post(
        '/payments',
        headers: {'X-Idempotency-Key': idempotencyKey},
        body: jsonEncode(paymentData),
      );

      if (response.statusCode == 201) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('Pembayaran berhasil!')));
          Navigator.pop(context, true);
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Gagal memproses pembayaran: ${response.body}'),
            ),
          );
        }
      }
    } catch (e) {
      try {
        final isCash = _paymentMethod == 'cash';
        final amountToRecord = isCash ? _orderTotal() : (double.tryParse(_amountController.text) ?? 0);
        final notesToSend = isCash
            ? _composeNotesForCash(_notesController.text)
            : _notesController.text;

        final orderType =
            (widget.order['order_type'] ?? '').toString().toLowerCase();
        final hc = widget.order['has_completed_payment'];
        final hasCompleted =
            hc == true || hc == 1 || hc?.toString().toLowerCase() == 'true';
        final isServiceLike =
            orderType == 'service' || orderType == 'custom';
        final paymentKind =
            isServiceLike ? (hasCompleted ? 'settlement' : 'dp') : null;
        final body = <String, dynamic>{
          'order_id': widget.order['order_id'],
          'amount': amountToRecord,
          'method': _paymentMethod,
          'notes': notesToSend,
          'proof_url': _proofUrl,
          'user_id': ref.read(userStateProvider).userId,
          'branch_id': ref.read(userStateProvider).branch,
        };
        if (paymentKind != null) {
          body['payment_kind'] = paymentKind;
        }
        final item = OfflineQueueItem(
          id: DateTime.now().microsecondsSinceEpoch.toString(),
          type: 'payment',
          method: 'POST',
          path: '/payments',
          body: body,
          idempotencyKey: OfflineQueue.instance.newIdempotencyKey(),
          attempts: 0,
          createdAt: DateTime.now(),
        );
        await OfflineQueue.instance.enqueue(item);
      } catch (_) {}
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    } finally {
      if (mounted) {
        setState(() {
          _isProcessing = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isServerHealthy = ref.watch(healthCheckProvider);
    final orderType =
        (widget.order['order_type'] ?? '').toString().toLowerCase();
    final isServiceLike = orderType == 'service' || orderType == 'custom';
    final hc = widget.order['has_completed_payment'];
    final hasCompleted =
        hc == true || hc == 1 || hc?.toString().toLowerCase() == 'true';
    final paidLabel = isServiceLike
        ? (hasCompleted ? 'Sudah dibayar (termasuk DP)' : 'Uang muka (DP)')
        : 'Terbayar';
    final sisaLabel =
        isServiceLike ? 'Sisa tagihan (pelunasan)' : 'Sisa Tagihan';

    final proofBusy = _proofPicking || _proofUploading;

    return Scaffold(
      appBar: AppBar(
        title: Text('Pembayaran Order #${widget.order['order_id']}'),
        actions: [
          Row(
            children: [
              Icon(
                isServerHealthy ? Icons.wifi : Icons.wifi_off,
                color: isServerHealthy ? Colors.green : Colors.red,
                size: 20,
              ),
              const SizedBox(width: 4),
              const Text('Live', style: TextStyle(fontSize: 12)),
            ],
          ),
          const SizedBox(width: 16),
        ],
      ),
      resizeToAvoidBottomInset: true,
      body: ResponsiveLayout.scrollableForm(
        context: context,
        formKey: _formKey,
        children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Ringkasan Order',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Customer: ${widget.order['customer_name'] ?? 'N/A'}',
                      ),
                      Text('Item: ${kasirOrderItemTitle(widget.order)}'),
                      Text(
                        'Berat: ${kasirOrderWeightGramsLabel(widget.order)} gram',
                      ),
                      Text('Total Tagihan: Rp ${widget.order['total']?.toString() ?? '0'}'),
                      if ((widget.order['paid_amount'] ?? 0) != 0)
                        Text('$paidLabel: Rp ${widget.order['paid_amount']?.toString() ?? '0'}'),
                      if ((widget.order['remaining_amount'] ?? 0) != 0)
                        Text('$sisaLabel: Rp ${widget.order['remaining_amount']?.toString() ?? '0'}'),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),

              const Text('Metode Pembayaran'),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _paymentMethodChip(
                    value: 'cash',
                    label: 'Tunai',
                    icon: Icons.payments,
                  ),
                  _paymentMethodChip(
                    value: 'transfer',
                    label: 'Transfer',
                    icon: Icons.account_balance,
                  ),
                  _paymentMethodChip(
                    value: 'qris',
                    label: 'QRIS',
                    icon: Icons.qr_code_2,
                  ),
                  _paymentMethodChip(
                    value: 'e-wallet',
                    label: 'E-Wallet',
                    icon: Icons.account_balance_wallet,
                  ),
                ],
              ),
              const SizedBox(height: 16),

              if (_paymentMethod == 'cash') ...[
                TextFormField(
                  controller: _cashReceivedController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    labelText: 'Uang diterima',
                    prefixText: 'Rp ',
                  ),
                  onChanged: (_) => setState(() {}),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Uang diterima wajib diisi';
                    }
                    final received = double.tryParse(value.trim());
                    if (received == null || received <= 0) {
                      return 'Uang diterima harus valid';
                    }
                    if (received < _orderTotal()) {
                      return 'Uang diterima kurang dari total tagihan';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                InputDecorator(
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    labelText: 'Kembalian',
                    prefixText: 'Rp ',
                  ),
                  child: Text(
                    _cashChange() < 0 ? '0' : _cashChange().toStringAsFixed(0),
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: _cashChange() < 0 ? Colors.red : Colors.green,
                    ),
                  ),
                ),
              ] else ...[
                TextFormField(
                  controller: _amountController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    labelText: 'Jumlah Bayar',
                    prefixText: 'Rp ',
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Jumlah bayar wajib diisi';
                    }
                    final amount = double.tryParse(value);
                    if (amount == null || amount <= 0) {
                      return 'Jumlah bayar harus valid';
                    }
                    return null;
                  },
                ),
              ],
              const SizedBox(height: 16),

              if (_methodRequiresProof()) ...[
                const Text('Bukti Pembayaran'),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: proofBusy ? null : _pickProofFromCamera,
                        icon: proofBusy
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.photo_camera_outlined),
                        label: const Text('Kamera'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: proofBusy ? null : _pickProofFromGallery,
                        icon: proofBusy
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.photo_library_outlined),
                        label: const Text('Galeri'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                if (_proofPreview() != null)
                  Center(child: _proofPreview()!),
                if (_proofPick == null &&
                    (_proofUrl == null || _proofUrl!.trim().isEmpty))
                  const Text(
                    'Wajib upload bukti untuk metode ini.',
                    style: TextStyle(color: Colors.red, fontSize: 12),
                  ),
                const SizedBox(height: 16),
              ],

              TextFormField(
                controller: _notesController,
                maxLines: 3,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  labelText: 'Catatan (Opsional)',
                  hintText: 'Tambahkan catatan pembayaran...',
                ),
              ),
              const SizedBox(height: 24),

              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: (_isProcessing || proofBusy) ? null : _processPayment,
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    backgroundColor: Colors.green,
                  ),
                  child: _isProcessing
                      ? const CircularProgressIndicator(color: Colors.white)
                      : const Text(
                          'PROSES PEMBAYARAN',
                          style: TextStyle(fontSize: 16, color: Colors.white),
                        ),
                ),
              ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _cashReceivedController.dispose();
    _amountController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Widget _paymentMethodChip({
    required String value,
    required String label,
    required IconData icon,
  }) {
    final selected = _paymentMethod == value;
    return ChoiceChip(
      label: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: selected ? Colors.white : null),
          const SizedBox(width: 6),
          Text(label),
        ],
      ),
      selected: selected,
      selectedColor: Theme.of(context).colorScheme.primary,
      labelStyle: TextStyle(
        color: selected ? Colors.white : null,
        fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
      ),
      onSelected: (_) {
        setState(() {
          _paymentMethod = value;
          if (!_methodRequiresProof()) {
            _proofPick = null;
            _proofUrl = null;
          }
        });
      },
    );
  }
}

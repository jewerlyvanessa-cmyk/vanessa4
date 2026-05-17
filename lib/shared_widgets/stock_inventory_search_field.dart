import 'package:flutter/material.dart';
import 'package:vanessa3/utils/stock_inventory_search.dart';
import 'package:vanessa3/widgets/qr_scan_route.dart';

/// Kolom pencarian stok + scan QR (isi otomatis & filter daftar).
class StockInventorySearchField extends StatelessWidget {
  const StockInventorySearchField({
    super.key,
    required this.controller,
    required this.onQueryChanged,
    this.enabled = true,
    this.hintText =
        'Cari kode, nama, jenis, kategori, material, kadar, status…',
  });

  final TextEditingController controller;
  final ValueChanged<String> onQueryChanged;
  final bool enabled;
  final String hintText;

  Future<void> _scan(BuildContext context) async {
    if (!enabled) return;
    final raw = await pushQrScanPage(
      context,
      title: 'Scan QR — Cari stok',
      showTorchActions: true,
    );
    if (raw == null || raw.trim().isEmpty) return;
    final q = normalizeStockSearchQuery(raw);
    controller.text = q;
    onQueryChanged(q);
  }

  void _clear() {
    controller.clear();
    onQueryChanged('');
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      enabled: enabled,
      textInputAction: TextInputAction.search,
      decoration: InputDecoration(
        prefixIcon: const Icon(Icons.search),
        hintText: hintText,
        border: const OutlineInputBorder(),
        isDense: true,
        suffixIcon: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (controller.text.trim().isNotEmpty)
              IconButton(
                tooltip: 'Hapus pencarian',
                onPressed: enabled ? _clear : null,
                icon: const Icon(Icons.clear),
              ),
            IconButton(
              tooltip: 'Scan QR / barcode',
              onPressed: enabled ? () => _scan(context) : null,
              icon: const Icon(Icons.qr_code_scanner),
            ),
          ],
        ),
      ),
      onChanged: onQueryChanged,
      onSubmitted: onQueryChanged,
    );
  }
}

/// Stateful wrapper agar tombol clear tampil saat teks berubah.
class StockInventorySearchFieldStateful extends StatefulWidget {
  const StockInventorySearchFieldStateful({
    super.key,
    required this.controller,
    required this.onQueryChanged,
    this.enabled = true,
    this.hintText,
  });

  final TextEditingController controller;
  final ValueChanged<String> onQueryChanged;
  final bool enabled;
  final String? hintText;

  @override
  State<StockInventorySearchFieldStateful> createState() =>
      _StockInventorySearchFieldStatefulState();
}

class _StockInventorySearchFieldStatefulState
    extends State<StockInventorySearchFieldStateful> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onControllerChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChanged);
    super.dispose();
  }

  void _onControllerChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return StockInventorySearchField(
      controller: widget.controller,
      onQueryChanged: widget.onQueryChanged,
      enabled: widget.enabled,
      hintText: widget.hintText ??
          'Cari kode, nama, jenis, kategori, material, kadar, status…',
    );
  }
}

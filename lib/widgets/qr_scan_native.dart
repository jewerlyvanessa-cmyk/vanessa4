import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:vanessa3/widgets/qr_scan_manual_entry.dart';

/// Scan berkelanjutan — kumpulkan banyak kode sebelum kembali.
Future<List<String>?> pushQrBatchScanPage(
  BuildContext context, {
  String title = 'Scan batch',
  bool showTorchActions = false,
  Color? appBarBackgroundColor,
}) {
  return Navigator.of(context).push<List<String>>(
    MaterialPageRoute(
      builder: (ctx) => _QrBatchScanPage(
        title: title,
        showTorchActions: showTorchActions,
        appBarBackgroundColor: appBarBackgroundColor,
      ),
    ),
  );
}

/// Scan QR di Android, iOS, desktop.
Future<String?> pushQrScanPage(
  BuildContext context, {
  String title = 'Scan QR Code',
  bool showTorchActions = false,
  Color? appBarBackgroundColor,
}) {
  return Navigator.of(context).push<String>(
    MaterialPageRoute(
      builder: (ctx) => _QrScanPage(
        title: title,
        showTorchActions: showTorchActions,
        appBarBackgroundColor: appBarBackgroundColor,
      ),
    ),
  );
}

class _QrScanPage extends StatefulWidget {
  const _QrScanPage({
    required this.title,
    required this.showTorchActions,
    this.appBarBackgroundColor,
  });

  final String title;
  final bool showTorchActions;
  final Color? appBarBackgroundColor;

  @override
  State<_QrScanPage> createState() => _QrScanPageState();
}

class _QrScanPageState extends State<_QrScanPage> {
  bool _handled = false;
  late final MobileScannerController _camera;

  @override
  void initState() {
    super.initState();
    _camera = MobileScannerController(
      detectionSpeed: DetectionSpeed.normal,
      facing: CameraFacing.back,
    );
  }

  @override
  void dispose() {
    _camera.dispose();
    super.dispose();
  }

  void _completeWith(String raw) {
    if (_handled || !mounted) return;
    final value = raw.trim();
    if (value.isEmpty) return;
    _handled = true;
    Navigator.of(context).pop(value);
  }

  void _onDetect(BarcodeCapture capture) {
    if (_handled || !mounted) return;
    final list = capture.barcodes;
    if (list.isEmpty) return;
    final raw = list.first.rawValue?.trim() ?? '';
    if (raw.isEmpty) return;
    _completeWith(raw);
  }

  Future<void> _manualEntry() async {
    final value = await showQrManualEntryDialog(context);
    if (value != null && value.isNotEmpty) {
      _completeWith(value);
    }
  }

  String _errorMessage(MobileScannerException error) {
    final code = error.errorCode;
    if (code == MobileScannerErrorCode.permissionDenied) {
      return 'Izin kamera ditolak. Aktifkan kamera di pengaturan perangkat.';
    }
    return error.errorDetails?.message ?? 'Kamera tidak dapat diakses.';
  }

  @override
  Widget build(BuildContext context) {
    final showActions = widget.showTorchActions && !kIsWeb;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        backgroundColor: widget.appBarBackgroundColor,
        actions: [
          IconButton(
            tooltip: 'Input manual',
            icon: const Icon(Icons.keyboard),
            onPressed: _manualEntry,
          ),
          if (showActions) ...[
            IconButton(
              icon: const Icon(Icons.flash_on),
              onPressed: () => _camera.toggleTorch(),
            ),
            IconButton(
              icon: const Icon(Icons.cameraswitch),
              onPressed: () => _camera.switchCamera(),
            ),
          ],
        ],
      ),
      body: MobileScanner(
        controller: _camera,
        onDetect: _onDetect,
        errorBuilder: (context, error) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.videocam_off, size: 48),
                  const SizedBox(height: 16),
                  Text(_errorMessage(error), textAlign: TextAlign.center),
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    onPressed: _manualEntry,
                    icon: const Icon(Icons.keyboard),
                    label: const Text('Input kode manual'),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _QrBatchScanPage extends StatefulWidget {
  const _QrBatchScanPage({
    required this.title,
    required this.showTorchActions,
    this.appBarBackgroundColor,
  });

  final String title;
  final bool showTorchActions;
  final Color? appBarBackgroundColor;

  @override
  State<_QrBatchScanPage> createState() => _QrBatchScanPageState();
}

class _QrBatchScanPageState extends State<_QrBatchScanPage> {
  static const _debounce = Duration(seconds: 2);

  final List<String> _codes = [];
  final Set<String> _seenKeys = {};
  final Map<String, DateTime> _lastDetect = {};
  late final MobileScannerController _camera;

  @override
  void initState() {
    super.initState();
    _camera = MobileScannerController(
      detectionSpeed: DetectionSpeed.normal,
      facing: CameraFacing.back,
    );
  }

  @override
  void dispose() {
    _camera.dispose();
    super.dispose();
  }

  String _dedupeKey(String raw) => raw.trim().toLowerCase();

  void _tryAdd(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return;
    final key = _dedupeKey(trimmed);
    final now = DateTime.now();
    final last = _lastDetect[key];
    if (last != null && now.difference(last) < _debounce) return;
    _lastDetect[key] = now;
    if (_seenKeys.contains(key)) return;
    setState(() {
      _seenKeys.add(key);
      _codes.add(trimmed);
    });
    HapticFeedback.lightImpact();
  }

  void _finish() {
    if (!mounted) return;
    Navigator.of(context).pop(_codes);
  }

  void _onDetect(BarcodeCapture capture) {
    if (!mounted) return;
    for (final b in capture.barcodes) {
      final raw = b.rawValue?.trim() ?? '';
      if (raw.isNotEmpty) _tryAdd(raw);
    }
  }

  Future<void> _manualEntry() async {
    final value = await showQrManualEntryDialog(context);
    if (value != null && value.isNotEmpty) _tryAdd(value);
  }

  String _errorMessage(MobileScannerException error) {
    final code = error.errorCode;
    if (code == MobileScannerErrorCode.permissionDenied) {
      return 'Izin kamera ditolak. Aktifkan kamera di pengaturan perangkat.';
    }
    return error.errorDetails?.message ?? 'Kamera tidak dapat diakses.';
  }

  @override
  Widget build(BuildContext context) {
    final showActions = widget.showTorchActions && !kIsWeb;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        backgroundColor: widget.appBarBackgroundColor,
        actions: [
          TextButton(
            onPressed: _codes.isEmpty ? null : _finish,
            child: Text('Selesai (${_codes.length})'),
          ),
          IconButton(
            tooltip: 'Input manual',
            icon: const Icon(Icons.keyboard),
            onPressed: _manualEntry,
          ),
          if (showActions) ...[
            IconButton(
              icon: const Icon(Icons.flash_on),
              onPressed: () => _camera.toggleTorch(),
            ),
            IconButton(
              icon: const Icon(Icons.cameraswitch),
              onPressed: () => _camera.switchCamera(),
            ),
          ],
        ],
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          MobileScanner(
            controller: _camera,
            onDetect: _onDetect,
            errorBuilder: (context, error) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.videocam_off, size: 48),
                      const SizedBox(height: 16),
                      Text(_errorMessage(error), textAlign: TextAlign.center),
                      const SizedBox(height: 24),
                      FilledButton.icon(
                        onPressed: _manualEntry,
                        icon: const Icon(Icons.keyboard),
                        label: const Text('Input kode manual'),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
              child: Material(
                color: Colors.black54,
                borderRadius: const BorderRadius.all(Radius.circular(8)),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _codes.isEmpty
                            ? 'Arahkan ke satu atau beberapa QR. Scan berulang tanpa tutup kamera.'
                            : '${_codes.length} kode terkumpul — scan lagi atau ketuk Selesai.',
                        style: const TextStyle(color: Colors.white, fontSize: 13),
                        textAlign: TextAlign.center,
                      ),
                      if (_codes.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        FilledButton(
                          onPressed: _finish,
                          child: Text('Selesai — proses ${_codes.length} kode'),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

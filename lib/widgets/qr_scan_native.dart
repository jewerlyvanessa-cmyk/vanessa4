import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:vanessa3/widgets/qr_scan_manual_entry.dart';

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

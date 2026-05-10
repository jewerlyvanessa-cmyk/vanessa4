import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart'
    if (dart.library.html) '../utils/mobile_scanner_stub.dart';

/// Buka layar scan QR satu kali (anti double-detect), nilai [trim].
/// Di web memakai stub (tanpa kamera). [showTorchActions]: lampu & ganti kamera (mobile/desktop native).
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
  MobileScannerController? _camera;

  @override
  void initState() {
    super.initState();
    if (widget.showTorchActions && !kIsWeb) {
      _camera = MobileScannerController();
    }
  }

  @override
  void dispose() {
    _camera?.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_handled || !mounted) return;
    final list = capture.barcodes;
    if (list.isEmpty) return;
    final raw = list.first.rawValue?.trim() ?? '';
    if (raw.isEmpty) return;
    _handled = true;
    Navigator.of(context).pop(raw);
  }

  @override
  Widget build(BuildContext context) {
    final showActions =
        widget.showTorchActions && !kIsWeb && _camera != null;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        backgroundColor: widget.appBarBackgroundColor,
        actions: [
          if (showActions) ...[
            IconButton(
              icon: const Icon(Icons.flash_on),
              onPressed: () => _camera!.toggleTorch(),
            ),
            IconButton(
              icon: const Icon(Icons.cameraswitch),
              onPressed: () => _camera!.switchCamera(),
            ),
          ],
        ],
      ),
      body: MobileScanner(
        controller: _camera,
        onDetect: _onDetect,
      ),
    );
  }
}

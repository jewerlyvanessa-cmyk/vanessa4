// Stub implementation for web platform
import 'package:flutter/material.dart';

/// Stub agar `ambil_page` / scanner lain bisa di-compile untuk web.
class MobileScannerController {
  void dispose() {}

  Future<void> toggleTorch() async {}

  Future<void> switchCamera() async {}
}

class MobileScanner extends StatelessWidget {
  final Function(BarcodeCapture)? onDetect;
  final MobileScannerController? controller;

  const MobileScanner({super.key, this.onDetect, this.controller});

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Text('QR Scanner not available on web platform'),
    );
  }
}

class Barcode {
  final String? rawValue;
  Barcode(this.rawValue);
}

class BarcodeCapture {
  final List<Barcode> barcodes;
  BarcodeCapture(this.barcodes);
}

// Stub implementation for web platform
import 'package:flutter/material.dart';

class MobileScanner extends StatelessWidget {
  final Function(BarcodeCapture)? onDetect;

  const MobileScanner({super.key, this.onDetect});

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Text('QR Scanner not available on web platform'),
    );
  }
}

class Barcode {
  final String rawValue;
  Barcode(this.rawValue);
}

class BarcodeCapture {
  final List<Barcode> barcodes;
  BarcodeCapture(this.barcodes);
}

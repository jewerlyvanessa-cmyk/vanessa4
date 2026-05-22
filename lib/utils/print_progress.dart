import 'package:flutter/material.dart';

/// Dialog ringan saat PDF/gambar sedang disiapin (perceived latency).
Future<T> runWithPrintProgress<T>(
  BuildContext context,
  Future<T> Function() action, {
  String message = 'Menyiapkan dokumen…',
}) async {
  if (!context.mounted) return action();
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => PopScope(
      canPop: false,
      child: AlertDialog(
        content: Row(
          children: [
            const CircularProgressIndicator(),
            const SizedBox(width: 20),
            Expanded(child: Text(message)),
          ],
        ),
      ),
    ),
  );
  try {
    return await action();
  } finally {
    if (context.mounted) {
      Navigator.of(context, rootNavigator: true).pop();
    }
  }
}

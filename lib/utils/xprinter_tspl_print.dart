import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vanessa3/utils/stock_item_qr_print.dart';
import 'package:vanessa3/utils/stock_label_tspl.dart';

const _channel = MethodChannel('com.example.vanessa3/label_print');
const _prefAddressKey = 'xprinter_bt_address';
const _prefNameKey = 'xprinter_bt_name';

bool get supportsTsplBluetoothPrint =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

class BondedBluetoothPrinter {
  const BondedBluetoothPrinter({required this.name, required this.address});

  final String name;
  final String address;

  factory BondedBluetoothPrinter.fromMap(Map<dynamic, dynamic> map) {
    return BondedBluetoothPrinter(
      name: (map['name'] ?? 'Printer').toString(),
      address: (map['address'] ?? '').toString(),
    );
  }
}

abstract final class XprinterTsplPrint {
  XprinterTsplPrint._();

  static bool _printInFlight = false;

  // ── Permission ────────────────────────────────────────────────────────────

  /// Tampilkan dialog sistem Android untuk meminta izin Bluetooth.
  /// Dipanggil HANYA sebagai recovery setelah operasi mengembalikan
  /// permission_denied — tidak proaktif agar tidak mengganggu pengguna
  /// Xiaomi/MIUI yang cache checkSelfPermission-nya tidak sinkron.
  static Future<bool> _askSystemPermission() async {
    try {
      final granted =
          await _channel.invokeMethod<bool>('requestBluetoothPermission');
      return granted == true;
    } on PlatformException {
      return false;
    }
  }

  /// Arahkan user ke Settings jika izin benar-benar tidak bisa diperoleh.
  static Future<void> _showSettingsDialog(BuildContext context) async {
    if (!context.mounted) return;
    final open = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Izin Bluetooth diperlukan'),
        content: const Text(
          'Aktifkan izin «Perangkat terdekat» untuk Vanessa:\n\n'
          'Pengaturan → Aplikasi → Vanessa → Izin '
          '→ Perangkat terdekat → Izinkan\n\n'
          'Setelah diizinkan, kembali dan coba cetak lagi.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Buka Pengaturan'),
          ),
        ],
      ),
    );
    if (open == true) {
      try {
        await _channel.invokeMethod<void>('openAppSettings');
      } catch (_) {}
    }
  }

  // ── List printer ──────────────────────────────────────────────────────────

  /// Ambil daftar printer yang sudah di-pair.
  /// Tidak ada pre-check permission — biarkan OS yang validasi.
  /// Lempar [PlatformException] dengan code 'permission_denied' jika gagal.
  static Future<List<BondedBluetoothPrinter>> _listBonded() async {
    final raw = await _channel.invokeMethod<List<dynamic>>(
      'listBondedBluetoothPrinters',
    );
    if (raw == null) return const [];
    return raw
        .whereType<Map>()
        .map(BondedBluetoothPrinter.fromMap)
        .where((p) => p.address.isNotEmpty)
        .toList();
  }

  // ── Saved printer preference ──────────────────────────────────────────────

  static Future<void> _savePrinter(BondedBluetoothPrinter printer) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefAddressKey, printer.address);
    await prefs.setString(_prefNameKey, printer.name);
  }

  static Future<BondedBluetoothPrinter?> loadSavedPrinter() async {
    final prefs = await SharedPreferences.getInstance();
    final address = prefs.getString(_prefAddressKey);
    if (address == null || address.isEmpty) return null;
    return BondedBluetoothPrinter(
      name: prefs.getString(_prefNameKey) ?? 'Printer',
      address: address,
    );
  }

  // ── Auto-posisi roll baru ─────────────────────────────────────────────────

  /// GAPDETECT: kalibrasi sensor gap roll (tanpa HOME — TSPL2 skip label).
  /// Gunakan SEKALI per ganti roll.
  static Future<void> autoPositionNewRoll(
    BuildContext context,
    BondedBluetoothPrinter printer,
  ) async {
    if (_printInFlight) {
      _snack(context, 'Tunggu cetak selesai sebelum posisi roll baru.');
      return;
    }
    _printInFlight = true;
    try {
      final ok = await _sendRawTspl(
        address: printer.address,
        data: StockLabelTspl.buildNewRollPositionJob(),
      );
      if (!context.mounted) return;
      if (ok) {
        _snack(
          context,
          'Posisi label pertama siap. Mulai cetak kapan saja.',
        );
      } else {
        _snack(context, 'Printer tidak merespons. Coba lagi.');
      }
    } on PlatformException catch (e) {
      if (!context.mounted) return;
      _snack(context, e.message ?? 'Gagal posisi roll baru: ${e.code}');
    } finally {
      _printInFlight = false;
    }
  }

  // ── Pick printer UI ───────────────────────────────────────────────────────

  static Future<BondedBluetoothPrinter?> pickPrinter(
    BuildContext context,
  ) async {
    if (!supportsTsplBluetoothPrint) {
      _snack(context, 'Cetak TSPL Bluetooth hanya tersedia di Android.');
      return null;
    }

    // Coba langsung tanpa pre-check permission.
    // Jika OS blokir (benar-benar tidak ada izin), baru minta izin sekali.
    List<BondedBluetoothPrinter> devices;
    try {
      devices = await _listBonded();
    } on PlatformException catch (e) {
      if (!context.mounted) return null;
      if (e.code == 'permission_denied') {
        // Izin belum diberikan di level OS → tampilkan dialog sistem sekali.
        final granted = await _askSystemPermission();
        if (!context.mounted) return null;
        if (!granted) {
          // User menolak dialog sistem → arahkan ke Settings.
          await _showSettingsDialog(context);
          return null;
        }
        // Retry setelah izin diberikan.
        try {
          devices = await _listBonded();
        } on PlatformException catch (e2) {
          if (!context.mounted) return null;
          if (e2.code == 'permission_denied') {
            await _showSettingsDialog(context);
          } else {
            _snack(context, e2.message ?? 'Gagal membaca printer Bluetooth.');
          }
          return null;
        }
      } else {
        _snack(context, e.message ?? 'Gagal membaca printer Bluetooth.');
        return null;
      }
    }

    if (!context.mounted) return null;

    if (devices.isEmpty) {
      _snack(
        context,
        'Tidak ada printer yang sudah di-pair.\n'
        'Pair XP-TT426B di Pengaturan → Bluetooth (PIN biasanya 0000).',
      );
      return null;
    }

    final saved = await loadSavedPrinter();
    if (!context.mounted) return null;

    return showModalBottomSheet<BondedBluetoothPrinter>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Text(
                'Pilih printer Bluetooth (XP-TT426B)',
                style: Theme.of(ctx).textTheme.titleSmall,
              ),
            ),
            for (final device in devices)
              ListTile(
                leading: const Icon(Icons.print_outlined),
                title: Text(device.name),
                subtitle: Text(device.address),
                trailing: saved?.address == device.address
                    ? const Icon(Icons.check_circle, color: Colors.green)
                    : null,
                onTap: () => Navigator.pop(ctx, device),
              ),
            const Divider(height: 1),
            // Tombol roll baru: EOP sekali untuk auto-posisi dari posisi mana pun.
            // Dilakukan SEKALI per ganti roll, setelah itu posisi otomatis.
            for (final device in devices)
              if (saved?.address == device.address)
                ListTile(
                  leading: const Icon(Icons.restart_alt, color: Colors.orange),
                  title: const Text('Posisikan Roll Baru'),
                  subtitle: const Text(
                    'Tekan jika baru ganti roll — printer akan cari '
                    'label pertama otomatis',
                  ),
                  onTap: () {
                    Navigator.pop(ctx);
                    autoPositionNewRoll(context, device);
                  },
                ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  // ── Print ─────────────────────────────────────────────────────────────────

  static Future<void> printLabels({
    required BuildContext context,
    required List<Map<String, dynamic>> items,
    required StockLabelPrintChoice format,
    BondedBluetoothPrinter? printer,
  }) async {
    if (!supportsTsplBluetoothPrint) {
      _snack(context, 'Cetak TSPL Bluetooth hanya tersedia di Android.');
      return;
    }

    final selected = printer ?? await pickPrinter(context);
    if (!context.mounted || selected == null) return;

    final labels = <({
      String payload,
      String titleLine,
      StockLabelPrintChoice format,
      String? weight,
      String? purity,
    })>[];

    for (final item in items) {
      final payload = stockItemQrPayload(item);
      if (payload.isEmpty) continue;
      final name = (item['name'] ?? '').toString().trim();
      labels.add((
        payload: payload,
        titleLine: name.isNotEmpty ? name : payload,
        format: format,
        weight: _formatWeight(item['weight']),
        purity: _formatPurity(item['purity']),
      ));
    }

    if (labels.isEmpty) {
      _snack(context, 'Tidak ada label valid untuk dicetak.');
      return;
    }

    try {
      if (_printInFlight) {
        _snack(
          context,
          'Cetak sedang berjalan. Tunggu printer selesai sebelum kirim lagi.',
        );
        return;
      }
      _printInFlight = true;

      if (!context.mounted) return;
      _snack(context, 'Mengirim ${labels.length} label ke ${selected.name}…');

      final bytes = StockLabelTspl.buildBatch(labels: labels);
      final ok = await _sendRawTspl(address: selected.address, data: bytes);

      if (ok != true) {
        throw const TsplPrintException(
          'Printer tidak merespons. Pastikan printer nyala, tidak pause, '
          'dan coba «Posisikan Roll Baru» jika baru ganti roll.',
        );
      }

      await _savePrinter(selected);
      if (!context.mounted) return;
      _snack(
        context,
        'Berhasil kirim ${labels.length} label ke ${selected.name} (TSPL).',
      );
    } on TsplPrintException catch (e) {
      if (context.mounted) _snack(context, e.message);
    } on PlatformException catch (e) {
      if (!context.mounted) return;
      if (e.code == 'permission_denied') {
        await _showSettingsDialog(context);
      } else {
        _snack(context, e.message ?? 'Gagal cetak TSPL: ${e.code}');
      }
    } finally {
      _printInFlight = false;
    }
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  static String? _formatWeight(dynamic raw) {
    if (raw == null) return null;
    final n = double.tryParse(raw.toString().trim());
    if (n == null || n <= 0) return null;
    if (n == n.roundToDouble()) return '${n.toInt()} g';
    return '${n.toStringAsFixed(2)} g';
  }

  static String? _formatPurity(dynamic raw) {
    final s = raw?.toString().trim() ?? '';
    return s.isEmpty ? null : s;
  }

  static void _snack(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  static Future<bool> _sendRawTspl({
    required String address,
    required Uint8List data,
  }) async {
    final ok = await _channel.invokeMethod<bool>(
      'printTsplBluetooth',
      <String, dynamic>{
        'address': address,
        'data': data,
      },
    );
    return ok == true;
  }
}

class TsplPrintException implements Exception {
  const TsplPrintException(this.message);
  final String message;

  @override
  String toString() => message;
}

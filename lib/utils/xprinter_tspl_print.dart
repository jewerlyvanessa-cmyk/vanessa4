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

  static String _prefGapKey(String address) => 'tspl_gap_mm_$address';
  static String _prefOffsetXKey(String address) => 'tspl_offset_x_mm_$address';
  static String _prefOffsetYKey(String address) => 'tspl_offset_y_mm_$address';
  static String _prefSpeedKey(String address) => 'tspl_speed_$address';
  static String _prefDensityKey(String address) => 'tspl_density_$address';

  static Future<StockLabelTsplSettings> _loadLabelSettings(
    BondedBluetoothPrinter printer,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    const d = StockLabelTsplSettings();
    final addr = printer.address;
    return StockLabelTsplSettings(
      gapMm: prefs.getDouble(_prefGapKey(addr)) ?? d.gapMm,
      calibrationOffsetXMm:
          prefs.getDouble(_prefOffsetXKey(addr)) ?? d.calibrationOffsetXMm,
      calibrationOffsetYMm:
          prefs.getDouble(_prefOffsetYKey(addr)) ?? d.calibrationOffsetYMm,
      speed: prefs.getInt(_prefSpeedKey(addr)) ?? d.speed,
      density: prefs.getInt(_prefDensityKey(addr)) ?? d.density,
    );
  }

  static Future<void> _saveLabelSettings(
    BondedBluetoothPrinter printer,
    StockLabelTsplSettings settings,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final addr = printer.address;
    await prefs.setDouble(_prefGapKey(addr), settings.gapMm);
    await prefs.setDouble(_prefOffsetXKey(addr), settings.calibrationOffsetXMm);
    await prefs.setDouble(_prefOffsetYKey(addr), settings.calibrationOffsetYMm);
    await prefs.setInt(_prefSpeedKey(addr), settings.speed);
    await prefs.setInt(_prefDensityKey(addr), settings.density);
  }

  static Future<Map<String, StockLabelTsplSettings>> _loadSettingsForDevices(
    List<BondedBluetoothPrinter> devices,
  ) async {
    if (devices.isEmpty) return const {};
    final prefs = await SharedPreferences.getInstance();
    const d = StockLabelTsplSettings();
    final out = <String, StockLabelTsplSettings>{};
    for (final p in devices) {
      final addr = p.address;
      out[addr] = StockLabelTsplSettings(
        gapMm: prefs.getDouble(_prefGapKey(addr)) ?? d.gapMm,
        calibrationOffsetXMm:
            prefs.getDouble(_prefOffsetXKey(addr)) ?? d.calibrationOffsetXMm,
        calibrationOffsetYMm:
            prefs.getDouble(_prefOffsetYKey(addr)) ?? d.calibrationOffsetYMm,
        speed: prefs.getInt(_prefSpeedKey(addr)) ?? d.speed,
        density: prefs.getInt(_prefDensityKey(addr)) ?? d.density,
      );
    }
    return out;
  }

  static String _fmtSettings(StockLabelTsplSettings s) {
    String mm(double v) => v.toStringAsFixed(1);
    return 'Gap ${mm(s.gapMm)} • OffX ${mm(s.calibrationOffsetXMm)} • '
        'OffY ${mm(s.calibrationOffsetYMm)} • '
        'D${s.density} • S${s.speed}';
  }

  static Future<void> editPrinterLabelSettings(
    BuildContext context,
    BondedBluetoothPrinter printer,
  ) async {
    final current = await _loadLabelSettings(printer);
    if (!context.mounted) return;

    final gapCtrl = TextEditingController(text: current.gapMm.toString());
    final offXCtrl =
        TextEditingController(text: current.calibrationOffsetXMm.toString());
    final offYCtrl =
        TextEditingController(text: current.calibrationOffsetYMm.toString());
    final speedCtrl = TextEditingController(text: current.speed.toString());
    final densityCtrl = TextEditingController(text: current.density.toString());

    StockLabelTsplSettings? result;
    try {
      result = await showDialog<StockLabelTsplSettings>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('Pengaturan Label (${printer.name})'),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Setelan ini khusus untuk printer ini (berdasarkan alamat Bluetooth).',
                  style: TextStyle(fontSize: 12, color: Colors.black54),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: gapCtrl,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'Gap (mm)',
                    hintText: 'mis. 3.0',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: offXCtrl,
                        keyboardType:
                            const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(
                          labelText: 'Offset X (mm)',
                          hintText: 'mis. 0.0',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: offYCtrl,
                        keyboardType:
                            const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(
                          labelText: 'Offset Y (mm)',
                          hintText: 'mis. 3.5',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: speedCtrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Speed',
                          hintText: 'mis. 4',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: densityCtrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Density',
                          hintText: 'mis. 8',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                const Text(
                  'Tip: setelah ubah Offset/Gap, jalankan «Pre-check» lalu cetak 1 label untuk verifikasi.',
                  style: TextStyle(fontSize: 12, color: Colors.black54),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Batal'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, const StockLabelTsplSettings()),
              child: const Text('Reset default'),
            ),
            FilledButton(
              onPressed: () {
                double? parseD(String s) => double.tryParse(s.trim());
                int? parseI(String s) => int.tryParse(s.trim());

                final gap = parseD(gapCtrl.text);
                final offX = parseD(offXCtrl.text);
                final offY = parseD(offYCtrl.text);
                final speed = parseI(speedCtrl.text);
                final density = parseI(densityCtrl.text);

                if (gap == null ||
                    offX == null ||
                    offY == null ||
                    speed == null ||
                    density == null) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Input tidak valid.')),
                  );
                  return;
                }

                final safeGap = gap.clamp(0.5, 10.0).toDouble();
                final safeSpeed = speed.clamp(1, 8);
                final safeDensity = density.clamp(0, 15);

                Navigator.pop(
                  ctx,
                  StockLabelTsplSettings(
                    gapMm: safeGap,
                    speed: safeSpeed,
                    density: safeDensity,
                    calibrationOffsetXMm: offX,
                    calibrationOffsetYMm: offY,
                  ),
                );
              },
              child: const Text('Simpan'),
            ),
          ],
        ),
      );
    } finally {
      gapCtrl.dispose();
      offXCtrl.dispose();
      offYCtrl.dispose();
      speedCtrl.dispose();
      densityCtrl.dispose();
    }

    if (!context.mounted || result == null) return;
    await _saveLabelSettings(printer, result);
    if (!context.mounted) return;
    _snack(context, 'Pengaturan label tersimpan untuk ${printer.name}.');
  }

  static Future<void> _runToolAndCloseSheet({
    required BuildContext sheetContext,
    required BuildContext appContext,
    required Future<void> Function() action,
  }) async {
    Navigator.pop(sheetContext);
    await Future<void>.delayed(const Duration(milliseconds: 80));
    if (!appContext.mounted) return;
    await action();
  }

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
      final settings = await _loadLabelSettings(printer);
      final ok = await _sendRawTspl(
        address: printer.address,
        data: StockLabelTspl.buildNewRollPositionJob(settings: settings),
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

  // ── Diagnostics / calibration (TSPL) ──────────────────────────────────────

  /// Pre-check posisi label sebelum cetak (GAPDETECT tanpa PRINT).
  ///
  /// Gunakan jika printer lama idle / baru tarik label / posisi ragu,
  /// terutama untuk label kecil agar job pertama tidak meleset.
  static Future<void> prePrintCheck(
    BuildContext context,
    BondedBluetoothPrinter printer,
  ) async {
    if (_printInFlight) {
      _snack(context, 'Tunggu cetak selesai sebelum pre-check.');
      return;
    }
    _printInFlight = true;
    try {
      final settings = await _loadLabelSettings(printer);
      final ok = await _sendRawTspl(
        address: printer.address,
        data: StockLabelTspl.buildPrePrintCheckJob(settings: settings),
      );
      if (!context.mounted) return;
      if (ok) {
        _snack(context, 'Pre-check selesai. Label siap untuk dicetak.');
      } else {
        _snack(context, 'Printer tidak merespons. Coba lagi.');
      }
    } on PlatformException catch (e) {
      if (!context.mounted) return;
      _snack(context, e.message ?? 'Gagal pre-check: ${e.code}');
    } finally {
      _printInFlight = false;
    }
  }

  /// Kalibrasi gap sensor (GAPDETECT) — sebaiknya **sekali** per ganti roll
  /// atau saat printer baru dinyalakan.
  ///
  /// Catatan: proses ini normalnya membuang beberapa label kosong.
  static Future<void> calibrateGapSensor(
    BuildContext context,
    BondedBluetoothPrinter printer,
  ) async {
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Kalibrasi gap sensor?'),
        content: const Text(
          'Kalibrasi gap akan membuat printer bergerak dan biasanya membuang beberapa label kosong.\n\n'
          'Lanjutkan?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Kalibrasi'),
          ),
        ],
      ),
    );
    if (go != true || !context.mounted) return;

    if (_printInFlight) {
      _snack(context, 'Tunggu cetak selesai sebelum kalibrasi gap.');
      return;
    }
    _printInFlight = true;
    try {
      final settings = await _loadLabelSettings(printer);
      final ok = await _sendRawTspl(
        address: printer.address,
        data: StockLabelTspl.buildGapCalibrationJob(settings: settings),
      );
      if (!context.mounted) return;
      if (ok) {
        _snack(
          context,
          'Kalibrasi gap dikirim. Tunggu printer selesai bergerak, lalu coba cetak 1 label.',
        );
      } else {
        _snack(context, 'Printer tidak merespons. Coba lagi.');
      }
    } on PlatformException catch (e) {
      if (!context.mounted) return;
      _snack(context, e.message ?? 'Gagal kalibrasi gap: ${e.code}');
    } finally {
      _printInFlight = false;
    }
  }

  /// Cetak sample kotak penanda untuk mengecek offset (REFERENCE) terhadap label fisik.
  ///
  /// Gunakan jika konten sering kepotong / terlalu naik-turun.
  static Future<void> printCalibrationSample(
    BuildContext context,
    BondedBluetoothPrinter printer,
  ) async {
    if (_printInFlight) {
      _snack(context, 'Tunggu cetak selesai sebelum cetak sample kalibrasi.');
      return;
    }
    _printInFlight = true;
    try {
      final settings = await _loadLabelSettings(printer);
      final ok = await _sendRawTspl(
        address: printer.address,
        data: StockLabelTspl.buildCalibrationSample(settings: settings),
      );
      if (!context.mounted) return;
      if (ok) {
        _snack(context, 'Sample kalibrasi dikirim. Cek posisi kotak/tepi di label.');
      } else {
        _snack(context, 'Printer tidak merespons. Coba lagi.');
      }
    } on PlatformException catch (e) {
      if (!context.mounted) return;
      _snack(context, e.message ?? 'Gagal cetak sample: ${e.code}');
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

    final settingsByAddr = await _loadSettingsForDevices(devices);
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
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(device.address),
                    const SizedBox(height: 2),
                    Text(
                      _fmtSettings(
                        settingsByAddr[device.address] ??
                            const StockLabelTsplSettings(),
                      ),
                      style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                            color: Theme.of(ctx)
                                .colorScheme
                                .onSurfaceVariant
                                .withValues(alpha: 0.85),
                            height: 1.2,
                          ),
                    ),
                  ],
                ),
                trailing: saved?.address == device.address
                    ? const Icon(Icons.check_circle, color: Colors.green)
                    : PopupMenuButton<String>(
                        tooltip: 'Tools',
                        onSelected: (value) async {
                          if (value == 'new_roll') {
                            await _runToolAndCloseSheet(
                              sheetContext: ctx,
                              appContext: context,
                              action: () => autoPositionNewRoll(context, device),
                            );
                          } else if (value == 'precheck') {
                            await _runToolAndCloseSheet(
                              sheetContext: ctx,
                              appContext: context,
                              action: () => prePrintCheck(context, device),
                            );
                          } else if (value == 'gap_cal') {
                            await _runToolAndCloseSheet(
                              sheetContext: ctx,
                              appContext: context,
                              action: () => calibrateGapSensor(context, device),
                            );
                          } else if (value == 'sample') {
                            await _runToolAndCloseSheet(
                              sheetContext: ctx,
                              appContext: context,
                              action: () => printCalibrationSample(context, device),
                            );
                          } else if (value == 'settings') {
                            await _runToolAndCloseSheet(
                              sheetContext: ctx,
                              appContext: context,
                              action: () => editPrinterLabelSettings(context, device),
                            );
                          }
                        },
                        itemBuilder: (_) => const [
                          PopupMenuItem(
                            value: 'new_roll',
                            child: ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: Icon(Icons.restart_alt, color: Colors.orange),
                              title: Text('Posisikan Roll Baru'),
                            ),
                          ),
                          PopupMenuItem(
                            value: 'precheck',
                            child: ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: Icon(Icons.check_circle_outline),
                              title: Text('Pre-check sebelum cetak'),
                            ),
                          ),
                          PopupMenuItem(
                            value: 'gap_cal',
                            child: ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: Icon(Icons.tune, color: Colors.blueGrey),
                              title: Text('Kalibrasi Gap Sensor'),
                            ),
                          ),
                          PopupMenuItem(
                            value: 'sample',
                            child: ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: Icon(Icons.crop_square, color: Colors.teal),
                              title: Text('Cetak Sample Kalibrasi'),
                            ),
                          ),
                          PopupMenuItem(
                            value: 'settings',
                            child: ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: Icon(Icons.settings),
                              title: Text('Pengaturan Label…'),
                            ),
                          ),
                        ],
                      ),
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
            for (final device in devices)
              if (saved?.address == device.address) ...[
                ListTile(
                  leading: const Icon(Icons.settings),
                  title: const Text('Pengaturan Label…'),
                  subtitle: const Text('Gap/offset/density/speed untuk printer ini'),
                  onTap: () {
                    Navigator.pop(ctx);
                    editPrinterLabelSettings(context, device);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.check_circle_outline),
                  title: const Text('Pre-check sebelum cetak'),
                  subtitle: const Text('Cek posisi label via sensor (tanpa cetak)'),
                  onTap: () {
                    Navigator.pop(ctx);
                    prePrintCheck(context, device);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.tune, color: Colors.blueGrey),
                  title: const Text('Kalibrasi Gap Sensor'),
                  subtitle: const Text('Sekali per ganti roll/printer nyala (bisa buang beberapa label)'),
                  onTap: () {
                    Navigator.pop(ctx);
                    calibrateGapSensor(context, device);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.crop_square, color: Colors.teal),
                  title: const Text('Cetak Sample Kalibrasi'),
                  subtitle: const Text('Kotak/marker untuk cek offset & area cetak'),
                  onTap: () {
                    Navigator.pop(ctx);
                    printCalibrationSample(context, device);
                  },
                ),
              ],
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

      final settings = await _loadLabelSettings(selected);

      // Jangan GAPDETECT otomatis sebelum cetak — membuang label kosong antar sesi
      // jika posisi sudah benar. Gunakan «Pre-check» manual dari menu printer.

      final bytes = StockLabelTspl.buildBatch(labels: labels, settings: settings);
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

import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Ikon konsisten antar-dashboard untuk fungsi menu yang sama.
abstract final class DashboardMenuIcons {
  DashboardMenuIcons._();

  /// Daftar / kelola pelanggan (`CustomersPage`, `/customers`).
  static const IconData pelanggan = Icons.people;

  /// Laporan (penjualan, stok, kasir, teknisi, workshop, …).
  static const IconData laporan = Icons.assessment;

  /// Karyawan cabang, user internal, manajemen user sistem (bukan pelanggan).
  static const IconData kelolaPengguna = Icons.manage_accounts;

  /// Stok global / ringkasan inventori.
  static const IconData stokGlobal = Icons.inventory;
}

/// Satu item menu modul (ikon + label + aksi).
class ModuleMenuEntry {
  const ModuleMenuEntry({
    required this.icon,
    required this.label,
    required this.iconColor,
    this.onTap,
    this.badgeCount,
    this.outlined = false,
  });

  final IconData icon;
  final String label;
  final Color iconColor;
  final VoidCallback? onTap;
  /// Jika > 0, ditampilkan badge merah (mis. antrian teknisi).
  final int? badgeCount;
  /// Border halus seperti menu Teknisi.
  final bool outlined;
}

/// Grid menu adaptif: layar lebar/web → lebih banyak kolom, ubin lebih pendek,
/// ikon & teks sedikit lebih kecil agar konten di bawahnya terlihat.
class ModuleMenuGrid extends StatelessWidget {
  const ModuleMenuGrid({
    super.key,
    required this.entries,
    this.shrinkWrap = true,
    this.physics,
    this.minCrossAxisCount = 3,
    this.maxCrossAxisCount = 10,
  });

  final List<ModuleMenuEntry> entries;
  final bool shrinkWrap;
  final ScrollPhysics? physics;
  final int minCrossAxisCount;
  final int maxCrossAxisCount;

  static int _crossAxisCount(
    double maxWidth, {
    required int minCols,
    required int maxCols,
  }) {
    final n = (maxWidth / 104).floor();
    if (n < minCols) return minCols;
    if (n > maxCols) return maxCols;
    return n;
  }

  static double _aspectRatio(double maxWidth) {
    if (maxWidth >= 960) return 1.28;
    if (maxWidth >= 720) return 1.15;
    if (maxWidth >= 520) return 1.0;
    if (maxWidth >= 400) return 0.88;
    return 0.78;
  }

  static double _spacing(double maxWidth) =>
      maxWidth >= 720 ? 8 : (maxWidth >= 420 ? 10 : 12);

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final cols = _crossAxisCount(
          w,
          minCols: minCrossAxisCount,
          maxCols: maxCrossAxisCount,
        );
        final ratio = _aspectRatio(w);
        final spacing = _spacing(w);

        return GridView.count(
          shrinkWrap: shrinkWrap,
          physics: physics ??
              (shrinkWrap
                  ? const NeverScrollableScrollPhysics()
                  : const AlwaysScrollableScrollPhysics()),
          crossAxisCount: cols,
          crossAxisSpacing: spacing,
          mainAxisSpacing: spacing,
          childAspectRatio: ratio,
          children: entries.map((e) => ModuleMenuTile(entry: e)).toList(),
        );
      },
    );
  }
}

class ModuleMenuTile extends StatelessWidget {
  const ModuleMenuTile({
    super.key,
    required this.entry,
  });

  final ModuleMenuEntry entry;

  String _twoLineLabel(String text) {
    final words =
        text.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    if (words.length <= 1) return text;
    final mid = (words.length / 2).ceil();
    final first = words.sublist(0, mid).join(' ');
    final second = words.sublist(mid).join(' ');
    if (second.isEmpty) return first;
    return '$first\n$second';
  }

  @override
  Widget build(BuildContext context) {
    final badge = entry.badgeCount;
    final showBadge = badge != null && badge > 0;

    return LayoutBuilder(
      builder: (context, constraints) {
        final cellW = constraints.maxWidth;
        final cellH = constraints.maxHeight;
        final shortSide = math.min(cellW, cellH);
        final isTiny = shortSide < 76;

        final hPad = (cellW * 0.06).clamp(4.0, 10.0);
        final vPad = (cellH * 0.06).clamp(4.0, 12.0);
        final innerW = math.max(0.0, cellW - 2 * hPad);
        final innerH = math.max(0.0, cellH - 2 * vPad);

        final fontSize = (shortSide * 0.11).clamp(9.0, 12.5);
        final gap = math.max(3.0, shortSide * 0.035);
        final labelReserve = fontSize * 2.9 + gap;
        final spaceForIcon = math.max(0.0, innerH - labelReserve);
        final iconFromHeight = spaceForIcon * 0.78;
        final iconFromWidth = innerW * 0.52;
        final iconSize = math.min(iconFromHeight, iconFromWidth).clamp(18.0, 40.0);

        final badgeSize = isTiny ? 16.0 : 19.0;
        final badgeFont = isTiny ? 8.5 : 9.5;

        return Material(
          color: entry.iconColor.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(10),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: entry.onTap,
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                border: entry.outlined
                    ? Border.all(
                        color: entry.iconColor.withValues(alpha: 0.22),
                        width: 1,
                      )
                    : null,
              ),
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: hPad, vertical: vPad),
                child: Stack(
                  fit: StackFit.expand,
                  clipBehavior: Clip.none,
                  children: [
                    Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Icon(
                            entry.icon,
                            size: iconSize,
                            color: entry.iconColor,
                          ),
                          SizedBox(height: gap),
                          SizedBox(
                            width: innerW,
                            child: Text(
                              _twoLineLabel(entry.label),
                              textAlign: TextAlign.center,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                    fontSize: fontSize,
                                    fontWeight: FontWeight.w600,
                                    height: 1.12,
                                  ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (showBadge)
                      Positioned(
                        top: 0,
                        right: 0,
                        child: Container(
                          padding: const EdgeInsets.all(2),
                          decoration: const BoxDecoration(
                            color: Colors.red,
                            shape: BoxShape.circle,
                          ),
                          constraints: BoxConstraints(
                            minWidth: badgeSize,
                            minHeight: badgeSize,
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            badge.toString(),
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: badgeFont,
                              fontWeight: FontWeight.bold,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

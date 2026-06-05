import 'package:flutter/material.dart';
import 'package:vanessa3/modules/common/logic/stock_opname_item_utils.dart';
import 'package:vanessa3/modules/common/logic/stock_opname_types.dart';
import 'package:vanessa3/shared_widgets/stock_status_filter_summary_header.dart';
import 'package:vanessa3/utils/branch_types.dart';

class StockOpnameBranchPicker extends StatelessWidget {
  const StockOpnameBranchPicker({
    super.key,
    required this.branches,
    required this.selectedBranchId,
    required this.onChanged,
  });

  final List<Map<String, dynamic>> branches;
  final String? selectedBranchId;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    if (branches.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: DropdownButtonFormField<String>(
        initialValue: selectedBranchId,
        decoration: const InputDecoration(
          labelText: 'Cabang',
          border: OutlineInputBorder(),
        ),
        items: [
          for (final b in branches)
            DropdownMenuItem(
              value: (b['branch_id'] ?? '').toString(),
              child: Text(
                '${(b['alias'] ?? b['name'] ?? b['branch_id'] ?? '').toString()} · ${branchTypeLabel(b['branch_type']?.toString())}',
              ),
            ),
        ],
        onChanged: onChanged,
      ),
    );
  }
}

class StockOpnameScanBar extends StatelessWidget {
  const StockOpnameScanBar({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.onSubmitted,
    required this.onOpenScanner,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onSubmitted;
  final VoidCallback onOpenScanner;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              focusNode: focusNode,
              autofocus: true,
              textInputAction: TextInputAction.done,
              decoration: const InputDecoration(
                labelText: 'Scan / ketik kode barang',
                hintText: 'KB001, scan QR…',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.qr_code_2),
                isDense: true,
              ),
              onSubmitted: onSubmitted,
            ),
          ),
          const SizedBox(width: 8),
          IconButton.filled(
            tooltip: 'Scan batch — beberapa QR tanpa tutup kamera',
            onPressed: onOpenScanner,
            icon: const Icon(Icons.qr_code_scanner),
          ),
        ],
      ),
    );
  }
}

class StockOpnameProgressCard extends StatelessWidget {
  const StockOpnameProgressCard({
    super.key,
    required this.total,
    required this.verified,
    required this.pending,
    required this.missingCount,
    required this.pendingCorrectionCount,
  });

  final int total;
  final int verified;
  final int pending;
  final int missingCount;
  final int pendingCorrectionCount;

  @override
  Widget build(BuildContext context) {
    final progress = total > 0 ? verified / total : 0.0;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Progress opname',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                  ),
                  Text(
                    '$verified / $total',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(value: progress, minHeight: 8),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  _StatChip(label: 'Terverifikasi', count: verified, color: Colors.green),
                  _StatChip(label: 'Belum scan', count: pending, color: Colors.orange),
                  if (missingCount > 0)
                    _StatChip(label: 'Hilang', count: missingCount, color: Colors.red),
                  if (pendingCorrectionCount > 0)
                    _StatChip(
                      label: 'Akan dikoreksi',
                      count: pendingCorrectionCount,
                      color: Colors.red,
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  const _StatChip({
    required this.label,
    required this.count,
    required this.color,
  });

  final String label;
  final int count;
  final MaterialColor color;

  @override
  Widget build(BuildContext context) {
    return Chip(
      avatar: CircleAvatar(
        backgroundColor: color.shade100,
        child: Text(
          '$count',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.bold,
            color: color.shade800,
          ),
        ),
      ),
      label: Text(label, style: const TextStyle(fontSize: 12)),
      visualDensity: VisualDensity.compact,
    );
  }
}

class StockOpnameRecentScans extends StatelessWidget {
  const StockOpnameRecentScans({
    super.key,
    required this.recentVerified,
    required this.onUnverify,
  });

  final List<Map<String, dynamic>> recentVerified;
  final ValueChanged<String> onUnverify;

  @override
  Widget build(BuildContext context) {
    if (recentVerified.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Baru discan', style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final m in recentVerified.take(6))
                InputChip(
                  avatar: const Icon(Icons.check, size: 16, color: Colors.green),
                  label: Text(
                    StockOpnameItemUtils.itemCode(m),
                    style: const TextStyle(fontSize: 12),
                  ),
                  onDeleted: () =>
                      onUnverify(StockOpnameItemUtils.itemIdStr(m)),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class StockOpnameListToggle extends StatelessWidget {
  const StockOpnameListToggle({
    super.key,
    required this.listView,
    required this.pendingCount,
    required this.verifiedCount,
    required this.missingCount,
    required this.totalCount,
    required this.onChanged,
  });

  final StockOpnameListView listView;
  final int pendingCount;
  final int verifiedCount;
  final int missingCount;
  final int totalCount;
  final ValueChanged<StockOpnameListView> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SegmentedButton<StockOpnameListView>(
          segments: [
            ButtonSegment(
              value: StockOpnameListView.pending,
              label: Text('Belum ($pendingCount)'),
              icon: const Icon(Icons.pending_actions, size: 18),
            ),
            ButtonSegment(
              value: StockOpnameListView.verified,
              label: Text('Sudah ($verifiedCount)'),
              icon: const Icon(Icons.check_circle_outline, size: 18),
            ),
            ButtonSegment(
              value: StockOpnameListView.missing,
              label: Text('Hilang ($missingCount)'),
              icon: const Icon(Icons.not_interested, size: 18),
            ),
            ButtonSegment(
              value: StockOpnameListView.all,
              label: Text('Semua ($totalCount)'),
              icon: const Icon(Icons.list, size: 18),
            ),
          ],
          selected: {listView},
          onSelectionChanged: (s) => onChanged(s.first),
        ),
      ),
    );
  }
}

class StockOpnameItemTile extends StatelessWidget {
  const StockOpnameItemTile({
    super.key,
    required this.item,
    required this.verified,
    required this.missing,
    required this.opnameStatus,
    required this.onMarkMissing,
    required this.onUnmarkMissing,
    required this.onUnverify,
    required this.onVerify,
    required this.onTap,
  });

  final Map<String, dynamic> item;
  final bool verified;
  final bool missing;
  final String opnameStatus;
  final VoidCallback onMarkMissing;
  final VoidCallback onUnmarkMissing;
  final VoidCallback onUnverify;
  final VoidCallback onVerify;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final code = StockOpnameItemUtils.itemCode(item);
    final name = (item['name'] ?? '-').toString();
    final status = (item['status'] ?? '').toString();

    Color avatarBg;
    IconData avatarIcon;
    Color avatarColor;
    if (missing) {
      avatarBg = Colors.red.shade50;
      avatarIcon = Icons.close;
      avatarColor = Colors.red.shade700;
    } else if (verified) {
      avatarBg = Colors.green.shade50;
      avatarIcon = Icons.check;
      avatarColor = Colors.green.shade700;
    } else {
      avatarBg = Colors.grey.shade100;
      avatarIcon = Icons.inventory_2_outlined;
      avatarColor = Colors.grey.shade600;
    }

    return ListTile(
      dense: true,
      leading: CircleAvatar(
        radius: 18,
        backgroundColor: avatarBg,
        child: Icon(avatarIcon, size: 20, color: avatarColor),
      ),
      title: Text(
        code.isEmpty ? name : code,
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
      subtitle: Text(
        missing
            ? '$name · Opname: Hilang'
            : verified
                ? '$name · Opname: Terverifikasi'
                : '$name · Opname: $opnameStatus · ${stockItemStatusLabel(status)}',
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!verified && !missing)
            IconButton(
              tooltip: 'Tandai hilang',
              icon: Icon(Icons.not_interested, size: 20, color: Colors.red.shade700),
              onPressed: onMarkMissing,
            ),
          if (missing)
            IconButton(
              tooltip: 'Batalkan tanda hilang',
              icon: const Icon(Icons.undo, size: 20),
              onPressed: onUnmarkMissing,
            )
          else if (verified)
            IconButton(
              tooltip: 'Batalkan verifikasi',
              icon: const Icon(Icons.undo, size: 20),
              onPressed: onUnverify,
            )
          else
            IconButton.filledTonal(
              tooltip: 'Tandai ditemukan',
              icon: const Icon(Icons.check, size: 20),
              onPressed: onVerify,
            ),
        ],
      ),
      onTap: onTap,
    );
  }
}

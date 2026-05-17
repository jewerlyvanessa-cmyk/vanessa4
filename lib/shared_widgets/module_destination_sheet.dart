import 'package:flutter/material.dart';

/// Satu tujuan di sheet pemilihan menu (mis. sub-halaman stok / laporan).
class ModuleDestinationOption {
  const ModuleDestinationOption({
    required this.label,
    required this.icon,
    required this.onTap,
    this.subtitle,
    this.iconColor,
  });

  final String label;
  final String? subtitle;
  final IconData icon;
  final Color? iconColor;
  final VoidCallback onTap;
}

/// Sheet ringkas untuk menggabungkan beberapa menu terkait jadi satu tile dashboard.
Future<void> showModuleDestinationSheet(
  BuildContext context, {
  required String title,
  required List<ModuleDestinationOption> options,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                title,
                style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
              ),
              const SizedBox(height: 8),
              ...options.map((opt) {
                return ListTile(
                  leading: Icon(opt.icon, color: opt.iconColor),
                  title: Text(opt.label),
                  subtitle: opt.subtitle == null
                      ? null
                      : Text(
                          opt.subtitle!,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                  onTap: () {
                    Navigator.pop(ctx);
                    opt.onTap();
                  },
                );
              }),
            ],
          ),
        ),
      );
    },
  );
}

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// Batas hari inklusif, selaras backend (`/payments/daily-summary`, order dashboard).
const int kManagerReportMaxRangeDays = 93;

DateTime managerReportDateOnly(DateTime d) =>
    DateTime(d.year, d.month, d.day);

bool managerReportSameCalendarDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

String managerReportIsoDate(DateTime d) {
  final x = managerReportDateOnly(d);
  final y = x.year.toString().padLeft(4, '0');
  final m = x.month.toString().padLeft(2, '0');
  final day = x.day.toString().padLeft(2, '0');
  return '$y-$m-$day';
}

/// Query untuk `/payments/daily-summary` dan `/api/dashboard/order-today`.
Map<String, String> managerReportPeriodQueryParams(
  DateTime start,
  DateTime end,
) {
  final s = managerReportDateOnly(start);
  final e = managerReportDateOnly(end);
  if (managerReportSameCalendarDay(s, e)) {
    return {'date': managerReportIsoDate(s)};
  }
  return {
    'date_from': managerReportIsoDate(s),
    'date_to': managerReportIsoDate(e),
  };
}

String managerReportPeriodTitle(
  DateTime start,
  DateTime end,
) {
  final s = managerReportDateOnly(start);
  final e = managerReportDateOnly(end);
  if (managerReportSameCalendarDay(s, e)) {
    return DateFormat('EEEE, dd MMM yyyy', 'id_ID').format(s);
  }
  final a = DateFormat('dd MMM yyyy', 'id_ID').format(s);
  final b = DateFormat('dd MMM yyyy', 'id_ID').format(e);
  return '$a – $b';
}

String managerReportPeriodShortSubtitle(
  DateTime start,
  DateTime end,
) {
  final s = managerReportDateOnly(start);
  final e = managerReportDateOnly(end);
  if (managerReportSameCalendarDay(s, e)) {
    return 'Satu hari';
  }
  final days = e.difference(s).inDays + 1;
  return 'Rentang $days hari';
}

class ManagerReportPeriodSelector extends StatelessWidget {
  const ManagerReportPeriodSelector({
    super.key,
    required this.rangeMode,
    required this.rangeStart,
    required this.rangeEnd,
    required this.onRangeModeChanged,
    required this.onPeriodChanged,
  });

  final bool rangeMode;
  final DateTime rangeStart;
  final DateTime rangeEnd;
  final ValueChanged<bool> onRangeModeChanged;
  final void Function(DateTime start, DateTime end) onPeriodChanged;

  static final DateFormat _dfDay = DateFormat('dd MMM yyyy', 'id_ID');

  Future<void> _pickRange(BuildContext context) async {
    final now = DateTime.now();
    final first = DateTime(now.year - 1);
    final last = DateTime(now.year, now.month, now.day);
    final s0 = managerReportDateOnly(rangeStart);
    final e0 = managerReportDateOnly(rangeEnd);
    final picked = await showDateRangePicker(
      context: context,
      firstDate: first,
      lastDate: last,
      initialDateRange: DateTimeRange(start: s0, end: e0),
      locale: const Locale('id', 'ID'),
    );
    if (picked == null) return;
    var s = managerReportDateOnly(picked.start);
    var e = managerReportDateOnly(picked.end);
    final span = e.difference(s).inDays + 1;
    if (span > kManagerReportMaxRangeDays) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Maksimal $kManagerReportMaxRangeDays hari (dipilih $span hari).',
          ),
        ),
      );
      return;
    }
    onPeriodChanged(s, e);
  }

  Future<void> _pickSingleDay(BuildContext context) async {
    final now = DateTime.now();
    final first = DateTime(now.year - 1);
    final last = DateTime(now.year, now.month, now.day);
    final cur = managerReportDateOnly(rangeStart);
    final picked = await showDatePicker(
      context: context,
      initialDate: cur,
      firstDate: first,
      lastDate: last,
      locale: const Locale('id', 'ID'),
    );
    if (picked == null) return;
    final d = managerReportDateOnly(picked);
    onPeriodChanged(d, d);
  }

  void _shiftSingleDay(int deltaDays) {
    final base = managerReportDateOnly(rangeStart);
    final next = base.add(Duration(days: deltaDays));
    final today = managerReportDateOnly(DateTime.now());
    if (next.isAfter(today)) return;
    onPeriodChanged(next, next);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final today = managerReportDateOnly(DateTime.now());
    final start = managerReportDateOnly(rangeStart);
    final end = managerReportDateOnly(rangeEnd);
    final canStepForward = !rangeMode && start.isBefore(today);

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment<bool>(
                  value: false,
                  label: Text('Satu hari'),
                  icon: Icon(Icons.today_outlined, size: 18),
                ),
                ButtonSegment<bool>(
                  value: true,
                  label: Text('Rentang'),
                  icon: Icon(Icons.date_range, size: 18),
                ),
              ],
              selected: {rangeMode},
              onSelectionChanged: (set) {
                final v = set.first;
                if (v == rangeMode) return;
                onRangeModeChanged(v);
                if (!v) {
                  final d = managerReportDateOnly(rangeStart);
                  onPeriodChanged(d, d);
                }
              },
            ),
            const SizedBox(height: 10),
            if (!rangeMode)
              Row(
                children: [
                  IconButton(
                    tooltip: 'Hari sebelumnya',
                    onPressed: () => _shiftSingleDay(-1),
                    icon: const Icon(Icons.chevron_left),
                  ),
                  Expanded(
                    child: InkWell(
                      onTap: () => _pickSingleDay(context),
                      borderRadius: BorderRadius.circular(8),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Text(
                          _dfDay.format(start),
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: cs.primary,
                          ),
                        ),
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Hari berikutnya',
                    onPressed:
                        canStepForward ? () => _shiftSingleDay(1) : null,
                    icon: const Icon(Icons.chevron_right),
                  ),
                  IconButton(
                    tooltip: 'Pilih tanggal',
                    onPressed: () => _pickSingleDay(context),
                    icon: const Icon(Icons.calendar_month_outlined),
                  ),
                ],
              )
            else
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  OutlinedButton.icon(
                    onPressed: () => _pickRange(context),
                    icon: const Icon(Icons.edit_calendar_outlined, size: 20),
                    label: Text(
                      '${_dfDay.format(start)} – ${_dfDay.format(end)}',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    alignment: WrapAlignment.center,
                    children: [
                      ActionChip(
                        label: const Text('7 hari ke belakang'),
                        onPressed: () {
                          final t = today;
                          onPeriodChanged(t.subtract(const Duration(days: 6)), t);
                        },
                      ),
                      ActionChip(
                        label: const Text('30 hari ke belakang'),
                        onPressed: () {
                          final t = today;
                          onPeriodChanged(t.subtract(const Duration(days: 29)), t);
                        },
                      ),
                      ActionChip(
                        label: const Text('Hari ini'),
                        onPressed: () => onPeriodChanged(today, today),
                      ),
                    ],
                  ),
                  Text(
                    'Maks. $kManagerReportMaxRangeDays hari per rentang.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 11,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

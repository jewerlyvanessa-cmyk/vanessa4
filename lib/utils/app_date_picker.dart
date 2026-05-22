import 'package:flutter/material.dart';
import 'package:vanessa3/utils/business_calendar.dart';

DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

DateTime _clampDate(DateTime d, DateTime first, DateTime last) {
  final x = _dateOnly(d);
  final f = _dateOnly(first);
  final l = _dateOnly(last);
  if (x.isBefore(f)) return f;
  if (x.isAfter(l)) return l;
  return x;
}

/// Hindari assertion `maxScale > minScale` pada [InteractiveViewer] di date picker web
/// ketika root app memakai [ResponsiveLayout.clampMediaQuery].
Widget appDatePickerDialogBuilder(BuildContext context, Widget? child) {
  if (child == null) return const SizedBox.shrink();
  return MediaQuery(
    data: MediaQuery.of(context).copyWith(
      textScaler: TextScaler.noScaling,
    ),
    child: child,
  );
}

/// Pemilih tanggal tunggal — aman di web & mobile, locale ID.
Future<DateTime?> showAppDatePicker({
  required BuildContext context,
  required DateTime initialDate,
  DateTime? firstDate,
  DateTime? lastDate,
  DatePickerEntryMode initialEntryMode = DatePickerEntryMode.calendarOnly,
}) async {
  final first = _dateOnly(firstDate ?? DateTime(2020));
  final last = _dateOnly(lastDate ?? BusinessCalendar.todayWibDateOnly());
  final initial = _clampDate(initialDate, first, last);

  return showDatePicker(
    context: context,
    locale: const Locale('id', 'ID'),
    initialDate: initial,
    firstDate: first,
    lastDate: last,
    initialEntryMode: initialEntryMode,
    builder: appDatePickerDialogBuilder,
  );
}

/// Pemilih rentang tanggal — aman di web & mobile, locale ID.
Future<DateTimeRange?> showAppDateRangePicker({
  required BuildContext context,
  required DateTimeRange initialDateRange,
  DateTime? firstDate,
  DateTime? lastDate,
}) async {
  final first = _dateOnly(firstDate ?? DateTime(2020));
  final last = _dateOnly(lastDate ?? BusinessCalendar.todayWibDateOnly());
  var start = _clampDate(initialDateRange.start, first, last);
  var end = _clampDate(initialDateRange.end, first, last);
  if (start.isAfter(end)) {
    end = start;
  }

  return showDateRangePicker(
    context: context,
    locale: const Locale('id', 'ID'),
    firstDate: first,
    lastDate: last,
    initialDateRange: DateTimeRange(start: start, end: end),
    builder: appDatePickerDialogBuilder,
  );
}

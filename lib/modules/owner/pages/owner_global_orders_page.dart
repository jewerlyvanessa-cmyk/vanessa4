import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:vanessa3/modules/owner/data/owner_dashboard_service.dart';
import 'package:vanessa3/modules/owner/widgets/owner_global_orders_section.dart';
import 'package:vanessa3/providers/user_state_provider.dart';
import 'package:vanessa3/utils/business_calendar.dart';

/// Halaman penuh daftar order global (jika dibuka terpisah dari dashboard).
class OwnerGlobalOrdersPage extends ConsumerStatefulWidget {
  const OwnerGlobalOrdersPage({super.key});

  @override
  ConsumerState<OwnerGlobalOrdersPage> createState() =>
      _OwnerGlobalOrdersPageState();
}

class _OwnerGlobalOrdersPageState extends ConsumerState<OwnerGlobalOrdersPage> {
  DateTime _selectedDate = BusinessCalendar.todayWibDateOnly();
  bool _loading = true;
  String _error = '';
  List<Map<String, dynamic>> _ordersRaw = const [];

  String get _dateYmd =>
      _selectedDate == BusinessCalendar.todayWibDateOnly()
          ? BusinessCalendar.todayYmd()
          : DateFormat('yyyy-MM-dd').format(_selectedDate);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool forceRefresh = false}) async {
    setState(() {
      _loading = true;
      _error = '';
    });
    try {
      final branches = ref.read(userStateProvider).branches;
      final data = await OwnerDashboardService.loadDashboard(
        branches: branches,
        dateYmd: _dateYmd,
        forceRefresh: forceRefresh,
      );
      if (!mounted) return;
      setState(() {
        _ordersRaw = data.orders;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _onDateChanged(DateTime date) async {
    setState(() => _selectedDate = date);
    OwnerDashboardService.invalidateCache();
    await _load(forceRefresh: true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Daftar Order Global'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loading
                ? null
                : () {
                    OwnerDashboardService.invalidateCache();
                    _load(forceRefresh: true);
                  },
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: OwnerGlobalOrdersSection(
          ordersRaw: _ordersRaw,
          loading: _loading,
          error: _error,
          selectedDate: _selectedDate,
          onDateChanged: _onDateChanged,
          onRefresh: () {
            OwnerDashboardService.invalidateCache();
            _load(forceRefresh: true);
          },
          showSectionTitle: false,
        ),
      ),
    );
  }
}

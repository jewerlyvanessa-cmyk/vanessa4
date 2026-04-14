import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:vanessa3/main.dart'; // Import for userStateProvider
import 'package:vanessa3/utils/network_config.dart'; // Import for NetworkConfig

// Model untuk Order Today
class OrderTodayStats {
  final int totalOrders;
  final int completedOrders;
  final int pendingOrders;
  final Map<String, int> ordersByType;
  final Map<String, int> ordersByStatus;
  final double totalRevenue;
  final DateTime date;

  OrderTodayStats({
    required this.totalOrders,
    required this.completedOrders,
    required this.pendingOrders,
    required this.ordersByType,
    required this.ordersByStatus,
    required this.totalRevenue,
    required this.date,
  });

  factory OrderTodayStats.fromJson(Map<String, dynamic> json) {
    return OrderTodayStats(
      totalOrders: json['total_orders'] ?? 0,
      completedOrders: json['completed_orders'] ?? 0,
      pendingOrders: json['pending_orders'] ?? 0,
      ordersByType: Map<String, int>.from(json['orders_by_type'] ?? {}),
      ordersByStatus: Map<String, int>.from(json['orders_by_status'] ?? {}),
      totalRevenue: (json['total_revenue'] ?? 0).toDouble(),
      date: DateTime.parse(json['date'] ?? DateTime.now().toIso8601String()),
    );
  }
}

// Provider untuk Order Today Stats
final orderTodayStatsProvider =
    StateNotifierProvider<OrderTodayStatsNotifier, AsyncValue<OrderTodayStats>>(
      (ref) {
        return OrderTodayStatsNotifier(ref);
      },
    );

class OrderTodayStatsNotifier
    extends StateNotifier<AsyncValue<OrderTodayStats>> {
  final Ref _ref;
  int? _lastUserId;
  String? _lastBranch;

  OrderTodayStatsNotifier(this._ref) : super(const AsyncValue.loading()) {
    // Check if user is already logged in and load data
    _checkAndFetch();
  }

  void _checkAndFetch() {
    final userState = _ref.read(userStateProvider);
    if (userState.userId != null && userState.branch.isNotEmpty) {
      fetchOrderTodayStats();
    } else {
      // User not logged in yet, stay in loading state
      state = const AsyncValue.loading();
    }
  }

  // Method untuk mendengarkan perubahan user state
  void listenToUserStateChanges() {
    final userState = _ref.read(userStateProvider);
    if (_lastUserId != userState.userId || _lastBranch != userState.branch) {
      _lastUserId = userState.userId;
      _lastBranch = userState.branch;
      _checkAndFetch();
    }
  }

  Future<void> fetchOrderTodayStats() async {
    state = const AsyncValue.loading();

    try {
      // Use real API call instead of mock data
      final baseUrl = NetworkConfig.baseUrl; // Use NetworkConfig for proper URL

      // Get current user state
      final userState = _ref.read(userStateProvider);
      final userId = userState.userId;
      final branchId =
          int.tryParse(userState.branch) ??
          1; // Parse branch string to int, default to 1

      // Build query parameters
      final queryParams = <String, String>{
        'branch_id': branchId.toString(),
        'date': DateTime.now().toIso8601String().split(
          'T',
        )[0], // YYYY-MM-DD format
      };

      // Add user_id filter only for non-CS users (CS should see all orders in their branch)
      final userRole = userState.role.toLowerCase();
      if (userId != null && userRole != 'cs') {
        queryParams['user_id'] = userId.toString();
      }

      final uri = Uri.parse(
        '$baseUrl/api/dashboard/order-today',
      ).replace(queryParameters: queryParams);

      final client = http.Client();
      final response = await client
          .get(uri, headers: NetworkConfig.defaultHeaders)
          .timeout(NetworkConfig.connectionTimeout);
      client.close();

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final stats = OrderTodayStats.fromJson(data);
        state = AsyncValue.data(stats);
      } else {
        throw Exception('Failed to load order stats: ${response.statusCode}');
      }
    } catch (error, stackTrace) {
      state = AsyncValue.error(error, stackTrace);
    }
  }

  // Method untuk refresh data
  Future<void> refresh() async {
    await fetchOrderTodayStats();
  }

  // Method untuk update stats secara real-time (dipanggil dari WebSocket)
  void updateStats(OrderTodayStats newStats) {
    state = AsyncValue.data(newStats);
  }
}

// Provider untuk list order hari ini
final todayOrdersProvider =
    StateNotifierProvider<
      TodayOrdersNotifier,
      AsyncValue<List<Map<String, dynamic>>>
    >((ref) {
      return TodayOrdersNotifier(ref);
    });

class TodayOrdersNotifier
    extends StateNotifier<AsyncValue<List<Map<String, dynamic>>>> {
  final Ref _ref;
  int? _lastUserId;
  String? _lastBranch;

  TodayOrdersNotifier(this._ref) : super(const AsyncValue.loading()) {
    // Check if user is already logged in and load data
    _checkAndFetch();
  }

  void _checkAndFetch() {
    final userState = _ref.read(userStateProvider);
    if (userState.userId != null && userState.branch.isNotEmpty) {
      fetchTodayOrders();
    } else {
      // User not logged in yet, stay in loading state
      state = const AsyncValue.loading();
    }
  }

  // Method untuk mendengarkan perubahan user state
  void listenToUserStateChanges() {
    final userState = _ref.read(userStateProvider);
    if (_lastUserId != userState.userId || _lastBranch != userState.branch) {
      _lastUserId = userState.userId;
      _lastBranch = userState.branch;
      _checkAndFetch();
    }
  }

  Future<void> fetchTodayOrders() async {
    state = const AsyncValue.loading();

    try {
      // Use real API call instead of mock data
      final baseUrl = NetworkConfig.baseUrl; // Use NetworkConfig for proper URL

      // Get current user state
      final userState = _ref.read(userStateProvider);
      final userId = userState.userId;
      final branchId =
          int.tryParse(userState.branch) ??
          1; // Parse branch string to int, default to 1

      // Build query parameters
      final queryParams = <String, String>{'branch_id': branchId.toString()};

      // Add user_id filter only for non-CS users (CS should see all orders in their branch)
      final userRole = userState.role.toLowerCase();
      if (userId != null && userRole != 'cs') {
        queryParams['user_id'] = userId.toString();
      }

      final uri = Uri.parse(
        '$baseUrl/orders/daily',
      ).replace(queryParameters: queryParams);

      final client = http.Client();
      final response = await client
          .get(uri, headers: NetworkConfig.defaultHeaders)
          .timeout(NetworkConfig.connectionTimeout);
      client.close();

      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        final rawOrders = data
            .map((order) => Map<String, dynamic>.from(order))
            .toList();

        // Check if response already includes item details (from updated /orders/daily endpoint)
        final hasItemDetails =
            rawOrders.isNotEmpty && rawOrders.first.containsKey('nama_item');

        if (hasItemDetails) {
          // Response already includes item details, group by order_id
          final ordersWithItems = _groupOrdersWithItems(rawOrders);
          state = AsyncValue.data(ordersWithItems);
        } else {
          // Legacy behavior: fetch order items separately
          final ordersWithItems = await _fetchOrderItemsForOrders(
            rawOrders,
            baseUrl,
            queryParams,
          );
          state = AsyncValue.data(ordersWithItems);
        }
      } else {
        throw Exception('Failed to load today orders: ${response.statusCode}');
      }
    } catch (error, stackTrace) {
      state = AsyncValue.error(error, stackTrace);
    }
  }

  Future<List<Map<String, dynamic>>> _fetchOrderItemsForOrders(
    List<Map<String, dynamic>> orders,
    String baseUrl,
    Map<String, String> queryParams,
  ) async {
    try {
      // Fetch all order items
      final orderItemsUri = Uri.parse(
        '$baseUrl/order-items',
      ).replace(queryParameters: queryParams);
      final client = http.Client();
      final orderItemsResponse = await client
          .get(orderItemsUri, headers: NetworkConfig.defaultHeaders)
          .timeout(NetworkConfig.connectionTimeout);
      client.close();

      if (orderItemsResponse.statusCode == 200) {
        final List<dynamic> orderItemsData = jsonDecode(
          orderItemsResponse.body,
        );

        // Group order items by order_id
        final Map<String, List<Map<String, dynamic>>> itemsByOrderId = {};
        for (var item in orderItemsData) {
          final orderId = item['order_id'].toString();
          if (!itemsByOrderId.containsKey(orderId)) {
            itemsByOrderId[orderId] = [];
          }
          itemsByOrderId[orderId]!.add(Map<String, dynamic>.from(item));
        }

        // Attach items to each order
        return orders.map((order) {
          final orderId = order['order_id'].toString();
          final orderItems = itemsByOrderId[orderId] ?? [];
          return {...order, 'items': orderItems};
        }).toList();
      } else {
        // If order-items endpoint fails, return orders without items
        return orders.map((order) => {...order, 'items': []}).toList();
      }
    } catch (error) {
      // If fetching order items fails, return orders without items
      return orders.map((order) => {...order, 'items': []}).toList();
    }
  }

  List<Map<String, dynamic>> _groupOrdersWithItems(
    List<Map<String, dynamic>> rawData,
  ) {
    // Group data by order_id since JOIN causes duplication
    final Map<String, Map<String, dynamic>> ordersMap = {};

    for (var row in rawData) {
      final orderId = row['order_id'].toString();

      if (!ordersMap.containsKey(orderId)) {
        // Create order entry (exclude item-specific fields)
        ordersMap[orderId] = {
          'order_id': row['order_id'],
          'order_number': row['order_number'],
          'order_type': row['order_type'],
          'customer_id': row['customer_id'],
          'customer_name': row['customer_name'],
          'customer_phone': row['customer_phone'],
          'customer_address': row['customer_address'],
          'branch_id': row['branch_id'],
          'user_id': row['user_id'],
          'status': row['status'],
          'total': row['total'],
          'diskon': row['diskon'],
          'mode': row['mode'],
          'created_at': row['created_at'],
          'updated_at': row['updated_at'],
          'items': [],
        };
      }

      // Add item if it exists (check if nama_item is not null)
      if (row['nama_item'] != null) {
        final qty = double.tryParse(row['qty'].toString()) ?? 0;
        final weight = double.tryParse(row['weight'].toString()) ?? 0;
        final hargaPerGram =
            double.tryParse(row['harga_per_gram'].toString()) ?? 0;
        final calculatedTotal = qty * weight * hargaPerGram;

        final item = {
          'order_item_id': row['order_item_id'],
          'nama_item': row['nama_item'],
          'kode_produk': row['kode_produk'] ?? row['item_kode'],
          'weight': row['weight'] ?? row['item_weight'],
          'qty': row['qty'],
          'harga_per_gram': row['harga_per_gram'],
          'total': calculatedTotal > 0
              ? calculatedTotal
              : (row['jumlah'] != null
                    ? double.tryParse(row['jumlah'].toString())
                    : null),
          'material': row['material'] ?? row['item_material'],
          'purity': row['purity'] ?? row['item_purity'],
          'kategori': row['kategori'] ?? row['item_kategori'],
          'jenis': row['jenis'] ?? row['item_jenis'],
          'tipe': row['tipe'] ?? row['item_tipe'],
          'item_id': row['item_id'],
          'photo_produk': row['photo_produk'],
        };

        ordersMap[orderId]!['items'].add(item);
      }
    }

    return ordersMap.values.toList();
  }

  Future<void> refresh() async {
    await fetchTodayOrders();
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vanessa3/main.dart';
import 'package:vanessa3/providers/websocket_provider.dart';
import 'package:vanessa3/shared_widgets/switch_branch_role_widget.dart';
import 'package:vanessa3/data/api_service.dart';

class MaterialStockPage extends ConsumerStatefulWidget {
  const MaterialStockPage({super.key});

  @override
  ConsumerState<MaterialStockPage> createState() => _MaterialStockPageState();
}

class _MaterialStockPageState extends ConsumerState<MaterialStockPage> {
  List<Map<String, dynamic>> _materialStock = [];
  bool _isLoading = true;
  String _errorMessage = '';
  String _selectedCategory = 'Semua';

  @override
  void initState() {
    super.initState();
    _loadMaterialStock();
  }

  Future<void> _loadMaterialStock() async {
    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    try {
      final userState = ref.read(userStateProvider);
      final stock = await ApiService.getMaterialStock(userState.branch);

      setState(() {
        _materialStock = stock;
        _isLoading = false;
      });
    } catch (error) {
      setState(() {
        _errorMessage = 'Gagal memuat stok material: $error';
        _isLoading = false;
      });
    }
  }

  List<Map<String, dynamic>> _getFilteredStock() {
    if (_selectedCategory == 'Semua') {
      return _materialStock;
    }
    return _materialStock.where((item) => item['material'] == _selectedCategory).toList();
  }

  @override
  Widget build(BuildContext context) {
    final webSocketState = ref.watch(webSocketProvider);
    final filteredStock = _getFilteredStock();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Stok Material'),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadMaterialStock,
          ),
        ],
      ),
      body: Column(
        children: [
          // Connection Status
          Container(
            padding: const EdgeInsets.all(8),
            color: webSocketState != null ? Colors.green[100] : Colors.red[100],
            child: Row(
              children: [
                Icon(
                  webSocketState != null ? Icons.wifi : Icons.wifi_off,
                  color: webSocketState != null ? Colors.green : Colors.red,
                ),
                const SizedBox(width: 8),
                Text(
                  webSocketState != null ? 'Terhubung' : 'Terputus',
                  style: TextStyle(
                    color: webSocketState != null ? Colors.green : Colors.red,
                  ),
                ),
              ],
            ),
          ),

          // Branch and Role Switcher
          const SwitchBranchRoleWidget(),

          // Category Filter
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                const Text('Kategori: '),
                DropdownButton<String>(
                  value: _selectedCategory,
                  items: ['Semua', 'Besi', 'Kayu', 'Cat', 'Lainnya']
                      .map((category) => DropdownMenuItem(
                            value: category,
                            child: Text(category),
                          ))
                      .toList(),
                  onChanged: (value) {
                    setState(() {
                      _selectedCategory = value!;
                    });
                  },
                ),
              ],
            ),
          ),

          // Content
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _errorMessage.isNotEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(_errorMessage, style: const TextStyle(color: Colors.red)),
                            const SizedBox(height: 16),
                            ElevatedButton(
                              onPressed: _loadMaterialStock,
                              child: const Text('Coba Lagi'),
                            ),
                          ],
                        ),
                      )
                    : filteredStock.isEmpty
                        ? const Center(child: Text('Tidak ada data stok material'))
                        : ListView.builder(
                            itemCount: filteredStock.length,
                            itemBuilder: (context, index) {
                              final item = filteredStock[index];
                              return Card(
                                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                                child: ListTile(
                                  title: Text(item['material'] ?? 'Unknown'),
                                  subtitle: Text('Stok: ${item['quantity'] ?? 0}'),
                                  trailing: Text('Cabang: ${item['branch'] ?? 'Unknown'}'),
                                ),
                              );
                            },
                          ),
          ),
        ],
      ),
    );
  }
}

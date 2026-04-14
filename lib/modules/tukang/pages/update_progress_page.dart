import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vanessa3/data/api_service.dart';
import 'package:vanessa3/main.dart';

class UpdateProgressPage extends ConsumerStatefulWidget {
  const UpdateProgressPage({super.key});

  @override
  ConsumerState<UpdateProgressPage> createState() => _UpdateProgressPageState();
}

class _UpdateProgressPageState extends ConsumerState<UpdateProgressPage> {
  List<Map<String, dynamic>> _workQueue = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadWorkQueue();
  }

  Future<void> _loadWorkQueue() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final userState = ref.read(userStateProvider);
      final workQueue = await ApiService.getWorkQueue(
        userState.userId.toString(),
        userState.branch,
      );

      setState(() {
        _workQueue = workQueue;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _updateProgress(int orderId, String status, String notes) async {
    try {
      final userState = ref.read(userStateProvider);
      await ApiService.updateWorkProgress(
        orderId,
        status,
        userState.userId.toString(),
        notes: notes,
      );

      // Reload work queue after update
      await _loadWorkQueue();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Progress berhasil diperbarui')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: ${e.toString()}')));
      }
    }
  }

  void _showUpdateDialog(Map<String, dynamic> work) {
    final statusController = TextEditingController(text: work['status']);
    final notesController = TextEditingController(text: work['notes'] ?? '');

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Update Progress - Order #${work['order_id']}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<String>(
              initialValue: statusController.text,
              decoration: const InputDecoration(labelText: 'Status'),
              items: const [
                DropdownMenuItem(value: 'pending', child: Text('Menunggu')),
                DropdownMenuItem(
                  value: 'in_progress',
                  child: Text('Dalam Proses'),
                ),
                DropdownMenuItem(value: 'completed', child: Text('Selesai')),
                DropdownMenuItem(value: 'cancelled', child: Text('Dibatalkan')),
              ],
              onChanged: (value) {
                statusController.text = value ?? '';
              },
            ),
            const SizedBox(height: 16),
            TextField(
              controller: notesController,
              decoration: const InputDecoration(
                labelText: 'Catatan',
                hintText: 'Tambahkan catatan progress...',
              ),
              maxLines: 3,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Batal'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(context).pop();
              _updateProgress(
                work['order_id'],
                statusController.text,
                notesController.text,
              );
            },
            child: const Text('Update'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: 'Kembali',
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text('Update Progress'),
      ),
      body: Column(
        children: [
          // Content Area
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.error, size: 48, color: Colors.red),
                        const SizedBox(height: 16),
                        Text('Error: $_error'),
                        const SizedBox(height: 16),
                        ElevatedButton(
                          onPressed: _loadWorkQueue,
                          child: const Text('Coba Lagi'),
                        ),
                      ],
                    ),
                  )
                : _workQueue.isEmpty
                ? const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.assignment, size: 48, color: Colors.grey),
                        SizedBox(height: 16),
                        Text('Tidak ada pekerjaan yang perlu diperbarui'),
                      ],
                    ),
                  )
                : RefreshIndicator(
                    onRefresh: _loadWorkQueue,
                    child: ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 16.0),
                      itemCount: _workQueue.length,
                      itemBuilder: (context, index) {
                        final work = _workQueue[index];
                        return Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor: _getStatusColor(work['status']),
                              child: Icon(
                                _getStatusIcon(work['status']),
                                color: Colors.white,
                                size: 20,
                              ),
                            ),
                            title: Text('Order #${work['order_id']}'),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '${work['item_name']} (${work['item_type']})',
                                ),
                                Text('Pelanggan: ${work['customer_name']}'),
                                Text(
                                  'Status: ${_getStatusText(work['status'])}',
                                ),
                                if (work['notes'] != null &&
                                    work['notes'].isNotEmpty)
                                  Text('Catatan: ${work['notes']}'),
                              ],
                            ),
                            trailing: IconButton(
                              icon: const Icon(Icons.edit),
                              onPressed: () => _showUpdateDialog(work),
                              tooltip: 'Update Progress',
                            ),
                            onTap: () => _showUpdateDialog(work),
                          ),
                        );
                      },
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  String _getStatusText(String status) {
    switch (status) {
      case 'pending':
        return 'Menunggu';
      case 'in_progress':
        return 'Dalam Proses';
      case 'completed':
        return 'Selesai';
      case 'cancelled':
        return 'Dibatalkan';
      default:
        return 'Unknown';
    }
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'pending':
        return Colors.orange;
      case 'in_progress':
        return Colors.blue;
      case 'completed':
        return Colors.green;
      case 'cancelled':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  IconData _getStatusIcon(String status) {
    switch (status) {
      case 'pending':
        return Icons.schedule;
      case 'in_progress':
        return Icons.engineering;
      case 'completed':
        return Icons.check_circle;
      case 'cancelled':
        return Icons.cancel;
      default:
        return Icons.help;
    }
  }
}

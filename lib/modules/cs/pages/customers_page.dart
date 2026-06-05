import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vanessa3/modules/cs/logic/customers_utils.dart';
import 'package:vanessa3/modules/cs/widgets/customers_data_table.dart';
import 'package:vanessa3/modules/cs/widgets/customers_dialogs.dart';
import 'package:vanessa3/providers/customers_provider.dart';
import 'package:vanessa3/providers/user_state_provider.dart';
import 'package:vanessa3/providers/websocket_provider.dart';

class CustomersPage extends ConsumerWidget {
  const CustomersPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final customersState = ref.watch(customersProvider);
    final customersNotifier = ref.read(customersProvider.notifier);
    final userState = ref.watch(userStateProvider);

    ref.listen(realTimeOrderUpdatesProvider, (previous, next) {
      next.whenData((update) {
        if (update['type'] == 'customer_update') {
          customersNotifier.fetchCustomers(
            branchId: userState.branch,
            silent: true,
          );
        }
      });
    });

    if (!customersState.hasLoaded && !customersState.isLoading) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!ref.read(customersProvider).hasLoaded) {
          customersNotifier.fetchCustomers(branchId: userState.branch);
        }
      });
    }

    if (customersState.isLoading && !customersState.hasLoaded) {
      return Scaffold(
        appBar: AppBar(title: const Text('Pelanggan')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (customersState.error != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Pelanggan')),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 64, color: Colors.red),
              const SizedBox(height: 16),
              Text('Error: ${customersState.error}'),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () => customersNotifier.fetchCustomers(
                  branchId: userState.branch,
                ),
                child: const Text('Coba Lagi'),
              ),
            ],
          ),
        ),
      );
    }

    final canAdd = CustomersUtils.canEditCustomer(userState.role);

    void onRowAction(String action, Map<String, dynamic> customer) {
      handleCustomerRowAction(context, ref, customer, action);
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Pelanggan'),
        actions: [
          if (canAdd)
            IconButton(
              icon: const Icon(Icons.person_add_outlined),
              tooltip: 'Tambah pelanggan',
              onPressed: () => showAddCustomerDialog(context, ref),
            ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: customersState.isLoading
                ? null
                : () => customersNotifier.fetchCustomers(
                      branchId: userState.branch,
                      silent: true,
                    ),
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: customersState.customers.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.people_outline,
                      size: 64,
                      color: Theme.of(context).colorScheme.outline,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Belum ada data pelanggan',
                      style: Theme.of(context).textTheme.titleMedium,
                      textAlign: TextAlign.center,
                    ),
                    if (canAdd) ...[
                      const SizedBox(height: 20),
                      FilledButton.icon(
                        onPressed: () => showAddCustomerDialog(context, ref),
                        icon: const Icon(Icons.add),
                        label: const Text('Tambah Pelanggan'),
                      ),
                    ],
                  ],
                ),
              ),
            )
          : Padding(
              padding: const EdgeInsets.only(top: 4),
              child: CustomersDataTable(
                customersState: customersState,
                role: userState.role,
                onAction: onRowAction,
              ),
            ),
      floatingActionButton: canAdd
          ? FloatingActionButton.extended(
              onPressed: () => showAddCustomerDialog(context, ref),
              icon: const Icon(Icons.add),
              label: const Text('Tambah'),
            )
          : null,
    );
  }
}

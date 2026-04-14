import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../main.dart';
import 'package:vanessa3/providers/websocket_provider.dart';

class MainModulePage extends ConsumerStatefulWidget {
  final String mainModule;
  final List<Map<String, dynamic>> branches;
  final List<String> roles;

  const MainModulePage({
    super.key,
    required this.mainModule,
    required this.branches,
    required this.roles,
  });

  @override
  MainModulePageState createState() => MainModulePageState();
}

class MainModulePageState extends ConsumerState<MainModulePage> {
  late String selectedBranchId;
  late String selectedRole;

  @override
  void initState() {
    super.initState();
    selectedBranchId = widget.branches.isNotEmpty
        ? widget.branches[0]['branch_id'].toString()
        : '';
    selectedRole = widget.roles.isNotEmpty ? widget.roles[0] : '';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Main Module'),
        actions: [
          IconButton(
            icon: const Icon(Icons.account_tree),
            tooltip: 'Ganti Branch',
            onPressed: () {
              showDialog(
                context: context,
                builder: (context) {
                  return AlertDialog(
                    title: const Text('Pilih Branch'),
                    content: SizedBox(
                      width: double.maxFinite,
                      child: ListView(
                        shrinkWrap: true,
                        children: widget.branches.map((branch) {
                          return ListTile(
                            title: Text(branch['name']),
                            selected:
                                selectedBranchId ==
                                branch['branch_id'].toString(),
                            onTap: () {
                              setState(() {
                                selectedBranchId = branch['branch_id']
                                    .toString();
                              });
                              List<String> branchRoles = branch['roles'] != null
                                  ? List<String>.from(branch['roles'])
                                  : [];
                              if (branchRoles.length == 1) {
                                setState(() {
                                  selectedRole = branchRoles[0];
                                });
                                Navigator.pop(context);
                                final mainModule = getMainModuleForRole(
                                  branchRoles[0],
                                );
                                navigateToMainModule(context, mainModule);
                              } else {
                                Navigator.pop(context);
                              }
                            },
                          );
                        }).toList(),
                      ),
                    ),
                  );
                },
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.person_outline),
            tooltip: 'Ganti Role',
            onPressed: () {
              showDialog(
                context: context,
                builder: (context) {
                  return AlertDialog(
                    title: const Text('Pilih Role'),
                    content: SizedBox(
                      width: double.maxFinite,
                      child: ListView(
                        shrinkWrap: true,
                        children: widget.roles.map((role) {
                          return ListTile(
                            title: Text(role),
                            selected: selectedRole == role,
                            onTap: () {
                              setState(() {
                                selectedRole = role;
                              });
                              Navigator.pop(context);
                            },
                          );
                        }).toList(),
                      ),
                    ),
                  );
                },
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Logout',
            onPressed: () {
              ref.read(webSocketProvider.notifier).disconnect();
              ref.read(userStateProvider.notifier).logout();
              Navigator.pushReplacementNamed(context, '/login');
            },
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Halaman utama: ${widget.mainModule}',
              style: const TextStyle(fontSize: 18),
            ),
            const SizedBox(height: 16),
            Text(
              'Modul untuk role: $selectedRole',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            _buildRoleModules(selectedRole),
            const Spacer(),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Column(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.account_tree),
                      tooltip: 'Ganti Branch',
                      onPressed: () {
                        showDialog(
                          context: context,
                          builder: (context) {
                            return AlertDialog(
                              title: const Text('Pilih Branch'),
                              content: SizedBox(
                                width: double.maxFinite,
                                child: ListView(
                                  shrinkWrap: true,
                                  children: widget.branches.map((branch) {
                                    return ListTile(
                                      title: Text(branch['name']),
                                      selected:
                                          selectedBranchId ==
                                          branch['branch_id'].toString(),
                                      onTap: () {
                                        setState(() {
                                          selectedBranchId = branch['branch_id']
                                              .toString();
                                        });
                                        Navigator.pop(context);
                                      },
                                    );
                                  }).toList(),
                                ),
                              ),
                            );
                          },
                        );
                      },
                    ),
                    Text(
                      (widget.branches.firstWhere(
                        (b) => b['branch_id'].toString() == selectedBranchId,
                        orElse: () => {'name': ''},
                      )['name']),
                    ),
                  ],
                ),
                const SizedBox(width: 32),
                Column(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.person_outline),
                      tooltip: 'Ganti Role',
                      onPressed: () {
                        showDialog(
                          context: context,
                          builder: (context) {
                            return AlertDialog(
                              title: const Text('Pilih Role'),
                              content: SizedBox(
                                width: double.maxFinite,
                                child: ListView(
                                  shrinkWrap: true,
                                  children: widget.roles.map((role) {
                                    return ListTile(
                                      title: Text(role),
                                      selected: selectedRole == role,
                                      onTap: () {
                                        setState(() {
                                          selectedRole = role;
                                        });
                                        Navigator.pop(context);
                                      },
                                    );
                                  }).toList(),
                                ),
                              ),
                            );
                          },
                        );
                      },
                    ),
                    Text(selectedRole),
                  ],
                ),
                const SizedBox(width: 32),
                TextButton(
                  onPressed: () {
                    final userState = ref.read(userStateProvider.notifier);
                    userState.setRole(selectedRole);
                    final mainModule = getMainModuleForRole(selectedRole);
                    navigateToMainModule(context, mainModule);
                  },
                  child: const Text('Switch'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRoleModules(String role) {
    final Map<String, List<String>> roleModules = {
      'cs': ['Order', 'Customer', 'Follow Up'],
      'kasir': ['Transaksi', 'Pembayaran', 'Refund'],
      'superadmin': ['User Management', 'Reporting', 'Setting'],
      'workshop': ['Service', 'Sparepart', 'Jadwal'],
      'order': ['Order Baru', 'Riwayat Order'],
      'reporting': ['Laporan Penjualan', 'Laporan Stok'],
      'dashboard': ['Ringkasan', 'Grafik'],
    };
    final modules = roleModules[role] ?? ['Modul tidak tersedia'];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: modules
          .map(
            (mod) => ListTile(
              leading: const Icon(Icons.check_circle_outline),
              title: Text(mod),
            ),
          )
          .toList(),
    );
  }
}

String getMainModuleForRole(String role) {
  switch (role) {
    case 'cs':
      return 'cs';
    case 'kasir':
      return 'kasir';
    case 'superadmin':
      return 'superadmin';
    case 'admin_toko':
      return 'adminToko';
    case 'admin_workshop':
      return 'admin_workshop';
    case 'tukang':
      return 'tukang';
    case 'manajer':
      return 'manajer';
    default:
      return 'dashboard';
  }
}

void navigateToMainModule(BuildContext context, String mainModule) {
  final navigator = Navigator.of(context);
  switch (mainModule) {
    case 'cs':
      navigator.pushReplacementNamed('/cs');
      break;
    case 'kasir':
      navigator.pushReplacementNamed('/kasir');
      break;
    case 'superadmin':
      navigator.pushReplacementNamed('/superadmin');
      break;
    case 'admin_toko':
      navigator.pushReplacementNamed('/admin_toko');
      break;
    case 'admin_workshop':
      navigator.pushReplacementNamed('/admin_workshop');
      break;
    case 'manajer':
      navigator.pushReplacementNamed('/manajer');
      break;
    case 'tukang':
      navigator.pushReplacementNamed('/tukang');
      break;
    default:
      navigator.pushReplacementNamed('/dashboard');
  }
}

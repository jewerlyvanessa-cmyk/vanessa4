import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/user_state_provider.dart';
import '../../providers/websocket_provider.dart';

class AdminWorkshopMainPage extends ConsumerWidget {
  const AdminWorkshopMainPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userState = ref.watch(userStateProvider);

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Image.asset(
              'assets/logo_bulat.png',
              height: 36,
              width: 36,
              fit: BoxFit.contain,
            ),
            const SizedBox(width: 12),
            const Text('Admin Workshop Main Page'),
          ],
        ),
        actions: [
          if (userState.branches.length > 1)
            PopupMenuButton<String>(
              icon: const Icon(Icons.account_tree),
              tooltip: 'Ganti Branch',
              onSelected: (branchId) {
                ref.read(userStateProvider.notifier).setBranch(branchId);
                final branchObj = userState.branches.firstWhere(
                  (b) => b['branch_id'].toString() == branchId,
                  orElse: () => <String, dynamic>{},
                );
                final rolesInBranch = (branchObj['roles'] is List)
                    ? List<String>.from(branchObj['roles'])
                    : <String>[];
                String newRole = '';
                if (rolesInBranch.isNotEmpty) {
                  newRole = rolesInBranch[0];
                  ref.read(userStateProvider.notifier).setRole(newRole);
                } else {
                  ref.read(userStateProvider.notifier).setRole('');
                }
                Future.microtask(() {
                  if (context.mounted) {
                    final mainModule = getMainModuleForRole(newRole);
                    navigateToMainModule(context, mainModule);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          'Branch diganti ke: ${branchObj['name'] ?? branchId}, role: $newRole',
                        ),
                      ),
                    );
                  }
                });
              },
              itemBuilder: (context) => userState.branches
                  .map(
                    (branch) => PopupMenuItem(
                      value: branch['branch_id'].toString(),
                      child: Text(
                        branch['name'] ?? branch['branch_id'].toString(),
                      ),
                    ),
                  )
                  .toList(),
            ),
          if (userState.branches.any(
            (b) =>
                b['branch_id'].toString() == userState.branch &&
                (b['roles'] as List).length > 1,
          ))
            PopupMenuButton<String>(
              icon: const Icon(Icons.switch_account),
              tooltip: 'Ganti Role',
              onSelected: (role) {
                ref.read(userStateProvider.notifier).setRole(role);
                final mainModule = getMainModuleForRole(role);
                navigateToMainModule(context, mainModule);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Role diganti ke: $role')),
                );
              },
              itemBuilder: (context) => userState.branches
                  .firstWhere(
                    (b) => b['branch_id'].toString() == userState.branch,
                  )['roles']
                  .map<PopupMenuItem<String>>(
                    (role) => PopupMenuItem(value: role, child: Text(role)),
                  )
                  .toList(),
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
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'User: ${userState.username.isNotEmpty ? userState.username : '-'}',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 4),
                Builder(
                  builder: (context) {
                    String branchName = userState.branch;
                    if (userState.branch.isNotEmpty &&
                        userState.branches.isNotEmpty) {
                      try {
                        final found = userState.branches.firstWhere(
                          (b) => b['branch_id'].toString() == userState.branch,
                        );
                        branchName = found['name'] ?? userState.branch;
                      } catch (e) {
                        branchName = userState.branch;
                      }
                    }
                    return Text(
                      'Branch aktif: $branchName',
                      style: Theme.of(context).textTheme.titleMedium,
                    );
                  },
                ),
                const SizedBox(height: 4),
                Text(
                  'Role aktif: ${userState.role}',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Expanded(
            child: Center(
              child: const Text('Halaman utama untuk modul Admin Workshop.'),
            ),
          ),
        ],
      ),
    );
  }
}

// Pastikan fungsi berikut tersedia di file ini atau diimpor
String getMainModuleForRole(String role) {
  switch (role) {
    case 'cs':
      return 'cs';
    case 'kasir':
      return 'kasir';
    case 'superadmin':
      return 'superadmin';
    case 'admin_toko':
      return 'admin_toko';
    case 'admin_workshop':
      return 'admin_workshop';
    case 'tukang':
      return 'tukang';
    case 'manajer':
      return 'manajer';
    case 'stockist':
      return 'stockist';
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
    case 'admin_toko':
      navigator.pushReplacementNamed('/admin_toko');
      break;
    case 'admin_workshop':
      navigator.pushReplacementNamed('/admin_workshop');
      break;
    case 'tukang':
      navigator.pushReplacementNamed('/tukang');
      break;
    case 'superadmin':
      navigator.pushReplacementNamed('/superadmin');
      break;
    case 'manajer':
      navigator.pushReplacementNamed('/manager');
      break;
    case 'stockist':
      navigator.pushReplacementNamed('/stockist');
      break;
    default:
      navigator.pushReplacementNamed('/dashboard');
  }
}

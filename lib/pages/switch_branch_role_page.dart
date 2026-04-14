import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../routes/app_routes.dart';
import 'package:vanessa3/main.dart';

class SwitchBranchRolePage extends ConsumerStatefulWidget {
  const SwitchBranchRolePage({super.key});

  @override
  ConsumerState<SwitchBranchRolePage> createState() => _SwitchBranchRolePageState();
}

class _SwitchBranchRolePageState extends ConsumerState<SwitchBranchRolePage> {
  String? selectedBranchId;
  String? selectedRole;
  Map<String, dynamic>? userData;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final args = ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?;
    if (args != null) {
      userData = args['userData'];
      // Set default selections
      if (userData?['branches']?.isNotEmpty == true) {
        selectedBranchId = userData!['branches'][0]['branch_id'].toString();
      }
      if (userData?['roles']?.isNotEmpty == true) {
        selectedRole = userData!['roles'][0];
      }
    }
  }

  void _continueToModule() {
    if (selectedBranchId == null || selectedRole == null || userData == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Silakan pilih cabang dan peran')),
      );
      return;
    }

    // Update user state with selected branch and role
    final userStateNotifier = ref.read(userStateProvider.notifier);
    final currentAuthToken = ref.read(userStateProvider).authToken;

    userStateNotifier.setUserData(
      userId: int.tryParse(userData!['user_id'].toString()),
      username: userData!['username'] ?? '',
      branch: selectedBranchId!,
      role: selectedRole!,
      authToken: currentAuthToken,
      roles: List<String>.from(userData!['roles'] ?? []),
      branches: List<Map<String, dynamic>>.from(userData!['branches'] ?? []),
    );

    // Navigate to appropriate module based on selected role
    String route = '';
    switch (selectedRole) {
      case 'cs':
        route = AppRoutes.cs;
        break;
      case 'kasir':
        route = AppRoutes.kasir;
        break;
      case 'superadmin':
        route = AppRoutes.superadmin;
        break;
      case 'admin_toko':
        route = AppRoutes.adminToko;
        break;
      case 'admin_workshop':
        route = AppRoutes.adminWorkshop;
        break;
      case 'manajer':
        route = AppRoutes.manajer;
        break;
      case 'tukang':
        route = AppRoutes.tukang;
        break;
      default:
        route = AppRoutes.dashboard;
    }

    Navigator.pushReplacementNamed(context, route);
  }

  @override
  Widget build(BuildContext context) {
    if (userData == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final branches = userData!['branches'] as List<dynamic>? ?? [];
    final roles = userData!['roles'] as List<dynamic>? ?? [];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Pilih Cabang & Peran'),
        automaticallyImplyLeading: false, // Disable back button
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Logo
            Center(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 24.0),
                child: Image.asset(
                  'assets/logo.png',
                  height: 80,
                ),
              ),
            ),

            Text(
              'Selamat datang, ${userData!['username']}',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            const Text(
              'Silakan pilih cabang dan peran untuk melanjutkan:',
              style: TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 32),

            // Branch Selection
            if (branches.length > 1) ...[
              const Text(
                'Pilih Cabang:',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: DropdownButton<String>(
                  value: selectedBranchId,
                  isExpanded: true,
                  underline: const SizedBox(),
                  hint: const Text('Pilih cabang'),
                  items: branches.map<DropdownMenuItem<String>>((branch) {
                    return DropdownMenuItem<String>(
                      value: branch['branch_id'].toString(),
                      child: Text(branch['name'] ?? 'Cabang ${branch['branch_id']}'),
                    );
                  }).toList(),
                  onChanged: (value) {
                    setState(() {
                      selectedBranchId = value;
                      // Reset role selection when branch changes
                      selectedRole = null;
                    });
                  },
                ),
              ),
              const SizedBox(height: 24),
            ] else if (branches.isNotEmpty) ...[
              Text(
                'Cabang: ${branches[0]['name'] ?? 'Cabang ${branches[0]['branch_id']}'}',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 24),
            ],

            // Role Selection
            if (roles.length > 1) ...[
              const Text(
                'Pilih Peran:',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: DropdownButton<String>(
                  value: selectedRole,
                  isExpanded: true,
                  underline: const SizedBox(),
                  hint: const Text('Pilih peran'),
                  items: roles.map<DropdownMenuItem<String>>((role) {
                    return DropdownMenuItem<String>(
                      value: role.toString(),
                      child: Text(_getRoleDisplayName(role.toString())),
                    );
                  }).toList(),
                  onChanged: (value) {
                    setState(() {
                      selectedRole = value;
                    });
                  },
                ),
              ),
            ] else if (roles.isNotEmpty) ...[
              Text(
                'Peran: ${_getRoleDisplayName(roles[0].toString())}',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
              ),
            ],

            const Spacer(),

            // Continue Button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _continueToModule,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: const Text(
                  'Lanjutkan',
                  style: TextStyle(fontSize: 16),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _getRoleDisplayName(String role) {
    switch (role) {
      case 'cs':
        return 'Customer Service';
      case 'kasir':
        return 'Kasir';
      case 'superadmin':
        return 'Super Admin';
      case 'admin_toko':
        return 'Admin Toko';
      case 'admin_workshop':
        return 'Admin Workshop';
      case 'manajer':
        return 'Manajer';
      case 'tukang':
        return 'Teknisi';
      default:
        return role;
    }
  }
}

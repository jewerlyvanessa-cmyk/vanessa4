import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:vanessa3/features/auth/domain/auth_repository.dart';
import 'package:vanessa3/providers/user_state_provider.dart';
import 'package:vanessa3/providers/websocket_provider.dart';
import 'package:vanessa3/routes/role_home_route.dart';
import 'package:vanessa3/utils/responsive_layout.dart';

class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key});

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> {
  final formKey = GlobalKey<FormState>();
  final usernameController = TextEditingController();
  final passwordController = TextEditingController();
  bool _isLoading = false;

  @override
  void dispose() {
    usernameController.dispose();
    passwordController.dispose();
    super.dispose();
  }

  Future<void> login() async {
    if (!formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    final username = usernameController.text;
    final password = passwordController.text;

    try {
      final result = await const AuthRepository().login(username, password);

      if (result['success'] == true) {
        final roles = List<String>.from(result['roles'] ?? []);
        final branches = List<Map<String, dynamic>>.from(
          result['branches'] ?? [],
        );
        final primaryRole = (result['role'] ?? '').toString().trim().toLowerCase();
        final primaryBranch = result['branch'] ?? '';

        ref.read(userStateProvider.notifier).setUserData(
              userId: int.tryParse(result['user_id'].toString()),
              username: result['username'] ?? '',
              branch: primaryBranch,
              role: primaryRole,
              authToken: result['token'] ?? '',
              roles: roles,
              branches: branches,
            );

        ref.read(webSocketProvider.notifier).initializeAfterLogin();

        final route = homeRouteForRole(primaryRole);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          Navigator.pushReplacementNamed(context, route);
        });
      } else {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(result['error'] ?? 'Login gagal')),
          );
        });
      }
    } catch (_) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Terjadi error saat login')),
        );
      });
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenW = MediaQuery.sizeOf(context).width;
    final formMaxW = screenW > 600 ? 400.0 : screenW.clamp(280.0, 600.0);
    return Scaffold(
      resizeToAvoidBottomInset: true,
      body: ResponsiveLayout.scrollableCenteredPage(
        context: context,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: formMaxW),
          child: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.only(bottom: 24.0),
                  child: Center(
                    child: Image.asset('assets/logo.png', height: 100),
                  ),
                ),
                TextFormField(
                  controller: usernameController,
                  decoration: const InputDecoration(
                    labelText: 'Username',
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                  ),
                  validator: (value) => value == null || value.isEmpty
                      ? 'Username tidak boleh kosong'
                      : null,
                  textInputAction: TextInputAction.next,
                  autofocus: true,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: passwordController,
                  decoration: const InputDecoration(
                    labelText: 'Password',
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                  ),
                  obscureText: true,
                  validator: (value) => value == null || value.isEmpty
                      ? 'Password tidak boleh kosong'
                      : null,
                  textInputAction: TextInputAction.done,
                  onFieldSubmitted: (_) => login(),
                ),
                const SizedBox(height: 32),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : login,
                    style: ElevatedButton.styleFrom(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: _isLoading
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                Colors.white,
                              ),
                            ),
                          )
                        : const Text('Login', style: TextStyle(fontSize: 16)),
                  ),
                ),
                const SizedBox(height: 16),
                const Center(
                  child: Text(
                    'Versi 1.0.0',
                    style: TextStyle(color: Colors.grey, fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

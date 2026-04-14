import 'package:flutter/material.dart';

class SuperadminMainPage extends StatelessWidget {
  const SuperadminMainPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Superadmin Main Page'),
      ),
      body: Center(
        child: Text('Halaman utama untuk modul Superadmin.'),
      ),
    );
  }
}

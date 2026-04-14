import 'package:flutter/material.dart';

class AdminTokoMainPage extends StatelessWidget {
  const AdminTokoMainPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Admin Toko Main Page'),
      ),
      body: Center(
        child: Text('Halaman utama untuk modul Admin Toko.'),
      ),
    );
  }
}

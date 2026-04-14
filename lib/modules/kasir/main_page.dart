import 'package:flutter/material.dart';

class KasirMainPage extends StatelessWidget {
  const KasirMainPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Kasir Main Page'),
      ),
      body: Center(
        child: Text('Halaman utama untuk modul Kasir.'),
      ),
    );
  }
}

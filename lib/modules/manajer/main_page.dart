import 'package:flutter/material.dart';

class ManajerMainPage extends StatelessWidget {
  const ManajerMainPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Manajer Main Page'),
      ),
      body: Center(
        child: Text('Halaman utama untuk modul Manajer.'),
      ),
    );
  }
}

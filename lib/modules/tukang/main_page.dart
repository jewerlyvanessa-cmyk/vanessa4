import 'package:flutter/material.dart';

class TukangMainPage extends StatelessWidget {
  const TukangMainPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Tukang Main Page'),
      ),
      body: Center(
        child: Text('Halaman utama untuk modul Tukang.'),
      ),
    );
  }
}

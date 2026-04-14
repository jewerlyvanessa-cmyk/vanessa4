import 'package:flutter/material.dart';

class ReportingPage extends StatelessWidget {
  const ReportingPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Reporting & Analytics'),
      ),
      body: Center(
        child: Text(
          'Halaman Reporting & Analytics sedang dalam pengembangan.',
          style: TextStyle(fontSize: 18),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}

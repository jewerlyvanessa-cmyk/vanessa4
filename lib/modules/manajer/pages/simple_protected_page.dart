import 'package:flutter/material.dart';

class SimpleProtectedPage extends StatelessWidget {
  final String title;
  final String description;
  const SimpleProtectedPage({
    super.key,
    required this.title,
    required this.description,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            description,
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}


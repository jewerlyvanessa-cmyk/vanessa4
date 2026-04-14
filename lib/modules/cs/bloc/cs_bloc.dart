import 'package:flutter/material.dart';

// Contoh BLoC sederhana menggunakan ChangeNotifier
class CsBloc extends ChangeNotifier {
  String _message = 'Initial';
  String get message => _message;

  void updateMessage(String newMessage) {
    _message = newMessage;
    notifyListeners();
  }
}

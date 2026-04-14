import 'dart:developer' as developer;

class Logger {
  static void logInfo(String message) {
    developer.log(message, level: 800, name: 'INFO');
  }

  static void logWarning(String message) {
    developer.log(message, level: 900, name: 'WARNING');
  }

  static void logError(String message, [Object? error, StackTrace? stackTrace]) {
    developer.log(message, level: 1000, name: 'ERROR', error: error, stackTrace: stackTrace);
  }
}

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:vanessa3/utils/sentry_bootstrap.dart';

/// Pelaporan error terpusat (hook ke Sentry / crash analytics di masa depan).
abstract final class AppErrorReporter {
  AppErrorReporter._();

  static void report(
    Object error, {
    StackTrace? stackTrace,
    String? context,
    Map<String, Object?>? extras,
  }) {
    final ctx = context != null ? '[$context] ' : '';
    debugPrint('AppErrorReporter: $ctx$error');
    if (stackTrace != null) {
      debugPrint(stackTrace.toString());
    }
    if (extras != null && extras.isNotEmpty) {
      debugPrint('extras: $extras');
    }
    unawaited(SentryBootstrap.capture(error, stackTrace: stackTrace, extras: extras));
  }

  static void reportApiFailure({
    required String method,
    required String path,
    int? statusCode,
    Object? error,
  }) {
    report(
      error ?? 'HTTP ${statusCode ?? '?'}',
      context: 'api',
      extras: {
        'method': method,
        'path': path,
        'statusCode': ?statusCode,
      },
    );
  }
}

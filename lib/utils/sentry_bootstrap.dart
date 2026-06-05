import 'package:flutter/foundation.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

/// Inisialisasi Sentry opsional via `--dart-define=SENTRY_DSN=...`.
abstract final class SentryBootstrap {
  SentryBootstrap._();

  static const _dsn = String.fromEnvironment('SENTRY_DSN', defaultValue: '');

  static bool get isEnabled => _dsn.trim().isNotEmpty;

  static Future<void> runApp(void Function() appRunner) async {
    if (!isEnabled) {
      appRunner();
      return;
    }

    await SentryFlutter.init(
      (options) {
        options.dsn = _dsn;
        options.environment = const String.fromEnvironment(
          'SENTRY_ENV',
          defaultValue: 'production',
        );
        options.tracesSampleRate = kDebugMode ? 1.0 : 0.2;
        options.enableAutoSessionTracking = true;
      },
      appRunner: appRunner,
    );
  }

  static Future<void> capture(
    Object error, {
    StackTrace? stackTrace,
    Map<String, Object?>? extras,
  }) async {
    if (!isEnabled) return;
    await Sentry.captureException(
      error,
      stackTrace: stackTrace,
      withScope: (scope) {
        if (extras != null) {
          for (final entry in extras.entries) {
            scope.setTag(entry.key, '${entry.value}');
          }
        }
      },
    );
  }
}

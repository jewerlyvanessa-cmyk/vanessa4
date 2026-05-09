import 'package:http/http.dart' as http;

/// Best-effort POST to debug ingest (web / when file path unavailable).
void agentAppendNdjsonLine(String line) {
  http
      .post(
        Uri.parse(
          'http://127.0.0.1:7676/ingest/e3f105c4-7929-49bc-bef6-8c05f37834ae',
        ),
        headers: const {
          'Content-Type': 'application/json',
          'X-Debug-Session-Id': 'dfc25a',
        },
        body: line,
      )
      .then((_) {}, onError: (_) {});
}

import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'agent_ndjson_io.dart' if (dart.library.html) 'agent_ndjson_web.dart'
    as agent_sink;

void agentDebugNdjson({
  required String hypothesisId,
  required String location,
  required String message,
  Map<String, Object?> data = const {},
  String runId = 'pre-fix',
}) {
  final payload = <String, dynamic>{
    'sessionId': 'dfc25a',
    'hypothesisId': hypothesisId,
    'location': location,
    'message': message,
    'data': data,
    'timestamp': DateTime.now().millisecondsSinceEpoch,
    'runId': runId,
  };
  final line = jsonEncode(payload);
  debugPrint('AGENT_NDJSON: $line');
  agent_sink.agentAppendNdjsonLine(line);
}

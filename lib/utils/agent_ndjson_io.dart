import 'dart:io';

/// Append one NDJSON line (debug instrumentation, VM/desktop/mobile).
void agentAppendNdjsonLine(String line) {
  try {
    File(
      '/Users/macbookpro2019/Documents/vanessa/vanessa 3/vanessa3/.cursor/debug-dfc25a.log',
    ).writeAsStringSync('$line\n', mode: FileMode.append, flush: true);
  } catch (_) {}
}

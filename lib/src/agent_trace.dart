import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';

const agentTraceEnabled = bool.fromEnvironment(
  'TERMINAL_USE_TRACE',
  defaultValue: kDebugMode,
);
const agentTraceRunKey = #agentTraceRun;
const agentTraceSecretsKey = #agentTraceSecrets;
const agentTraceToolKey = #agentTraceTool;

String redactTrace(String value, Iterable<String> secrets) {
  for (final secret in secrets) {
    if (secret.isNotEmpty) value = value.replaceAll(secret, '[REDACTED]');
  }
  return value.replaceAllMapped(
    RegExp(r'(Bearer\s+)[^\s"<>]+', caseSensitive: false),
    (m) => '${m[1]}[REDACTED]',
  );
}

/// Chunk complete JSON events so IDE line limits do not silently drop payloads.
void agentTrace(
  String event,
  Map<String, Object?> fields, {
  String? traceId,
  Iterable<String> secrets = const [],
}) {
  if (!agentTraceEnabled) return;
  final hidden = [
    ...?Zone.current[agentTraceSecretsKey] as List<String>?,
    ...secrets,
  ];
  Object? clean(Object? value, [String? key]) {
    if (key != null &&
        RegExp(
          r'^(authorization|x-api-key|api_?key|token|password|secret)$',
          caseSensitive: false,
        ).hasMatch(key)) {
      return '[REDACTED]';
    }
    if (value is Map) {
      return value.map((k, v) => MapEntry('$k', clean(v, '$k')));
    }
    if (value is Iterable) return value.map((v) => clean(v)).toList();
    if (value is String) return redactTrace(value, hidden);
    return value;
  }

  final record = jsonEncode(
    clean({
      'time': DateTime.now().toUtc().toIso8601String(),
      'event': event,
      'runId': Zone.current[agentTraceRunKey],
      'toolCallId': Zone.current[agentTraceToolKey],
      'traceId': traceId,
      ...fields,
    }),
  );
  final chunks = <String>[];
  for (var start = 0; start < record.length;) {
    var end = (start + 1600).clamp(0, record.length);
    if (end < record.length &&
        record.codeUnitAt(end - 1) >= 0xD800 &&
        record.codeUnitAt(end - 1) <= 0xDBFF) {
      end--;
    }
    chunks.add(record.substring(start, end));
    start = end;
  }
  for (var i = 0; i < chunks.length; i++) {
    // print is intentional: Flutter forwards it to the IDE/run console.
    // ignore: avoid_print
    print(
      '[agent-trace][$event][${traceId ?? Zone.current[agentTraceRunKey] ?? "local"}][${i + 1}/${chunks.length}] ${chunks[i]}',
    );
  }
}

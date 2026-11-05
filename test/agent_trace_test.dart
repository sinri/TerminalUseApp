import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:terminal_use_app/src/agent_trace.dart';

void main() {
  test(
    'trace preserves complete chunked payload with run and tool correlation',
    () {
      final lines = <String>[];
      final content = List.filled(2000, '中文👩‍💻').join();
      runZoned(
        () {
          agentTrace('http.request', {
            'payload': {
              'messages': [
                {'content': content},
              ],
            },
          }, traceId: 'api-test');
        },
        zoneValues: {
          agentTraceRunKey: 'run-test',
          agentTraceToolKey: 'call-test',
        },
        zoneSpecification: ZoneSpecification(
          print: (_, _, _, line) => lines.add(line),
        ),
      );
      expect(lines.length, greaterThan(1));
      final record = jsonDecode(
        lines.map((line) => line.substring(line.indexOf('] ') + 2)).join(),
      );
      expect(record['runId'], 'run-test');
      expect(record['toolCallId'], 'call-test');
      expect(record['traceId'], 'api-test');
      expect(record['payload']['messages'][0]['content'], content);
    },
  );
  test(
    'trace hides known keys, authorization and nested credential fields',
    () {
      final lines = <String>[];
      runZoned(
        () {
          agentTrace(
            'http.request',
            {
              'headers': {'Authorization': 'Bearer key-123'},
              'payload': {
                'api_key': 'another-secret',
                'messages': [
                  {'content': 'echo key-123'},
                ],
              },
            },
            secrets: ['key-123'],
          );
        },
        zoneSpecification: ZoneSpecification(
          print: (_, _, _, line) => lines.add(line),
        ),
      );
      expect(lines.join(), isNot(contains('key-123')));
      expect(lines.join(), isNot(contains('another-secret')));
      expect(lines.join(), contains('[REDACTED]'));
    },
  );
}

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:terminal_use_app/src/model_stream.dart';
import 'package:terminal_use_app/src/model_request.dart';
import 'package:terminal_use_app/src/api_request.dart';
import 'package:terminal_use_app/src/settings.dart';

String frame(Map value) => 'data: ${jsonEncode(value)}\r\n\r\n';
void delta(ModelStream stream, Map value) => stream.add('', jsonEncode(value));

void main() {
  test(
    'OpenAI preserves text, reasoning, parallel tool fragments and usage',
    () {
      final emitted = <String>[];
      final s = ModelStream(
        'openai',
        onDelta: (kind, text) => emitted.add('$kind:$text'),
      );
      delta(s, {
        'choices': [
          {
            'index': 0,
            'delta': {
              'content': '你好',
              'reasoning_content': 'reason',
              'tool_calls': [
                {
                  'index': 1,
                  'id': 'b',
                  'function': {'name': 'terminal_read', 'arguments': '{'},
                },
                {
                  'index': 0,
                  'id': 'a',
                  'function': {
                    'name': 'terminal_run',
                    'arguments': '{"command":',
                  },
                },
              ],
            },
          },
        ],
      });
      delta(s, {
        'choices': [
          {
            'index': 0,
            'delta': {
              'content': '世界',
              'reasoning_content': 'ing',
              'tool_calls': [
                {
                  'index': 0,
                  'function': {'arguments': '"pwd"}'},
                },
                {
                  'index': 1,
                  'function': {'arguments': '}'},
                },
              ],
            },
            'finish_reason': 'tool_calls',
          },
        ],
      });
      delta(s, {
        'choices': [],
        'usage': {'completion_tokens': 12},
      });
      s.add('', '[DONE]');
      final result = s.finish(), message = result['choices'][0]['message'];
      expect(message['content'], '你好世界');
      expect(message['reasoning_content'], 'reasoning');
      expect(message['tool_calls'][0]['id'], 'a');
      expect(jsonDecode(message['tool_calls'][0]['function']['arguments']), {
        'command': 'pwd',
      });
      expect(jsonDecode(message['tool_calls'][1]['function']['arguments']), {});
      expect(result['usage']['completion_tokens'], 12);
      expect(emitted, contains('text:你好'));
    },
  );
  test('Anthropic preserves text, thinking signature, tool JSON and usage', () {
    final s = ModelStream('anthropic');
    delta(s, {
      'type': 'message_start',
      'message': {
        'role': 'assistant',
        'content': [],
        'usage': {'input_tokens': 8},
      },
    });
    delta(s, {
      'type': 'content_block_start',
      'index': 0,
      'content_block': {'type': 'thinking', 'thinking': ''},
    });
    delta(s, {
      'type': 'content_block_delta',
      'index': 0,
      'delta': {'type': 'thinking_delta', 'thinking': 'thought'},
    });
    delta(s, {
      'type': 'content_block_delta',
      'index': 0,
      'delta': {'type': 'signature_delta', 'signature': 'signed'},
    });
    delta(s, {'type': 'content_block_stop', 'index': 0});
    delta(s, {
      'type': 'content_block_start',
      'index': 1,
      'content_block': {'type': 'text', 'text': ''},
    });
    delta(s, {
      'type': 'content_block_delta',
      'index': 1,
      'delta': {'type': 'text_delta', 'text': '正文'},
    });
    delta(s, {'type': 'content_block_stop', 'index': 1});
    delta(s, {
      'type': 'content_block_start',
      'index': 2,
      'content_block': {
        'type': 'tool_use',
        'id': 'call',
        'name': 'terminal_run',
        'input': {},
      },
    });
    for (final json in ['{"command":', '"pwd"}']) {
      delta(s, {
        'type': 'content_block_delta',
        'index': 2,
        'delta': {'type': 'input_json_delta', 'partial_json': json},
      });
    }
    delta(s, {'type': 'content_block_stop', 'index': 2});
    delta(s, {
      'type': 'message_delta',
      'delta': {'stop_reason': 'tool_use'},
      'usage': {'output_tokens': 9},
    });
    delta(s, {'type': 'message_stop'});
    final result = s.finish();
    expect(result['content'][0]['signature'], 'signed');
    expect(result['content'][1]['text'], '正文');
    expect(result['content'][2]['input'], {'command': 'pwd'});
    expect(result['usage'], {'input_tokens': 8, 'output_tokens': 9});
  });
  test(
    'premature EOF, missing finish reason and in-band errors are rejected',
    () {
      final s = ModelStream('openai');
      delta(s, {
        'choices': [
          {
            'delta': {
              'tool_calls': [
                {
                  'index': 0,
                  'function': {'arguments': '{"command":'},
                },
              ],
            },
          },
        ],
      });
      expect(s.finish, throwsFormatException);
      expect(() => s.add('', '[DONE]'), throwsFormatException);
      expect(
        () => s.add('error', '{"error":{"message":"overloaded"}}'),
        throwsFormatException,
      );
    },
  );
  test('SSE framing accepts heartbeat comments and multiline data', () {
    final events = <String>[];
    final f = SseFrames((event, data) => events.add('$event:$data'));
    for (final line in [
      ': heartbeat',
      'event: message',
      'data: {',
      'data: "ok":true}',
      '',
    ]) {
      f.line(line);
    }
    expect(events, ['message:{\n"ok":true}']);
  });
  test('HTTP SSE delivers split UTF8 text before completion', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final client = HttpClient();
    final release = Completer<void>(), first = Completer<void>();
    addTearDown(() async {
      if (!release.isCompleted) release.complete();
      client.close(force: true);
      await server.close(force: true);
    });
    server.listen((request) async {
      final body = jsonDecode(await utf8.decoder.bind(request).join());
      expect(body['stream'], isTrue);
      expect(request.headers.value('accept'), 'text/event-stream');
      request.response.bufferOutput = false;
      request.response.headers.contentType = ContentType(
        'text',
        'event-stream',
      );
      for (final byte in utf8.encode(
        frame({
          'choices': [
            {
              'index': 0,
              'delta': {'content': '中文👋'},
            },
          ],
        }),
      )) {
        request.response.add([byte]);
      }
      await request.response.flush();
      await release.future;
      request.response.write(
        frame({
          'choices': [
            {'index': 0, 'delta': {}, 'finish_reason': 'stop'},
          ],
        }),
      );
      request.response.write('data: [DONE]\n\n');
      await request.response.close();
    });
    final profile = LlmProfile(
      name: 'mock',
      endpoint: 'http://127.0.0.1:${server.port}',
      model: 'm',
    );
    var completed = false;
    final text = StringBuffer();
    final result =
        modelRequest(
          client,
          profile,
          {'model': 'm'},
          onDelta: (kind, part) {
            if (kind == 'text') {
              text.write(part);
              if (!first.isCompleted) first.complete();
            }
          },
        ).then((value) {
          completed = true;
          return value;
        });
    await first.future.timeout(const Duration(seconds: 3));
    expect(completed, isFalse);
    expect(text.toString(), '中文👋');
    release.complete();
    expect((await result)['choices'][0]['message']['content'], '中文👋');
  });
  test('heartbeats keep streams alive beyond the idle timeout', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final client = HttpClient();
    addTearDown(() async {
      client.close(force: true);
      await server.close(force: true);
    });
    server.listen((request) async {
      await request.drain<void>();
      request.response.bufferOutput = false;
      request.response.headers.contentType = ContentType(
        'text',
        'event-stream',
      );
      for (var i = 0; i < 8; i++) {
        request.response.write(': ping\n\n');
        await request.response.flush();
        await Future<void>.delayed(const Duration(milliseconds: 40));
      }
      request.response.write(
        frame({
          'choices': [
            {
              'delta': {'content': 'done'},
              'finish_reason': 'stop',
            },
          ],
        }),
      );
      request.response.write('data: [DONE]\n\n');
      await request.response.close();
    });
    final result = await modelRequest(
      client,
      LlmProfile(
        name: 'mock',
        endpoint: 'http://127.0.0.1:${server.port}',
        model: 'm',
      ),
      {'model': 'm'},
      timeout: const Duration(milliseconds: 200),
    );
    expect(result['choices'][0]['message']['content'], 'done');
  });
  test(
    'length is explicit; missing DONE never yields partial tool arguments',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final client = HttpClient();
      addTearDown(() async {
        client.close(force: true);
        await server.close(force: true);
      });
      var truncated = true;
      server.listen((request) async {
        await request.drain<void>();
        request.response.bufferOutput = false;
        request.response.headers.contentType = ContentType(
          'text',
          'event-stream',
        );
        request.response.write(
          frame({
            'choices': [
              {
                'delta': {
                  'tool_calls': [
                    {
                      'index': 0,
                      'id': 'call',
                      'function': {
                        'name': 'terminal_run',
                        'arguments': '{"command":',
                      },
                    },
                  ],
                },
                if (truncated) 'finish_reason': 'length',
              },
            ],
          }),
        );
        if (truncated) request.response.write('data: [DONE]\n\n');
        await request.response.close();
      });
      final p = LlmProfile(
        name: 'mock',
        endpoint: 'http://127.0.0.1:${server.port}',
        model: 'm',
      );
      await expectLater(
        modelRequest(client, p, {'model': 'm', 'max_tokens': 16384}),
        throwsA(isA<ModelOutputTruncated>()),
      );
      truncated = false;
      await expectLater(
        modelRequest(client, p, {'model': 'm'}),
        throwsA(
          isA<ApiRequestFailure>().having(
            (e) => e.details,
            'details',
            contains('提前结束'),
          ),
        ),
      );
    },
  );
}

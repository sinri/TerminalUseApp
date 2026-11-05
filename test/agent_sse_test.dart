import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:terminal_use_app/src/internal_agent.dart';
import 'package:terminal_use_app/src/settings.dart';
import 'package:terminal_use_app/src/terminal_session.dart';
import 'package:terminal_use_app/src/terminal_workspace.dart';

class StreamMemorySession extends TerminalSession {
  final writes = <String>[];
  @override
  bool get running => true;
  @override
  void write(String value) => writes.add(value);
  @override
  Map<String, dynamic> snapshot() => {'text': 'ready', 'running': true};
  @override
  void stop() {}
}

void main() {
  for (final cancel in [false, true]) {
    test(
      'Agent ${cancel ? 'cancellation' : 'completion'} with incomplete SSE tool arguments',
      () async {
        final session = StreamMemorySession();
        final workspace = TerminalWorkspace()
          ..tabs.add(TerminalTab('a', 'A', session));
        final settings = AppSettings()..autoAllow.add(CommandRisk.low);
        final agent = InternalAgent(workspace, settings: settings);
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        final partial = Completer<void>(), release = Completer<void>();
        var turns = 0, assessments = 0;
        server.listen((request) async {
          try {
            final body = jsonDecode(await utf8.decoder.bind(request).join());
            expect(body['stream'], isTrue);
            if (!body.containsKey('tools')) {
              assessments++;
              request.response.headers.contentType = ContentType.json;
              request.response.write(
                jsonEncode({
                  'choices': [
                    {
                      'finish_reason': 'stop',
                      'message': {
                        'content': jsonEncode({
                          'syntax': 'valid',
                          'syntax_reason': 'valid',
                          'level': 'low',
                          'explanation': 'read',
                          'reason': 'read',
                        }),
                      },
                    },
                  ],
                }),
              );
            } else {
              turns++;
              request.response.bufferOutput = false;
              request.response.headers.contentType = ContentType(
                'text',
                'event-stream',
                charset: 'utf-8',
              );
              void send(Map event) =>
                  request.response.write('data: ${jsonEncode(event)}\n\n');
              if (turns == 1) {
                send({
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
                    },
                  ],
                });
                await request.response.flush();
                partial.complete();
                await release.future;
                send({
                  'choices': [
                    {
                      'delta': {
                        'tool_calls': [
                          {
                            'index': 0,
                            'function': {'arguments': '"pwd"}'},
                          },
                        ],
                      },
                      'finish_reason': 'tool_calls',
                    },
                  ],
                });
              } else {
                send({
                  'choices': [
                    {
                      'delta': {'content': '已完成'},
                      'finish_reason': 'stop',
                    },
                  ],
                });
              }
              request.response.write('data: [DONE]\n\n');
            }
            await request.response.close();
          } on IOException {
            /* The cancelled client closes its response socket. */
          }
        });
        try {
          final run = agent.run(
            LlmProfile(
              name: 'mock',
              endpoint: 'http://127.0.0.1:${server.port}',
              model: 'mock',
            ),
            'inspect',
            'a',
            SkillCatalog(''),
          );
          await partial.future.timeout(const Duration(seconds: 3));
          expect(session.writes, isEmpty);
          expect(assessments, 0);
          if (cancel) {
            agent.stop();
            await run.timeout(const Duration(seconds: 3));
            expect(session.writes, isEmpty);
            expect(assessments, 0);
          } else {
            release.complete();
            await run;
            expect(session.writes, ['pwd\r']);
            expect(assessments, 1);
            final text = agent.log.whereType<AgentText>().single;
            expect(text.text, '已完成');
            expect(text.complete, isTrue);
          }
          expect(agent.running, isFalse);
        } finally {
          if (!release.isCompleted) release.complete();
          agent.dispose();
          workspace.dispose();
          await server.close(force: true);
        }
      },
    );
  }
}

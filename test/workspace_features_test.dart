import 'dart:convert';
import 'dart:async';
import 'package:terminal_use_app/src/card_text.dart';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:terminal_use_app/src/settings.dart';
import 'package:terminal_use_app/src/terminal_approval.dart';
import 'package:terminal_use_app/src/internal_agent.dart';
import 'package:terminal_use_app/src/terminal_session.dart';
import 'package:terminal_use_app/src/terminal_workspace.dart';

class MemorySession extends TerminalSession {
  final inputs = <String>[];
  @override
  bool get running => true;
  @override
  void write(String data) => inputs.add(data);
  @override
  Map<String, dynamic> snapshot() => {'text': 'ready', 'running': true};
  @override
  void stop() {}
}

void main() {
  for (final protocol in ['openai', 'anthropic']) {
    test(
      '$protocol truncated assessment never authorizes even valid partial JSON',
      () async {
        final session = MemorySession();
        final workspace = TerminalWorkspace()
          ..tabs.add(TerminalTab('a', 'test', session));
        final settings = AppSettings()..autoAllow.addAll(CommandRisk.values);
        final agent = InternalAgent(workspace, settings: settings);
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        server.listen((request) async {
          final body = jsonDecode(await utf8.decoder.bind(request).join());
          expect(body['max_tokens'], 16384);
          // Provider-specific extensions must not leak to arbitrary services.
          expect(body.containsKey('thinking'), isFalse);
          final risk = jsonEncode({
            'syntax': 'valid',
            'syntax_reason': 'valid',
            'level': 'low',
            'explanation': 'read',
            'reason': 'read',
          });
          request.response.write(
            jsonEncode(
              protocol == 'openai'
                  ? {
                      'choices': [
                        {
                          'finish_reason': 'length',
                          'message': {'content': risk},
                        },
                      ],
                      'usage': {'completion_tokens': 16384},
                    }
                  : {
                      'stop_reason': 'max_tokens',
                      'content': [
                        {'type': 'text', 'text': risk},
                      ],
                      'usage': {'output_tokens': 16384},
                    },
            ),
          );
          await request.response.close();
        });
        final profile = LlmProfile(
          name: 'mock',
          endpoint: 'http://127.0.0.1:${server.port}/v1',
          model: 'mock',
          protocol: protocol,
        );
        try {
          await expectLater(
            agent.approvals.check(
              workspace.require('a'),
              'terminal_run',
              'pwd\r',
              (profile, 'mock'),
            ),
            throwsA(
              isA<RiskAssessmentFailure>().having(
                (e) => e.message,
                'message',
                contains('token 上限'),
              ),
            ),
          );
          expect(session.inputs, isEmpty);
          expect(agent.approvals.pending, isNull);
          expect(agent.log.whereType<ApprovedOperation>(), isEmpty);
        } finally {
          agent.dispose();
          workspace.dispose();
          await server.close(force: true);
        }
      },
    );
  }

  test(
    'empty risk assessment ends the turn without writing and permits another message',
    () async {
      final session = MemorySession();
      final workspace = TerminalWorkspace()
        ..tabs.add(TerminalTab('a', 'test', session));
      final agent = InternalAgent(workspace);
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      var requests = 0;
      server.listen((request) async {
        await request.drain<void>();
        requests++;
        final message = requests == 1
            ? {
                'tool_calls': [
                  {
                    'id': 'call-1',
                    'type': 'function',
                    'function': {
                      'name': 'terminal_run',
                      'arguments': '{"command":"pwd"}',
                    },
                  },
                ],
              }
            : {'content': requests == 2 ? '' : '可以继续'};
        request.response.write(
          jsonEncode({
            'choices': [
              {'message': message},
            ],
          }),
        );
        await request.response.close();
      });
      final profile = LlmProfile(
        name: 'mock',
        endpoint: 'http://127.0.0.1:${server.port}/v1/chat/completions',
        model: 'mock',
      );
      try {
        await agent.run(profile, 'inspect', 'a', SkillCatalog(''));
        expect(requests, 2);
        expect(session.inputs, isEmpty);
        expect(agent.running, isFalse);
        expect(agent.activeTool, isNull);
        expect(agent.approvals.pending, isNull);
        expect(agent.status, contains('可以继续输入'));
        expect(
          agent.log.whereType<ToolActivity>().single.result,
          contains('没有返回风险评估正文'),
        );
        await agent.run(profile, '继续', 'a', SkillCatalog(''));
        expect(requests, 3);
        expect(agent.log.last, '可以继续');
        expect(agent.running, isFalse);
      } finally {
        agent.dispose();
        workspace.dispose();
        await server.close(force: true);
      }
    },
  );

  test(
    'tool cards format transport fields while preserving literal output',
    () {
      expect(
        toolResultText('terminal_list', {
          'terminals': [
            {'id': 't1', 'name': '开发', 'running': true},
          ],
        }),
        '开发（t1） · 运行中',
      );
      expect(
        toolResultText('terminal_read', {'text': '{"literal":true}\n第二行'}),
        '{"literal":true}\n第二行',
      );
      expect(displayInput('echo "hello"\r'), 'echo "hello"⟨回车⟩');
    },
  );
  test(
    'card text preserves terminal glyphs and whole emoji, exposing hidden keys',
    () {
      expect(displayInput('中文  👩🏽‍💻\r\u0085'), '中文  👩🏽‍💻⟨回车⟩\\u0085');
      expect(textTail('长日志👩🏽‍💻', 1, '…'), '…👩🏽‍💻');
      expect(visibleControls('第一行\n第二行'), '第一行\n第二行');
    },
  );
  test(
    'auto-approval matches only the configured risk and requires a complete assessment',
    () async {
      final settings = AppSettings();
      final agent = InternalAgent(TerminalWorkspace(), settings: settings);
      final tab = TerminalTab('a', 'target', MemorySession());
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      var level = CommandRisk.low;
      var complete = true;
      var syntax = 'valid';
      server.listen((req) async {
        final request = jsonDecode(await utf8.decoder.bind(req).join());
        final messages = request['messages'] as List;
        expect(messages.length, 2);
        expect(jsonDecode(messages.last['content']), {
          'tool': 'terminal_run',
          'input': 'command',
        });
        expect(request.containsKey('tools'), isFalse);
        req.response.write(
          jsonEncode({
            'choices': [
              {
                'message': {
                  'content': jsonEncode({
                    'level': level.name,
                    'reason': '判定理由',
                    'syntax': syntax,
                    'syntax_reason': '测试语法结论',
                    if (complete) 'explanation': '命令作用',
                  }),
                },
              },
            ],
          }),
        );
        await req.response.close();
      });
      var manual = 0;
      agent.approvals.addListener(() {
        final review = agent.approvals.pending;
        if (review != null) {
          expect(review.explanation, '命令作用');
          manual++;
          agent.approvals.decide(review, true);
        }
      });
      final profile = LlmProfile(
        name: 'test',
        model: 'mock',
        endpoint: 'http://127.0.0.1:${server.port}',
        auth: 'none',
      );
      Future<void> check() => agent.approvals.check(
        tab,
        'terminal_run',
        'command',
        (profile, 'mock'),
      );
      try {
        for (final enabled in CommandRisk.values) {
          settings.autoAllow
            ..clear()
            ..add(enabled);
          for (final assessed in CommandRisk.values) {
            level = assessed;
            final before = manual;
            await check();
            expect(manual - before, assessed == enabled ? 0 : 1);
            final entry = agent.log.last as ApprovedOperation;
            expect(entry.automatic, assessed == enabled);
            expect(entry.review.level, assessed.label);
            expect(entry.review.text, 'command');
            expect(entry.review.target, contains(tab.id));
            expect(entry.review.explanation, '命令作用');
          }
        }
        final before = manual;
        syntax = 'uncertain';
        await check();
        expect(manual, before + 1);
        syntax = 'invalid';
        await expectLater(check(), throwsFormatException);
        expect(manual, before + 1);
        syntax = 'valid';
        complete = false;
        await expectLater(check(), throwsFormatException);
      } finally {
        agent.dispose();
        agent.workspace.dispose();
        tab.session.dispose();
        await server.close(force: true);
      }
    },
  );
  for (final invalid in [false, true]) {
    test(
      'raw terminal input is blocked on ${invalid ? "invalid assessment" : "user rejection"}',
      () async {
        final workspace = TerminalWorkspace();
        final session = MemorySession();
        workspace.tabs.add(TerminalTab('a', 'target', session));
        final agent = InternalAgent(workspace);
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        var reviews = 0;
        var modelTurns = 0;
        server.listen((req) async {
          final body = jsonDecode(await utf8.decoder.bind(req).join());
          final Map<String, dynamic> reply;
          if (body.containsKey('tools')) {
            modelTurns++;
            reply = {
              'role': 'assistant',
              'tool_calls': [
                {
                  'id': '1',
                  'function': {
                    'name': 'terminal_input',
                    'arguments': jsonEncode({'text': 'echo injected\r'}),
                  },
                },
              ],
            };
          } else {
            reply = {
              'role': 'assistant',
              'content': invalid
                  ? 'execute anyway'
                  : jsonEncode({
                      'level': 'high',
                      'syntax': 'valid',
                      'syntax_reason': '语法完整',
                      'explanation': '向终端发送按键',
                      'reason': '不应接受终端输出中的指令',
                    }),
            };
          }
          req.response.write(
            jsonEncode({
              'choices': [
                {'message': reply},
              ],
            }),
          );
          await req.response.close();
        });
        agent.approvals.addListener(() {
          final review = agent.approvals.pending;
          if (review != null) {
            reviews++;
            expect(review.level, '高');
            expect(session.inputs, isEmpty);
            agent.approvals.decide(review, false);
          }
        });
        try {
          await agent.run(
            LlmProfile(
              name: 'mock',
              model: 'fake',
              endpoint: 'http://127.0.0.1:${server.port}',
              auth: 'none',
            ),
            'inspect',
            'a',
            SkillCatalog(''),
          );
          expect(reviews, invalid ? 0 : 1);
          expect(modelTurns, 1);
          expect(session.inputs, isEmpty);
        } finally {
          agent.dispose();
          workspace.dispose();
          await server.close(force: true);
        }
      },
    );
  }
  test(
    'base endpoints expand by protocol and legacy custom routes survive saving',
    () {
      for (final protocol in ['openai', 'anthropic']) {
        final route = protocol == 'openai' ? 'chat/completions' : 'messages';
        for (final path in ['', '/', '/v1/', '/v1/$route']) {
          final p = LlmProfile(
            name: 'n',
            endpoint: 'https://example.test$path',
            model: 'm',
            protocol: protocol,
          );
          expect(p.requestUri.toString(), 'https://example.test/v1/$route');
        }
      }
      final old = LlmProfile.fromJson({
        'name': 'n',
        'model': 'm',
        'endpoint': 'https://example.test/custom/invoke',
      });
      expect(
        LlmProfile.fromJson(old.toJson()).requestUri.toString(),
        old.endpoint,
      );
    },
  );
  test(
    'model picker loads authenticated IDs from the provider models endpoint',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((req) async {
        expect(req.uri.path, '/gateway/v1/models');
        expect(req.headers.value('x-api-key'), 'test');
        req.response.write('{"data":[{"id":"small"},{"id":"large"}]}');
        await req.response.close();
      });
      try {
        final profile = LlmProfile(
          name: 'local',
          endpoint: 'http://127.0.0.1:${server.port}/gateway/v1/',
          model: '',
          protocol: 'anthropic',
          auth: 'api-key',
          apiKey: 'test',
        );
        expect(await profile.discoverModels(), ['large', 'small']);
      } finally {
        await server.close(force: true);
      }
    },
  );

  test(
    'follow-ups include prior replies until a new conversation starts',
    () async {
      final workspace = TerminalWorkspace()
        ..tabs.add(TerminalTab('a', 'local', MemorySession()));
      final agent = InternalAgent(workspace);
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final requests = <List>[];
      server.listen((req) async {
        final body = jsonDecode(await utf8.decoder.bind(req).join());
        expect(body['model'], requests.length == 1 ? 'large' : 'test');
        requests.add(body['messages'] as List);
        req.response.write(
          '{"choices":[{"message":{"role":"assistant","content":"disk ready"}}]}',
        );
        await req.response.close();
      });
      final profile = LlmProfile(
        name: 'local',
        endpoint: 'http://127.0.0.1:${server.port}/v1/chat/completions',
        model: 'test',
        auth: 'none',
      );
      try {
        await agent.run(profile, 'inspect', 'a', SkillCatalog(''));
        final restored = LlmProfile.fromJson({
          ...profile.toJson(),
          'additionalModels': ['large'],
        });
        expect(restored.modelIds, ['test', 'large']);
        await agent.run(
          restored,
          'explain',
          'a',
          SkillCatalog(''),
          modelId: restored.modelIds.last,
        );
        expect(requests.last.map((m) => m['content']), contains('disk ready'));
        agent.newConversation();
        expect(agent.log, isEmpty);
        await agent.run(profile, 'another task', 'a', SkillCatalog(''));
        expect(
          requests.last.map((m) => m['content']),
          isNot(contains('disk ready')),
        );
      } finally {
        agent.dispose();
        workspace.dispose();
        await server.close(force: true);
      }
    },
  );
  test(
    'SSH validates options and supports interactive password authentication',
    () {
      expect(
        () => SshProfile(name: 'bad', host: '-oProxyCommand=bad').arguments,
        throwsFormatException,
      );
      expect(
        () => SshProfile(name: 'bad', host: 'host', port: 65536).arguments,
        throwsFormatException,
      );
      final p = SshProfile(
        name: 'prod',
        host: 'example.test',
        user: 'alice',
        key: '/tmp/key with spaces',
      );
      expect(
        p.arguments,
        containsAll([
          'ServerAliveInterval=30',
          'ServerAliveCountMax=3',
          '/tmp/key with spaces',
          'alice',
        ]),
      );
      final password = SshProfile(name: 'pass', host: 'host', password: true);
      expect(password.arguments, contains('PubkeyAuthentication=no'));
      expect(password.toJson().keys, isNot(contains('secret')));
    },
  );
  test(
    'settings round trip preserves multiple profiles and protects local file',
    () async {
      final dir = await Directory.systemTemp.createTemp(
        'terminal-settings-test-',
      );
      try {
        final file = File('${dir.path}/config/settings.json');
        final settings = AppSettings()..skillRoot = '~/skills';
        settings.ssh.add(SshProfile(name: 'host', host: 'host'));
        settings.models.addAll([
          LlmProfile(
            name: 'one',
            endpoint: 'https://example.test/v1/chat/completions',
            model: 'model',
            apiKey: 'secret',
          ),
          LlmProfile(
            name: 'two',
            endpoint: 'http://localhost/v1/messages',
            model: 'other',
            protocol: 'anthropic',
            auth: 'api-key',
          ),
        ]);
        settings.autoAllow.add(CommandRisk.medium);
        final firstSave = settings.save(file: file);
        settings.skillRoot = '~/updated-skills';
        final secondSave = settings.save(file: file);
        await Future.wait([firstSave, secondSave]);
        final loaded = AppSettings();
        await loaded.load(file: file);
        expect(loaded.models.map((v) => v.name), ['one', 'two']);
        expect(loaded.models.first.apiKey, 'secret');
        expect(loaded.ssh.single.host, 'host');
        expect(loaded.autoAllow, {CommandRisk.medium});
        expect(loaded.skillRoot, '~/updated-skills');
        if (!Platform.isWindows) expect((await file.stat()).mode & 511, 384);
      } finally {
        await dir.delete(recursive: true);
      }
    },
  );
  test(
    'skills discover nested entries, reject traversal and outside links',
    () async {
      final dir = await Directory.systemTemp.createTemp(
        'terminal-skills-test-',
      );
      try {
        final root = Directory('${dir.path}/root');
        await Directory('${root.path}/nested').create(recursive: true);
        final skill = File('${root.path}/nested/SKILL.md');
        await skill.writeAsString(
          '---\nname: inspect\ndescription: Inspect services\n---\nRead status first.',
        );
        final outside = File('${dir.path}/SKILL.md');
        await outside.writeAsString('outside');
        await Link('${root.path}/linked').create(dir.path);
        final catalog = SkillCatalog(root.path);
        await catalog.discover();
        expect(catalog.entries.single.name, 'inspect');
        expect(await catalog.read('inspect'), contains('Read status first.'));
        await expectLater(catalog.read('../SKILL.md'), throwsStateError);
        await skill.delete();
        await Link(skill.path).create(outside.path);
        await expectLater(catalog.read('inspect'), throwsStateError);
      } finally {
        await dir.delete(recursive: true);
      }
    },
  );
  for (final closeTarget in [false, true]) {
    test(
      '${closeTarget ? "closing the bound tab" : "stopping the agent"} cancels an in-flight request',
      () async {
        final workspace = TerminalWorkspace();
        final terminal = MemorySession();
        workspace.tabs.add(TerminalTab('a', 'A', terminal));
        final agent = InternalAgent(workspace);
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        final received = Completer<void>();
        server.listen((req) async {
          await req.drain<void>();
          received.complete();
        });
        try {
          final run = agent.run(
            LlmProfile(
              name: 'slow',
              endpoint: 'http://127.0.0.1:${server.port}/api',
              model: 'fake',
              auth: 'none',
            ),
            'check',
            'a',
            SkillCatalog(''),
          );
          await received.future.timeout(const Duration(seconds: 5));
          if (closeTarget) {
            workspace.close('a');
          } else {
            agent.stop();
          }
          await run.timeout(const Duration(seconds: 5));
          expect(agent.running, isFalse);
          expect(terminal.inputs, isEmpty);
          expect(agent.log.last, contains('已停止'));
        } finally {
          agent.dispose();
          workspace.dispose();
          await server.close(force: true);
        }
      },
    );
  }
  for (final protocol in ['openai', 'anthropic']) {
    test(
      '$protocol agent executes tools on bound target and handles protocol results',
      () async {
        final workspace = TerminalWorkspace();
        final first = MemorySession(), second = MemorySession();
        workspace.tabs.addAll([
          TerminalTab('a', 'A', first),
          TerminalTab('b', 'B', second),
        ]);
        workspace.selectedId = 'b';
        final agent = InternalAgent(workspace);
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        var calls = 0;
        agent.approvals.addListener(() {
          final review = agent.approvals.pending;
          if (review != null) {
            expect(first.inputs, isEmpty);
            expect(review.level, '低');
            expect(review.text, 'pwd\r');
            agent.approvals.decide(review, true);
          }
        });
        server.listen((req) async {
          final body = jsonDecode(await utf8.decoder.bind(req).join());
          if (protocol == 'anthropic') {
            expect(req.headers.value('x-api-key'), 'test-key');
            expect(req.headers.value('anthropic-version'), '2023-06-01');
          } else {
            expect(req.headers.value('authorization'), 'Bearer test-key');
          }
          if (!body.containsKey('tools')) {
            final risk = jsonEncode({
              'level': 'low',
              'syntax': 'valid',
              'syntax_reason': '语法完整',
              'explanation': '显示当前目录路径',
              'reason': '读取工作目录',
            });
            req.response.write(
              jsonEncode(
                protocol == 'anthropic'
                    ? {
                        'content': [
                          {'type': 'text', 'text': risk},
                        ],
                      }
                    : {
                        'choices': [
                          {
                            'message': {'content': risk},
                          },
                        ],
                      },
              ),
            );
            await req.response.close();
            return;
          }
          expect(body['model'], 'fake');
          final prompt =
              (body['messages'] as List).firstWhere(
                    (m) => m['role'] == 'user',
                  )['content']
                  as String;
          expect(prompt, contains('"active_tab":{"id":"b","name":"B"}'));
          expect(prompt, contains('"authorized_tab":{"id":"a","name":"A"}'));
          calls++;
          final anthropic = protocol == 'anthropic';
          if (calls == 1) {
            final response = anthropic
                ? {
                    'content': [
                      {
                        'type': 'tool_use',
                        'id': 'call-1',
                        'name': 'terminal_run',
                        'input': {'terminal_id': 'a', 'command': 'pwd'},
                      },
                    ],
                  }
                : {
                    'choices': [
                      {
                        'message': {
                          'role': 'assistant',
                          'content': null,
                          'reasoning_content': 'tool reasoning to preserve',
                          'tool_calls': [
                            {
                              'id': 'call-1',
                              'type': 'function',
                              'function': {
                                'name': 'terminal_run',
                                'arguments': jsonEncode({
                                  'terminal_id': 'a',
                                  'command': 'pwd',
                                }),
                              },
                            },
                          ],
                        },
                      },
                    ],
                  };
            req.response.write(jsonEncode(response));
          } else {
            expect(jsonEncode(body['messages']), contains('call-1'));
            expect(jsonEncode(body['messages']), contains('ok'));
            if (!anthropic) {
              expect(
                (body['messages'] as List).firstWhere(
                  (m) => m['role'] == 'assistant',
                )['reasoning_content'],
                'tool reasoning to preserve',
              );
            }
            req.response.write(
              jsonEncode(
                anthropic
                    ? {
                        'content': [
                          {'type': 'text', 'text': 'done'},
                        ],
                      }
                    : {
                        'choices': [
                          {
                            'message': {'role': 'assistant', 'content': 'done'},
                          },
                        ],
                      },
              ),
            );
          }
          await req.response.close();
        });
        try {
          await agent.run(
            LlmProfile(
              name: 'fake',
              endpoint: 'http://127.0.0.1:${server.port}/api',
              model: 'fake',
              apiKey: 'test-key',
              auth: protocol == 'anthropic' ? 'api-key' : 'bearer',
              protocol: protocol,
            ),
            'check',
            'a',
            SkillCatalog(''),
          );
          expect(calls, 2);
          expect(first.inputs, ['pwd\r']);
          expect(second.inputs, isEmpty);
          expect(agent.log.last, 'done');
          final activity = agent.log.whereType<ToolActivity>().single;
          expect(activity.approval!.review.text, 'pwd\r');
          expect(activity.result, '命令已提交，请读取终端确认执行结果。');
          expect(agent.log.whereType<ApprovedOperation>(), isEmpty);
          await expectLater(
            agent.execute(
              'terminal_input',
              {'terminal_id': 'b', 'text': 'bad'},
              'a',
              SkillCatalog(''),
            ),
            throwsStateError,
          );
          workspace.close('a');
          await expectLater(
            agent.execute('terminal_read', {}, 'a', SkillCatalog('')),
            throwsStateError,
          );
        } finally {
          agent.dispose();
          workspace.dispose();
          await server.close(force: true);
        }
      },
    );
  }
}

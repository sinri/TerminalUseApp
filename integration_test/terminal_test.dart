import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:integration_test/integration_test.dart';
import 'package:terminal_use_app/main.dart';
import 'package:terminal_use_app/src/agent_server.dart';
import 'package:terminal_use_app/src/agent_launcher.dart';
import 'package:terminal_use_app/src/terminal_session.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('desktop workspace renders', (tester) async {
    await tester.pumpWidget(const TerminalUseApp());
    await tester.pump(const Duration(seconds: 2));
    expect(find.text('TERMINAL USE'), findsOneWidget);
    expect(find.text('Agent bridge ready'), findsOneWidget);
    expect(find.text('启动 OpenCode'), findsOneWidget);
    expect(find.text('启动 Codex'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    await tester.tap(find.text('高级：其他启动命令'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(TextField), findsOneWidget);
    await tester.ensureVisible(find.byType(TextField));
    expect(tester.takeException(), isNull);
  });
  testWidgets('MCP bridge controls a real PTY with persistent shell state', (
    tester,
  ) async {
    final terminal = TerminalSession();
    final server = AgentServer(
      read: terminal.snapshot,
      write: terminal.write,
      interrupt: terminal.interrupt,
    );
    try {
      terminal.start();
      await server.start();
      final bridge = Process.start('python3', [
        '${Directory.current.path}/tools/terminal_bridge.py',
        'mcp',
      ], environment: server.environment);
      await tester.runAsync(() async {
        final process = await bridge;
        final replies = process.stdout
            .transform(utf8.decoder)
            .transform(const LineSplitter())
            .map((line) => jsonDecode(line) as Map<String, dynamic>);
        final iterator = StreamIterator<Map<String, dynamic>>(replies);
        Future<Map<String, dynamic>> call(
          int id,
          String name,
          Map<String, dynamic> args,
        ) async {
          process.stdin.writeln(
            jsonEncode({
              'jsonrpc': '2.0',
              'id': id,
              'method': 'tools/call',
              'params': {'name': name, 'arguments': args},
            }),
          );
          expect(
            await iterator.moveNext().timeout(const Duration(seconds: 10)),
            isTrue,
          );
          final reply = iterator.current;
          expect(reply['result']['isError'], isNot(true));
          return jsonDecode(reply['result']['content'][0]['text'])
              as Map<String, dynamic>;
        }

        try {
          await call(1, 'terminal_input', {
            'text': "export TERMINAL_USE_SMOKE=shared_state\r",
          });
          await Future<void>.delayed(const Duration(milliseconds: 500));
          await call(2, 'terminal_input', {
            'text': "printf 'CHECK:%s:END\\n' \"\u0024TERMINAL_USE_SMOKE\"\r",
          });
          var found = false;
          for (var i = 0; i < 30; i++) {
            await Future<void>.delayed(const Duration(milliseconds: 100));
            final state = await call(3 + i, 'terminal_read', {});
            if ((state['text'] as String).contains('CHECK:shared_state:END')) {
              found = true;
              break;
            }
          }
          expect(
            found,
            isTrue,
            reason: 'MCP input must execute in the same persistent PTY',
          );
        } finally {
          await process.stdin.close();
          process.kill();
          await iterator.cancel();
        }
      });
    } finally {
      await server.close();
      terminal.dispose();
    }
  });
  if (const bool.fromEnvironment('TEST_INSTALLED_AGENTS')) {
    for (final choice in BuiltInAgent.values) {
      testWidgets('${choice.name} discovers bundled MCP tools', (tester) async {
        final shell = TerminalSession();
        final cli = TerminalSession();
        final api = AgentServer(
          read: shell.snapshot,
          write: shell.write,
          interrupt: shell.interrupt,
        );
        AgentLaunch? launch;
        try {
          shell.start();
          await tester.runAsync(() async {
            await api.start();
            launch = await AgentLauncher.prepare(choice, api.environment);
          });
          cli.start(
            executable: launch!.executable,
            arguments: launch!.arguments,
            environment: launch!.environment,
          );
          await tester.runAsync(() async {
            final marker = File(
              launch!.environment['TERMINAL_USE_MCP_STATUS']!,
            );
            var connected = false;
            for (var i = 0; i < 100; i++) {
              await Future<void>.delayed(const Duration(milliseconds: 200));
              if (await marker.exists() &&
                  (await marker.readAsString()).contains('tools_listed')) {
                connected = true;
                break;
              }
            }
            expect(
              connected,
              isTrue,
              reason: '${choice.name} output: ${cli.terminal.buffer.getText()}',
            );
          });
        } finally {
          cli.dispose();
          shell.dispose();
          await tester.runAsync(() async {
            await api.close();
            await launch?.dispose();
          });
        }
      });
    }
  }
}

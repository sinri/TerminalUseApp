import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:integration_test/integration_test.dart';
import 'package:terminal_use_app/main.dart';
import 'package:terminal_use_app/src/internal_agent_view.dart';
import 'package:terminal_use_app/src/settings.dart';
import 'package:terminal_use_app/src/mac_controls.dart';
import 'package:terminal_use_app/src/agent_server.dart';
import 'package:terminal_use_app/src/terminal_session.dart';
import 'package:terminal_use_app/src/terminal_workspace.dart';

Future<dynamic> nativeEdit(String action) async {
  const codec = StandardMethodCodec();
  final reply = Completer<ByteData?>();
  ServicesBinding.instance.channelBuffers.push(
    'terminal_use/lifecycle',
    codec.encodeMethodCall(MethodCall('edit:$action')),
    reply.complete,
  );
  return codec.decodeEnvelope((await reply.future)!);
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('desktop workspace renders', (tester) async {
    await tester.pumpWidget(const TerminalUseApp());
    await tester.pump(const Duration(seconds: 2));
    final send = find.text('发送');
    final input = find.byType(TextField);
    final grip = find.byKey(const Key('agent-input-divider'));
    final contextBox = find.byKey(const Key('agent-context'));
    final initialHeight = tester.getSize(input).height;
    expect(initialHeight, 112);
    final initialPanel = tester.widget<InternalAgentView>(
      find.byType(InternalAgentView),
    );
    expect(initialPanel.workspace.tabs, isEmpty);
    expect(find.text('0 个终端'), findsOneWidget);
    expect(find.text('无活跃 Tab'), findsOneWidget);
    expect(
      tester.widget<MacButton>(find.widgetWithText(MacButton, '发送')).onPressed,
      isNull,
    );
    await tester.tap(find.text('新建终端'));
    await tester.pump();
    expect(find.text('当前 Tab：Terminal 1（terminal-1）'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 300));
    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: '中文',
        selection: TextSelection.collapsed(offset: 2),
        composing: TextRange(start: 0, end: 2),
      ),
    );
    await tester.pump();
    expect(
      initialPanel.workspace.selected!.session.snapshot()['text'],
      isNot(contains('中文')),
    );
    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: '中文',
        selection: TextSelection.collapsed(offset: 2),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      initialPanel.workspace.selected!.session.snapshot()['text'],
      contains('中文'),
    );
    initialPanel.workspace.selected!.session.interrupt();

    final previousClipboard = await Clipboard.getData(Clipboard.kTextPlain);
    try {
      await Clipboard.setData(const ClipboardData(text: 'echo NATIVE_CLIP_中文'));
      expect(await nativeEdit('paste'), isTrue);
      initialPanel.workspace.selected!.session.write('\r');
      await tester.pump(const Duration(milliseconds: 300));
      expect(
        initialPanel.workspace.selected!.session.snapshot()['text'],
        contains('NATIVE_CLIP_中文'),
      );
      await tester.tap(find.text('Terminal 1'));
      await tester.pump(const Duration(milliseconds: 100));
      expect(await nativeEdit('selectAll'), isTrue);
      expect(await nativeEdit('copy'), isTrue);
      expect(
        (await Clipboard.getData(Clipboard.kTextPlain))?.text,
        contains('NATIVE_CLIP_中文'),
      );
      await tester.tap(input);
      await tester.pump();
      await Clipboard.setData(const ClipboardData(text: 'AGENT_CLIP_中文'));
      expect(
        await nativeEdit('paste'),
        isTrue,
        reason: 'Native editing must route to the focused Agent text field',
      );
      await tester.pump();
      expect(
        tester.widget<TextField>(input).controller?.text,
        contains('AGENT_CLIP_中文'),
      );
      await tester.enterText(input, '');
    } finally {
      await Clipboard.setData(
        ClipboardData(text: previousClipboard?.text ?? ''),
      );
    }

    await tester.drag(grip, const Offset(0, -1000));
    await tester.pump();
    expect(tester.getSize(input).height, greaterThan(initialHeight));
    expect(
      tester.getSize(contextBox).height,
      greaterThanOrEqualTo(
        tester.getSize(find.byType(InternalAgentView)).height / 2,
      ),
    );
    await tester.drag(grip, const Offset(0, 1000));
    await tester.pump();
    expect(tester.getSize(input).height, lessThanOrEqualTo(initialHeight));
    final tabsDivider = find.byKey(const Key('tabs-divider'));
    final tabsX = tester.getTopLeft(tabsDivider).dx;
    final agentX = tester.getTopLeft(input).dx;
    await tester.drag(tabsDivider, const Offset(80, 0));
    await tester.pump();
    expect(tester.getTopLeft(tabsDivider).dx, greaterThan(tabsX));
    expect(tester.getTopLeft(input).dx, agentX);
    await tester.drag(tabsDivider, const Offset(-160, 0));
    await tester.pump();
    expect(tester.getTopLeft(tabsDivider).dx, lessThan(tabsX));
    final initialX = tester.getTopLeft(input).dx;
    expect(tester.getTopLeft(find.byTooltip('新建终端')).dx, lessThan(initialX));
    expect(
      tester.getTopLeft(input).dy,
      greaterThan(tester.getTopLeft(find.text('一起处理终端任务')).dy),
    );
    await tester.drag(
      find.byKey(const Key('panel-divider')),
      const Offset(-60, 0),
    );
    await tester.pump();
    expect(tester.getTopLeft(input).dx, lessThan(initialX));
    await tester.tap(find.byTooltip('新建终端'));
    await tester.pump();
    expect(find.text('Terminal 2'), findsOneWidget);
    expect(find.text('当前 Tab：Terminal 2（terminal-2）'), findsOneWidget);
    // New-terminal focus is applied after its first frame.
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(input);
    await tester.pump(const Duration(milliseconds: 100));
    await tester.enterText(input, '请检查 @');
    await tester.pump();
    expect(tester.widget<TextField>(input).controller!.text, '请检查 @');
    await tester.tap(find.widgetWithText(ListTile, 'terminal-1'));
    await tester.pump();
    expect(
      tester.widget<TextField>(input).controller!.text,
      '请检查 @terminal-1 ',
    );
    await tester.tap(find.byTooltip('打开 SSH'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('管理 SSH 入口'));
    await tester.pumpAndSettle();
    expect(find.text('添加 SSH 入口'), findsOneWidget);
    expect(find.text('添加 LLM 配置'), findsNothing);
    await tester.tap(find.byTooltip('关闭设置'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Agent 设置'));
    await tester.pumpAndSettle();
    expect(find.text('添加 LLM 配置'), findsOneWidget);
    expect(find.text('添加 SSH 入口'), findsNothing);
    await tester.tap(find.byTooltip('关闭设置'));
    await tester.pumpAndSettle();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.comma);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pumpAndSettle();
    expect(find.byTooltip('关闭设置'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byTooltip('关闭设置'), findsNothing);
    await tester.enterText(input, '检查磁盘');
    await tester.tap(find.byTooltip('新建 Agent 会话'));
    await tester.pump();
    expect(find.text('检查磁盘'), findsNothing);
    tester.view.physicalSize = const Size(720, 640);
    tester.view.devicePixelRatio = 1;
    await tester.pump();
    expect(send, findsOneWidget);
    expect(tester.takeException(), isNull);
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
    await tester.pump();
    await tester.tap(find.text('Terminal 1'));
    await tester.pump();
    await tester.tap(find.byTooltip('关闭 Terminal 1'));
    await tester.pump();
    await tester.tap(find.byTooltip('关闭 Terminal 2'));
    await tester.pump();
    expect(initialPanel.workspace.tabs, isEmpty);
    expect(find.text('新建终端'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  });
  testWidgets('approval stays in conversation while settings remain usable', (
    tester,
  ) async {
    await tester.pumpWidget(const TerminalUseApp());
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(find.byTooltip('新建终端'));
    await tester.pump();
    final panel = tester.widget<InternalAgentView>(
      find.byType(InternalAgentView),
    );
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      await request.drain<void>();
      request.response.write(
        jsonEncode({
          'choices': [
            {
              'message': {
                'content': jsonEncode({
                  'level': 'low',
                  'syntax': 'valid',
                  'syntax_reason': '语法完整',
                  'explanation': '显示当前目录路径',
                  'reason': '查看当前路径',
                }),
              },
            },
          ],
        }),
      );
      await request.response.close();
    });
    final model = LlmProfile(
      name: 'mock',
      model: 'mock',
      endpoint: 'http://127.0.0.1:${server.port}',
      auth: 'none',
    );
    try {
      for (final allow in [false, true]) {
        await tester.tap(find.byTooltip('Agent 设置'));
        await tester.pumpAndSettle();
        final result = panel.agent.approvals
            .check(panel.workspace.selected!, 'terminal_run', 'pwd\r', (
              model,
              'mock',
            ))
            .then((_) => 'approved', onError: (Object e) => e.toString());
        for (var i = 0; i < 50 && panel.agent.approvals.pending == null; i++) {
          await tester.pump(const Duration(milliseconds: 50));
        }
        await tester.pumpAndSettle();
        expect(panel.agent.approvals.pending, isNotNull);
        expect(find.text('确认终端操作 · 低风险').hitTestable(), findsNothing);
        expect(find.text('添加 LLM 配置'), findsOneWidget);
        await tester.tap(find.byTooltip('关闭设置'));
        await tester.pumpAndSettle();
        expect(
          find.descendant(
            of: find.byKey(const Key('agent-context')),
            matching: find.text('确认终端操作 · 低风险'),
          ),
          findsOneWidget,
        );
        await tester.tap(find.text(allow ? '允许本次执行' : '拒绝'));
        await tester.pumpAndSettle();
        expect(await result, allow ? 'approved' : '你已拒绝本次操作，未执行。');
        expect(find.text('确认终端操作 · 低风险'), findsNothing);
        expect(find.text('手动同意 · 低风险'), allow ? findsOneWidget : findsNothing);
        expect(find.text('允许本次执行'), findsNothing);
      }
      panel.settings.autoAllow.add(CommandRisk.low);
      await panel.agent.approvals.check(
        panel.workspace.selected!,
        'terminal_run',
        'pwd\r',
        (model, 'mock'),
      );
      await tester.pumpAndSettle();
      expect(find.text('自动放行 · 低风险'), findsOneWidget);
      await tester.tap(find.text('自动放行 · 低风险'));
      await tester.pumpAndSettle();
      expect(find.textContaining('风险依据：查看当前路径'), findsOneWidget);
      await tester.tap(find.text('自动放行 · 低风险'));
      await tester.pumpAndSettle();
      expect(find.textContaining('风险依据：查看当前路径'), findsNothing);
      expect(find.text('手动同意 · 低风险'), findsOneWidget);
      expect(find.text('允许本次执行'), findsNothing);
    } finally {
      await server.close(force: true);
      await tester.pumpWidget(const SizedBox.shrink());
    }
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
          await call(1, 'terminal_run', {
            'command': "export TERMINAL_USE_SMOKE=shared_state",
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
  testWidgets(
    'multi-tab targeting survives selection changes and closes child jobs',
    (tester) async {
      final workspace = TerminalWorkspace();
      await tester.runAsync(() async {
        final dir = await Directory.systemTemp.createTemp(
          'terminal-close-test-',
        );
        final childFile = File('${dir.path}/child');
        final detachedFile = File('${dir.path}/detached');
        int? detachedPid;
        final first = workspace.add();
        final second = workspace.add();
        final api = AgentServer(
          read: first.session.snapshot,
          write: first.session.write,
          interrupt: first.session.interrupt,
          list: () => workspace.tabs.map((t) => t.snapshot()).toList(),
          readTerminal: (id) => workspace.require(id).snapshot(),
          writeTerminal: (id, text) =>
              workspace.require(id).session.write(text),
          interruptTerminal: (id) => workspace.require(id).session.interrupt(),
        );
        try {
          await api.start();
          final result = await Process.run('python3', [
            'tools/terminal_bridge.py',
            'input',
            "printf 'TARGET_%s_END\\n' ONE\r",
            '--terminal-id',
            first.id,
          ], environment: api.environment);
          expect(result.exitCode, 0, reason: '${result.stderr}');
          // Login-shell initialization can exceed 600 ms on a busy desktop.
          for (
            var i = 0;
            i < 50 &&
                !(first.session.snapshot()['text'] as String).contains(
                  'TARGET_ONE_END',
                );
            i++
          ) {
            await Future<void>.delayed(const Duration(milliseconds: 100));
          }
          expect(first.session.snapshot()['text'], contains('TARGET_ONE_END'));
          expect(
            second.session.snapshot()['text'],
            isNot(contains('TARGET_ONE_END')),
          );
          first.session.write(
            "nohup sleep 60 </dev/null > /dev/null 2>&1 & echo \$! > ${detachedFile.path}\r",
          );
          for (var i = 0; i < 30 && !await detachedFile.exists(); i++) {
            await Future<void>.delayed(const Duration(milliseconds: 100));
          }
          expect(await detachedFile.exists(), isTrue);
          detachedPid = int.parse((await detachedFile.readAsString()).trim());
          // Foreground jobs have their own process group under an interactive shell.
          first.session.write(
            "sh -c 'echo \$\$ > ${childFile.path}; exec sleep 60'\r",
          );
          for (var i = 0; i < 30 && !await childFile.exists(); i++) {
            await Future<void>.delayed(const Duration(milliseconds: 100));
          }
          expect(await childFile.exists(), isTrue);
          final childPid = int.parse((await childFile.readAsString()).trim());
          workspace.close(first.id);
          await Future<void>.delayed(const Duration(seconds: 1));
          final childStatus = await Process.run('/bin/ps', [
            '-p',
            '$childPid',
            '-o',
            'stat=',
          ]);
          expect(
            (childStatus.stdout as String).trim(),
            isEmpty,
            reason: 'Closing Tab must terminate foreground child',
          );
          expect(second.session.running, isTrue);
          final detachedStatus = await Process.run('/bin/ps', [
            '-p',
            '$detachedPid',
            '-o',
            'stat=',
          ]);
          expect(
            (detachedStatus.stdout as String).trim(),
            isNotEmpty,
            reason: 'Closing Tab must preserve a nohup job',
          );
          final closed = await Process.run('python3', [
            'tools/terminal_bridge.py',
            'input',
            'echo BAD\r',
            '--terminal-id',
            first.id,
          ], environment: api.environment);
          expect(closed.exitCode, isNot(0));
          expect(
            second.session.snapshot()['text'],
            isNot(contains('echo BAD')),
          );
        } finally {
          if (detachedPid != null) Process.killPid(detachedPid);
          await api.close();
          workspace.dispose();
          await dir.delete(recursive: true);
        }
      });
    },
  );
}

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:terminal_use_app/main.dart';
import 'package:terminal_use_app/src/internal_agent_view.dart';
import 'package:terminal_use_app/src/mac_controls.dart';
import 'package:terminal_use_app/src/terminal_session.dart';
import 'package:terminal_use_app/src/terminal_workspace.dart';

void main() {
  late Directory historyDirectory;
  setUp(() async {
    historyDirectory = await Directory.systemTemp.createTemp(
      'agent-panel-test-',
    );
  });

  testWidgets(
    'toolbar renames the active terminal and fits the minimum window',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(720, 640));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        TerminalUseApp(
          historyFile: File('${historyDirectory.path}/history.json'),
        ),
      );
      final view = tester.widget<InternalAgentView>(
        find.byType(InternalAgentView),
      );
      final tab = TerminalTab(
        'test-terminal',
        '很长的当前终端名称' * 10,
        TerminalSession(),
      );
      view.workspace.tabs.add(tab);
      view.workspace.select(tab.id);
      await tester.pump();
      final toolbar = find.byKey(const Key('workspace-toolbar'));
      expect(
        find.descendant(of: toolbar, matching: find.text('1 个终端')),
        findsOneWidget,
      );
      for (final tooltip in [
        '终端设置',
        '新建终端',
        '打开 SSH',
        'Agent 设置',
        '新建 Agent 会话',
      ]) {
        expect(
          find.descendant(of: toolbar, matching: find.byTooltip(tooltip)),
          findsOneWidget,
        );
      }
      await tester.tap(find.byKey(const Key('rename-active-terminal')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.byType(TextField),
        ),
        '开发终端',
      );
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      expect(tab.name, '开发终端');
      expect(
        find.descendant(of: toolbar, matching: find.text('开发终端')),
        findsOneWidget,
      );
      for (final key in ['toggle-tabs', 'toggle-agent']) {
        final button = find.byKey(Key(key));
        final position = tester.getTopLeft(button);
        await tester.tap(button);
        await tester.pump();
        expect(tester.getTopLeft(button), position);
      }
      expect(find.byTooltip('终端设置'), findsNothing);
      expect(find.byTooltip('新建终端'), findsNothing);
      expect(find.byTooltip('打开 SSH'), findsNothing);
      expect(find.byTooltip('Agent 设置'), findsNothing);
      expect(find.byTooltip('新建 Agent 会话'), findsNothing);
      expect(find.byKey(const Key('agent-conversation-title')), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1));
    },
  );

  testWidgets('collapse preserves the panel state, draft and width', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      TerminalUseApp(
        historyFile: File('${historyDirectory.path}/history.json'),
      ),
    );
    final panel = find.byType(InternalAgentView);
    final state = tester.state(panel);
    final view = tester.widget<InternalAgentView>(panel);
    view.task.text = '保留任务草稿';
    expect(find.text('Agent'), findsOneWidget);
    view.agent.log.add('任务 → terminal-1\n检查服务日志并排查启动失败');
    expect(view.agent.conversationTitle, '检查服务日志并排查启动失败');
    final width = tester.getSize(panel).width;
    final sidebar = find.byKey(const Key('terminal-sidebar'));
    final sidebarWidth = tester.getSize(sidebar).width;
    final toggle = find.byKey(const Key('toggle-tabs'));
    final togglePosition = tester.getTopLeft(toggle);
    final list = find.descendant(
      of: sidebar,
      matching: find.byType(Scrollable),
    );
    final listState = tester.state(list);
    await tester.tap(find.byKey(const Key('toggle-tabs')));
    await tester.pump();
    expect(sidebar, findsNothing);
    expect(tester.getTopLeft(toggle), togglePosition);
    expect(find.byTooltip('展开终端列表'), findsOneWidget);
    expect(tester.state(panel), same(state));

    for (var i = 0; i < 2; i++) {
      await tester.tap(find.byKey(const Key('toggle-agent')));
      await tester.pump();
      expect(panel, findsNothing);
      expect(
        tester.state(find.byType(InternalAgentView, skipOffstage: false)),
        same(state),
      );
      expect(view.task.text, '保留任务草稿');
      await tester.tap(find.byKey(const Key('toggle-agent')));
      await tester.pump();
      expect(tester.state(panel), same(state));
      expect(find.text('检查服务日志并排查启动失败'), findsOneWidget);
      expect(tester.getSize(panel).width, width);
      expect(tester.widget<InternalAgentView>(panel).task.text, '保留任务草稿');
    }
    await tester.tap(find.byKey(const Key('toggle-agent')));
    await tester.pump();
    await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
      'terminal_use/lifecycle',
      const StandardMethodCodec().encodeMethodCall(
        const MethodCall('focusAgent'),
      ),
      (_) {},
    );
    await tester.pump();
    await tester.pump();
    expect(panel, findsOneWidget);
    expect(view.inputFocus!.hasFocus, isTrue);
    await tester.tap(find.byKey(const Key('toggle-tabs')));
    await tester.pump();
    expect(tester.getSize(sidebar).width, sidebarWidth);
    expect(tester.getTopLeft(toggle), togglePosition);
    expect(tester.state(list), same(listState));
    expect(tester.state(panel), same(state));
    await tester.tap(find.byKey(const Key('toggle-tabs')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('toggle-tabs')));
    await tester.pump();
    expect(tester.state(list), same(listState));
    expect(tester.getSize(sidebar).width, sidebarWidth);
    expect(tester.getTopLeft(toggle), togglePosition);

    await tester.tap(find.byTooltip('新建 Agent 会话'));
    await tester.pump();
    expect(view.agent.conversationTitle, '检查服务日志并排查启动失败');
    expect(
      tester.widget<InternalAgentView>(panel).agent.conversationTitle,
      isNull,
    );
    expect(find.text('Agent'), findsOneWidget);

    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1));
  });
  testWidgets('history switches drafts and binds or unbinds the selected tab', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(720, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      TerminalUseApp(
        historyFile: File('${historyDirectory.path}/binding.json'),
      ),
    );
    var panel = tester.widget<InternalAgentView>(
      find.byType(InternalAgentView),
    );
    final firstAgent = panel.agent;
    firstAgent.log.add('任务 → first\n第一个会话');
    panel.task.text = '第一份草稿';
    final one = TerminalTab('first', '开发终端', TerminalSession());
    final two = TerminalTab('second', '其他终端', TerminalSession());
    final bindingButton = tester.widget<MacButton>(
      find.byKey(const Key('agent-tab-binding')),
    );
    expect(bindingButton.onPressed, isNull);
    final topToolbar = find.byKey(const Key('workspace-toolbar'));
    expect(
      find.descendant(
        of: topToolbar,
        matching: find.byKey(const Key('agent-tab-binding')),
      ),
      findsNothing,
    );
    expect(
      find.descendant(
        of: topToolbar,
        matching: find.byKey(const Key('agent-history')),
      ),
      findsOneWidget,
    );
    final middleToolbar = find.byKey(const Key('agent-session-toolbar'));
    expect(
      tester.getTopLeft(middleToolbar).dy,
      greaterThan(
        tester.getBottomLeft(find.byKey(const Key('agent-context'))).dy - 1,
      ),
    );
    expect(
      tester.getBottomLeft(middleToolbar).dy,
      lessThanOrEqualTo(
        tester.getTopLeft(find.byKey(const Key('agent-input-divider'))).dy,
      ),
    );
    panel.workspace.tabs.addAll([one, two]);
    panel.workspace.select(one.id);
    await tester.pump();
    await tester.tap(find.byKey(const Key('agent-tab-binding')));
    await tester.pumpAndSettle();
    expect(one.agentConversationId, isNotNull);
    await tester.tap(find.byKey(const Key('agent-history')));
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.textContaining('已绑定：开发终端'),
      ),
      findsOneWidget,
    );
    await tester.tap(find.text('关闭'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('新建 Agent 会话'));
    await tester.pump();
    panel = tester.widget<InternalAgentView>(find.byType(InternalAgentView));
    expect(panel.agent, isNot(same(firstAgent)));
    expect(panel.task.text, isEmpty);
    panel.task.text = '第二份草稿';
    panel.workspace.select(two.id);
    panel.workspace.select(one.id);
    await tester.pump();
    panel = tester.widget<InternalAgentView>(find.byType(InternalAgentView));
    expect(panel.agent, same(firstAgent));
    expect(panel.task.text, '第一份草稿');
    await tester.tap(find.byKey(const Key('agent-tab-unbinding')));
    await tester.pumpAndSettle();
    expect(one.agentConversationId, isNull);
    await tester.tap(find.byKey(const Key('agent-history')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('新会话'));
    await tester.pumpAndSettle();
    panel = tester.widget<InternalAgentView>(find.byType(InternalAgentView));
    expect(panel.task.text, '第二份草稿');
    panel.workspace.select(two.id);
    panel.workspace.select(one.id);
    await tester.pump();
    expect(
      tester.widget<InternalAgentView>(find.byType(InternalAgentView)).agent,
      same(panel.agent),
    );
    expect(tester.takeException(), isNull);
    await tester.tap(find.byKey(const Key('agent-tab-binding')));
    await tester.pump();
    expect(one.agentConversationId, isNotNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    expect(one.agentConversationId, isNull);
  });
}

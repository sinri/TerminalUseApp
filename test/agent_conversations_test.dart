import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:terminal_use_app/src/agent_conversations.dart';
import 'package:terminal_use_app/src/internal_agent.dart';
import 'package:terminal_use_app/src/settings.dart';
import 'package:terminal_use_app/src/terminal_approval.dart';
import 'package:terminal_use_app/src/terminal_session.dart';
import 'package:terminal_use_app/src/terminal_workspace.dart';

void main() {
  late Directory directory;
  late TerminalWorkspace workspace;
  late AgentConversations store;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('agent-history-test-');
    workspace = TerminalWorkspace();
    store = AgentConversations(
      workspace,
      AppSettings(),
      file: File('${directory.path}/history.json'),
    );
    await store.load();
  });
  tearDown(() async {
    await store.flush();
    store.dispose();
    workspace.dispose();
    await directory.delete(recursive: true);
  });

  test(
    'round trip preserves contexts, tool reviews, replies, draft and active session',
    () async {
      final original = store.active;
      original.agent.restoreConversation({
        'history': [
          {'role': 'user', 'content': 'earlier task'},
          {'role': 'assistant', 'content': 'earlier answer'},
        ],
        'log': [
          {'type': 'text', 'text': '任务 → old-terminal\n检查服务'},
        ],
      });
      original.agent.log.addAll([
        AgentText()
          ..text = 'streamed answer'
          ..complete = true,
        ToolActivity('terminal_run', 'old-terminal')
          ..arguments = {'command': 'pwd'}
          ..result = '/home/user'
          ..approval = ApprovedOperation(
            TerminalReview(
              'old-terminal',
              'terminal_run',
              'pwd\r',
              'low',
              'reason',
              'explanation',
              'valid',
              false,
            ),
            automatic: false,
          ),
      ]);
      store.updateDraft('first draft');
      store.rename(original.id, '服务排查');
      store.create();
      final second = store.active;
      store.updateDraft('second draft');
      await store.flush();
      final restored = AgentConversations(
        workspace,
        AppSettings(),
        file: store.file,
      );
      await restored.load();
      addTearDown(restored.dispose);
      expect(restored.active.id, second.id);
      expect(restored.active.draft, 'second draft');
      final first = restored.find(original.id)!;
      expect(first.title, '服务排查');
      expect(first.draft, 'first draft');
      expect(
        first.agent.exportConversation()['history'],
        original.agent.exportConversation()['history'],
      );
      expect(
        first.agent.log.whereType<AgentText>().single.text,
        'streamed answer',
      );
      final tool = first.agent.log.whereType<ToolActivity>().single;
      expect(tool.result, '/home/user');
      expect(tool.approval!.review.text, 'pwd\r');
      expect(tool.approval!.automatic, false);
      expect(first.agent.running, false);
      expect(first.agent.approvals.pending, isNull);
      if (!Platform.isWindows) {
        expect((await store.file.stat()).mode & 0x1ff, 0x180);
      }
    },
  );

  test(
    'tab binding follows selection; unbinding and deletion preserve other sessions',
    () {
      final one = TerminalTab('one', 'one', TerminalSession());
      final two = TerminalTab('two', 'two', TerminalSession());
      workspace.tabs.addAll([one, two]);
      workspace.select(one.id);
      final first = store.active;
      store.bind(one, first.id);
      store.create();
      final second = store.active;
      store.bind(two, second.id);
      workspace.select(two.id);
      expect(store.active, second);
      workspace.select(one.id);
      expect(store.active, first);
      store.bind(one, null);
      store.select(second.id);
      workspace.select(two.id);
      workspace.select(one.id);
      expect(store.active, second);
      store.bind(one, first.id);
      expect(store.active, first);
      expect(store.delete(first.id), true);
      expect(one.agentConversationId, isNull);
      expect(store.active, second);
      expect(store.delete(second.id), true);
      expect(store.conversations, hasLength(1));
      expect(two.agentConversationId, isNull);
    },
  );

  test(
    'binding releases both previous relationships before creating a one-to-one pair',
    () {
      final one = TerminalTab('one', 'one', TerminalSession());
      final two = TerminalTab('two', 'two', TerminalSession());
      final unbound = TerminalTab('three', 'three', TerminalSession());
      workspace.tabs.addAll([one, two, unbound]);
      workspace.select(one.id);
      final first = store.active;
      store.bind(one, first.id);
      store.create();
      final second = store.active;
      store.bind(two, second.id);
      var notifications = 0;
      store.addListener(() {
        notifications++;
        final ids = workspace.tabs
            .map((t) => t.agentConversationId)
            .whereType<String>()
            .toList();
        expect(ids.toSet(), hasLength(ids.length));
      });
      store.bind(two, first.id);
      expect(notifications, greaterThan(0));
      expect(one.agentConversationId, isNull);
      expect(two.agentConversationId, first.id);
      expect(store.boundTab(second.id), isNull);
      expect(store.boundTab(first.id), same(two));
      workspace.select(two.id);
      expect(store.active, first);
      workspace.select(unbound.id);
      expect(store.active, first);
      store.unbindConversation(first.id);
      expect(two.agentConversationId, isNull);
      store.select(second.id);
      workspace.select(two.id);
      expect(store.active, second);
    },
  );

  test('closing tabs and application shutdown clear all relationships', () {
    final one = TerminalTab('one', 'one', TerminalSession());
    final two = TerminalTab('two', 'two', TerminalSession());
    workspace.tabs.addAll([one, two]);
    workspace.select(one.id);
    final first = store.active;
    store.bind(one, first.id);
    workspace.close(one.id);
    expect(one.agentConversationId, isNull);
    expect(store.boundTab(first.id), isNull);
    expect(store.find(first.id), same(first));
    store.bind(two, first.id);
    store.clearBindings();
    expect(two.agentConversationId, isNull);
    expect(store.find(first.id), same(first));
    final otherWorkspace = TerminalWorkspace();
    final otherTab = TerminalTab('other', 'other', TerminalSession())
      ..agentConversationId = first.id;
    otherWorkspace.tabs.add(otherTab);
    otherWorkspace.dispose();
    expect(otherTab.agentConversationId, isNull);
  });

  test('corrupt history is retained and never overwritten', () async {
    await store.file.writeAsString('{broken');
    final broken = AgentConversations(
      workspace,
      AppSettings(),
      file: store.file,
    );
    await broken.load();
    expect(broken.storageError, contains('原文件已保留'));
    broken.create();
    await broken.flush();
    expect(await store.file.readAsString(), '{broken');
    broken.dispose();
  });

  test(
    'failed writes show an error and a later flush retries without losing sessions',
    () async {
      store.updateDraft('must survive retry');
      await Directory(store.file.path).create();
      await store.flush();
      expect(store.storageError, contains('保存失败'));
      await Directory(store.file.path).delete();
      await store.flush();
      expect(store.storageError, isNull);
      expect(await store.file.readAsString(), contains('must survive retry'));
    },
  );

  test(
    'an unfinished tool restores as interrupted without pending approval',
    () {
      final agent = InternalAgent(workspace);
      agent.restoreConversation({
        'history': [],
        'log': [
          {
            'type': 'tool',
            'name': 'terminal_run',
            'target': 'one',
            'arguments': {'command': 'pwd'},
            'result': null,
            'failed': false,
          },
          {'type': 'reply', 'text': 'partial', 'complete': false},
        ],
      });
      expect(agent.log.whereType<ToolActivity>().single.failed, true);
      expect(
        agent.log.whereType<ToolActivity>().single.result,
        contains('不会自动重新执行'),
      );
      expect(agent.log.whereType<AgentText>().single.complete, false);
      expect(agent.approvals.pending, isNull);
      agent.dispose();
    },
  );

  test(
    'switching during a request keeps output and context in the original conversation',
    () async {
      final tab = TerminalTab('one', 'one', TerminalSession());
      workspace.tabs.add(tab);
      workspace.select(tab.id);
      final first = store.active;
      final received = Completer<void>();
      final release = Completer<void>();
      final requests = <Map<String, dynamic>>[];
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) async {
        requests.add(
          jsonDecode(await utf8.decoder.bind(request).join())
              as Map<String, dynamic>,
        );
        if (!received.isCompleted) {
          received.complete();
          await release.future;
        }
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode({
            'choices': [
              {
                'message': {
                  'role': 'assistant',
                  'content': 'answer ${requests.length}',
                },
                'finish_reason': 'stop',
              },
            ],
          }),
        );
        await request.response.close();
      });
      addTearDown(() => server.close(force: true));
      final profile = LlmProfile(
        name: 'test',
        endpoint: 'http://127.0.0.1:${server.port}/v1',
        model: 'test',
      );
      final run = first.agent.run(
        profile,
        'first question',
        tab.id,
        SkillCatalog(''),
      );
      await received.future;
      expect(first.agent.running, true);
      store.create();
      final second = store.active;
      expect(store.delete(first.id), false);
      release.complete();
      await run;
      expect(store.active, second);
      expect(second.agent.log, isEmpty);
      expect(
        first.agent.exportConversation()['history'].toString(),
        contains('answer 1'),
      );
      store.select(first.id);
      await first.agent.run(profile, 'follow-up', tab.id, SkillCatalog(''));
      expect(requests.last['messages'].toString(), contains('first question'));
      expect(requests.last['messages'].toString(), contains('answer 1'));
      expect(second.agent.log, isEmpty);
    },
  );
}

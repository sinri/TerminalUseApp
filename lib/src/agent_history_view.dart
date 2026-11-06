import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'agent_conversations.dart';
import 'mac_controls.dart';
import 'terminal_workspace.dart';

class AgentHistoryDialog extends StatefulWidget {
  const AgentHistoryDialog({super.key, required this.conversations, this.tab});
  final AgentConversations conversations;
  final TerminalTab? tab;
  @override
  State<AgentHistoryDialog> createState() => _AgentHistoryDialogState();
}

class _AgentHistoryDialogState extends State<AgentHistoryDialog> {
  String query = '';

  Future<void> _rename(AgentConversation conversation) async {
    final controller = TextEditingController(text: conversation.title);
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('重命名会话'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: '会话名称'),
          onSubmitted: (value) => Navigator.pop(context, value),
        ),
        actions: [
          MacButton(label: '取消', onPressed: () => Navigator.pop(context)),
          MacButton(
            label: '保存',
            primary: true,
            onPressed: () => Navigator.pop(context, controller.text),
          ),
        ],
      ),
    );
    if (name != null) widget.conversations.rename(conversation.id, name);
    await Future<void>.delayed(const Duration(milliseconds: 300));
    controller.dispose();
  }

  Future<void> _delete(AgentConversation conversation) async {
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除会话？'),
        content: Text('将删除“${conversation.title}”的历史记录和草稿，并解除对应的 Tab 绑定。'),
        actions: [
          MacButton(
            label: '取消',
            onPressed: () => Navigator.pop(context, false),
          ),
          MacButton(label: '删除', onPressed: () => Navigator.pop(context, true)),
        ],
      ),
    );
    if (accepted == true) widget.conversations.delete(conversation.id);
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.conversations,
    builder: (context, _) {
      final store = widget.conversations;
      final tab = widget.tab;
      final entries =
          store.conversations
              .where((c) => c.title.toLowerCase().contains(query.toLowerCase()))
              .toList()
            ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      return AlertDialog(
        title: Text(tab == null ? 'Agent 会话历史' : '绑定会话 · ${tab.name}'),
        content: SizedBox(
          width: 520,
          height: 420,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (store.storageError != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(
                    store.storageError!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              if (tab != null) ...[
                const Text('选择后，切换到此 Tab 会自动显示对应的 Agent 会话。'),
                const SizedBox(height: 12),
              ],
              TextField(
                decoration: const InputDecoration(
                  labelText: '搜索会话',
                  prefixIcon: Icon(CupertinoIcons.search),
                ),
                onChanged: (value) => setState(() => query = value),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: entries.isEmpty
                    ? const Center(child: Text('没有匹配的会话'))
                    : ListView.builder(
                        itemCount: entries.length,
                        itemBuilder: (context, index) {
                          final conversation = entries[index];
                          final selected = tab == null
                              ? store.active.id == conversation.id
                              : tab.agentConversationId == conversation.id;
                          final busy =
                              conversation.agent.running ||
                              conversation.agent.approvals.pending != null;
                          final boundTab = store.boundTab(conversation.id);
                          final time = conversation.updatedAt
                              .toLocal()
                              .toString()
                              .substring(0, 16);
                          return ListTile(
                            key: ValueKey(conversation.id),
                            selected: selected,
                            leading: Icon(
                              selected
                                  ? CupertinoIcons.check_mark_circled_solid
                                  : CupertinoIcons.chat_bubble,
                            ),
                            title: Text(
                              conversation.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Text(
                              '$time${busy ? ' · 运行中 / 等待确认' : ''}\n${boundTab == null ? '未绑定 Tab' : '已绑定：${boundTab.name}（${boundTab.id}）'}',
                            ),
                            onTap: () {
                              if (tab == null) {
                                store.select(conversation.id);
                              } else if (store.workspace.tabs.contains(tab)) {
                                store.bind(tab, conversation.id);
                              }
                              Navigator.pop(context);
                            },
                            trailing: tab != null
                                ? null
                                : PopupMenuButton<String>(
                                    tooltip: '管理会话',
                                    onSelected: (value) {
                                      if (value == 'rename') {
                                        _rename(conversation);
                                      }
                                      if (value == 'delete') {
                                        _delete(conversation);
                                      }
                                    },
                                    itemBuilder: (context) => [
                                      const PopupMenuItem(
                                        value: 'rename',
                                        child: Text('重命名…'),
                                      ),
                                      PopupMenuItem(
                                        value: 'delete',
                                        enabled: !busy,
                                        child: const Text('删除会话…'),
                                      ),
                                    ],
                                  ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
        actions: [
          if (tab != null)
            MacButton(
              label: '解除绑定',
              onPressed: tab.agentConversationId == null
                  ? null
                  : () {
                      if (store.workspace.tabs.contains(tab)) {
                        store.bind(tab, null);
                      }
                      Navigator.pop(context);
                    },
            ),
          if (tab == null)
            MacButton(
              label: '新建会话',
              onPressed: () {
                store.create();
                Navigator.pop(context);
              },
            ),
          MacButton(label: '关闭', onPressed: () => Navigator.pop(context)),
        ],
      );
    },
  );
}

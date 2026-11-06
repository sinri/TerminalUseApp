import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'internal_agent.dart';
import 'settings.dart';
import 'terminal_workspace.dart';

class AgentConversation {
  AgentConversation(
    this.id,
    this.agent, {
    DateTime? createdAt,
    DateTime? updatedAt,
  }) : createdAt = createdAt ?? DateTime.now(),
       updatedAt = updatedAt ?? DateTime.now();
  final String id;
  final InternalAgent agent;
  final DateTime createdAt;
  DateTime updatedAt;
  String draft = '';
  String? name;
  String get title => name ?? agent.conversationTitle ?? '新会话';
}

/// Each conversation owns its agent so changing the visible conversation cannot
/// redirect an in-flight model response, tool call, or approval.
class AgentConversations extends ChangeNotifier {
  AgentConversations(this.workspace, this.settings, {File? file})
    : file =
          file ??
          File('${AppSettings.defaultFile.parent.path}/agent-history.json') {
    _create();
    _selectedTab = workspace.selectedId;
    workspace.addListener(_workspaceChanged);
  }
  final TerminalWorkspace workspace;
  final AppSettings settings;
  final File file;
  final conversations = <AgentConversation>[];
  late AgentConversation active;
  String? storageError;
  String? _selectedTab;
  bool _disposed = false;
  bool _changed = false;
  bool _readOnly = false;
  bool _loaded = false;
  int _sequence = 0;
  Timer? _saveTimer;
  Future<void> _writes = Future<void>.value();

  AgentConversation _create({String? id}) {
    final conversation = AgentConversation(
      id ?? 'chat-${DateTime.now().microsecondsSinceEpoch}-${_sequence++}',
      InternalAgent(workspace, settings: settings),
    );
    conversations.add(conversation);
    active = conversation;
    _listen(conversation);
    return conversation;
  }

  void _listen(AgentConversation conversation) {
    void changed() {
      if (_disposed) return;
      conversation.updatedAt = DateTime.now();
      _scheduleSave();
      notifyListeners();
    }

    conversation.agent.addListener(changed);
    conversation.agent.approvals.addListener(changed);
  }

  AgentConversation? find(String? id) =>
      conversations.where((c) => c.id == id).firstOrNull;

  void create() {
    _create();
    _scheduleSave();
    notifyListeners();
  }

  void select(String id) {
    final conversation = find(id);
    if (conversation == null || identical(active, conversation)) return;
    active = conversation;
    _scheduleSave();
    notifyListeners();
  }

  void updateDraft(String text) {
    if (active.draft == text) return;
    active.draft = text;
    _scheduleSave();
  }

  void rename(String id, String name) {
    final conversation = find(id);
    if (conversation == null) return;
    conversation.name = name.trim().isEmpty ? null : name.trim();
    _scheduleSave();
    notifyListeners();
  }

  void bind(TerminalTab tab, String? conversationId) {
    if (!workspace.tabs.contains(tab)) throw StateError('终端已关闭');
    if (conversationId != null && find(conversationId) == null) {
      throw StateError('会话不存在');
    }
    // Release both ends before publishing the new relationship.
    tab.agentConversationId = null;
    if (conversationId != null) {
      for (final other in workspace.tabs) {
        if (other.agentConversationId == conversationId) {
          other.agentConversationId = null;
        }
      }
    }
    tab.agentConversationId = conversationId;
    if (tab.id == workspace.selectedId && conversationId != null) {
      select(conversationId);
    }
    notifyListeners();
  }

  TerminalTab? boundTab(String conversationId) => workspace.tabs
      .where((tab) => tab.agentConversationId == conversationId)
      .firstOrNull;

  void unbindConversation(String conversationId) {
    for (final tab in workspace.tabs) {
      if (tab.agentConversationId == conversationId) {
        tab.agentConversationId = null;
      }
    }
    notifyListeners();
  }

  void clearBindings() {
    for (final tab in workspace.tabs) {
      tab.agentConversationId = null;
    }
    notifyListeners();
  }

  void _workspaceChanged() {
    final tab = workspace.selected;
    if (_selectedTab == tab?.id) return;
    _selectedTab = tab?.id;
    final id = tab?.agentConversationId;
    if (id != null) select(id);
  }

  bool delete(String id) {
    final conversation = find(id);
    if (conversation == null ||
        conversation.agent.running ||
        conversation.agent.approvals.pending != null) {
      return false;
    }
    for (final tab in workspace.tabs) {
      if (tab.agentConversationId == id) tab.agentConversationId = null;
    }
    conversations.remove(conversation);
    conversation.agent.dispose();
    if (conversations.isEmpty) {
      _create();
    } else if (identical(active, conversation)) {
      active = conversations.last;
    }
    _scheduleSave();
    notifyListeners();
    return true;
  }

  Future<void> load() async {
    final restored = <AgentConversation>[];
    try {
      if (!await file.exists()) return;
      final data =
          jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      if (data['version'] != 1) throw const FormatException('不支持的会话历史版本');
      for (final raw in data['conversations'] as List) {
        final entry = Map<String, dynamic>.from(raw as Map);
        final agent = InternalAgent(workspace, settings: settings);
        try {
          agent.restoreConversation(
            Map<String, dynamic>.from(entry['agent'] as Map),
          );
          final conversation =
              AgentConversation(
                  entry['id'] as String,
                  agent,
                  createdAt: DateTime.parse(entry['createdAt'] as String),
                  updatedAt: DateTime.parse(entry['updatedAt'] as String),
                )
                ..draft = entry['draft'] as String? ?? ''
                ..name = entry['name'] as String?;
          if (restored.any((c) => c.id == conversation.id)) {
            throw const FormatException('会话 ID 重复');
          }
          restored.add(conversation);
        } catch (_) {
          agent.dispose();
          rethrow;
        }
      }
      if (_disposed) {
        for (final c in restored) {
          c.agent.dispose();
        }
        return;
      }
      // Preserve any conversation the user started while disk I/O was pending.
      if (!_changed) {
        for (final c in conversations) {
          c.agent.dispose();
        }
        conversations.clear();
      }
      conversations.insertAll(0, restored);
      for (final c in restored) {
        _listen(c);
      }
      if (!_changed) {
        if (conversations.isEmpty) {
          _create();
        }
        active = find(data['activeId'] as String?) ?? conversations.last;
      }
      notifyListeners();
    } catch (e) {
      for (final c in restored) {
        c.agent.dispose();
      }
      // A failed read must never silently overwrite existing history.
      _readOnly = true;
      storageError = '会话历史读取失败，原文件已保留：$e';
      if (!_disposed) notifyListeners();
    } finally {
      _loaded = true;
      if (_changed) _scheduleSave();
    }
  }

  void _scheduleSave() {
    _changed = true;
    if (_disposed || _readOnly || !_loaded) return;
    _saveTimer ??= Timer(const Duration(milliseconds: 750), () {
      _saveTimer = null;
      unawaited(flush());
    });
  }

  Future<void> flush() {
    _saveTimer?.cancel();
    _saveTimer = null;
    if (_readOnly || !_changed || !_loaded) return _writes;
    final content = jsonEncode({
      'version': 1,
      'activeId': active.id,
      'conversations': conversations
          .map(
            (c) => {
              'id': c.id,
              'name': c.name,
              'createdAt': c.createdAt.toIso8601String(),
              'updatedAt': c.updatedAt.toIso8601String(),
              'draft': c.draft,
              'agent': c.agent.exportConversation(),
            },
          )
          .toList(),
    });
    _changed = false;
    final write = _writes.then((_) async {
      await file.parent.create(recursive: true);
      if (!Platform.isWindows) {
        final result = await Process.run('chmod', ['700', file.parent.path]);
        if (result.exitCode != 0) throw const FileSystemException('无法保护历史目录');
      }
      final temporary = File('${file.path}.tmp');
      await temporary.writeAsString(content, flush: true);
      if (!Platform.isWindows) {
        final result = await Process.run('chmod', ['600', temporary.path]);
        if (result.exitCode != 0) throw const FileSystemException('无法保护历史文件');
      }
      await temporary.rename(file.path);
    });
    _writes = write.then(
      (_) {
        if (storageError != null) {
          storageError = null;
          if (!_disposed) notifyListeners();
        }
      },
      onError: (Object error) {
        _changed = true;
        storageError = '会话历史保存失败：$error';
        if (!_disposed) notifyListeners();
      },
    );
    return _writes;
  }

  void stopAll() {
    for (final c in conversations) {
      c.agent.approvals.cancelAll();
      c.agent.stop();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _saveTimer?.cancel();
    workspace.removeListener(_workspaceChanged);
    for (final tab in workspace.tabs) {
      tab.agentConversationId = null;
    }
    for (final c in conversations) {
      c.agent.dispose();
    }
    super.dispose();
  }
}

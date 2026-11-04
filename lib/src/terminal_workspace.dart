import 'package:flutter/foundation.dart';
import 'terminal_session.dart';

class TerminalTab {
  TerminalTab(this.id, this.name, this.session);
  final String id;
  String name;
  final TerminalSession session;
  Map<String, dynamic> snapshot() => {
    'id': id,
    'name': name,
    ...session.snapshot(),
  };
}

class TerminalWorkspace extends ChangeNotifier {
  final tabs = <TerminalTab>[];
  int _nextId = 0;
  String? selectedId;
  TerminalTab? get selected =>
      tabs.where((t) => t.id == selectedId).firstOrNull;
  TerminalTab add({
    String? name,
    String? executable,
    List<String> arguments = const [],
  }) {
    final session = TerminalSession();
    try {
      session.start(executable: executable, arguments: arguments);
    } catch (_) {
      session.dispose();
      rethrow;
    }
    final tab = TerminalTab(
      'terminal-${++_nextId}',
      name ?? 'Terminal $_nextId',
      session,
    );
    tabs.add(tab);
    selectedId = tab.id;
    session.addListener(notifyListeners);
    notifyListeners();
    return tab;
  }

  TerminalTab require(String id) => tabs.firstWhere(
    (t) => t.id == id,
    orElse: () => throw StateError('终端不存在或已关闭：$id'),
  );
  void select(String id) {
    require(id);
    selectedId = id;
    notifyListeners();
  }

  void rename(String id, String name) {
    if (name.trim().isEmpty) return;
    require(id).name = name.trim();
    notifyListeners();
  }

  void close(String id) {
    final tab = require(id);
    tabs.remove(tab);
    tab.session.removeListener(notifyListeners);
    tab.session.dispose();
    if (selectedId == id) selectedId = tabs.lastOrNull?.id;
    notifyListeners();
  }

  @override
  void dispose() {
    for (final tab in tabs) {
      tab.session.removeListener(notifyListeners);
      tab.session.dispose();
    }
    tabs.clear();
    super.dispose();
  }
}

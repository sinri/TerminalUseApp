import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:xterm/xterm.dart';
import 'src/agent_server.dart';
import 'src/card_text.dart';
import 'src/terminal_session.dart';
import 'src/terminal_workspace.dart';
import 'src/settings.dart';
import 'src/settings_view.dart';
import 'src/internal_agent.dart';
import 'src/internal_agent_view.dart';

// Keep the platform's text metrics and use the bundled mono icons only for
// missing glyphs, including the private-use characters in shell prompts.
final terminalTextStyle = const TerminalStyle(fontSize: 13, fontFamily: 'Menlo')
    .copyWith(
      fontFamilyFallback: [
        'TerminalSymbols',
        ...const TerminalStyle().fontFamilyFallback,
      ],
    );

void main() {
  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks([
      'Nerd Fonts Symbols',
    ], await rootBundle.loadString('assets/fonts/NERD-FONTS-LICENSE.txt'));
  });
  runApp(const TerminalUseApp());
}

class TerminalUseApp extends StatelessWidget {
  const TerminalUseApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    title: 'Terminal Use',
    theme: ThemeData(
      brightness: Brightness.dark,
      fontFamilyFallback: cardFontFallback,
      colorSchemeSeed: const Color(0xff87e0bf),
      scaffoldBackgroundColor: const Color(0xff101418),
      useMaterial3: true,
    ),
    home: const Workspace(),
  );
}

class Workspace extends StatefulWidget {
  const Workspace({super.key});
  @override
  State<Workspace> createState() => _WorkspaceState();
}

class _WorkspaceState extends State<Workspace> {
  static const lifecycle = MethodChannel('terminal_use/lifecycle');
  final workspace = TerminalWorkspace();
  final settings = AppSettings();
  late final InternalAgent internal = InternalAgent(
    workspace,
    settings: settings,
  );
  String? legacyId;
  final taskDraft = TextEditingController();
  ModelChoice? selectedModel;
  final terminalControllers = <TerminalSession, TerminalController>{};
  TerminalSession get shell => workspace.require(legacyId!).session;
  AgentServer? server;
  String? error;
  bool ready = false;
  @override
  void initState() {
    super.initState();
    lifecycle.setMethodCallHandler((call) async {
      if (call.method == 'shutdown') await _shutdown();
    });
    workspace.addListener(_refresh);
    _start();
  }

  Future<void> _start() async {
    try {
      legacyId = workspace.add().id;
      try {
        await settings.load();
      } catch (e) {
        error = '配置读取失败，原文件已保留：$e';
      }
      if (!mounted) return;
      final api = AgentServer(
        read: () => shell.snapshot(),
        write: (text) => _externalInput(legacyId!, text),
        interrupt: () => _externalInput(legacyId!, '\x03'),
        list: () => workspace.tabs
            .map(
              (t) => {'id': t.id, 'name': t.name, 'running': t.session.running},
            )
            .toList(),
        readTerminal: (id) => workspace.require(id).snapshot(),
        writeTerminal: _externalInput,
        interruptTerminal: (id) => _externalInput(id, '\x03'),
      );
      server = api;
      await api.start();
      if (!mounted) {
        await api.close();
        return;
      }
      setState(() => ready = true);
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    }
  }

  Future<void> _externalInput(String id, String text) async {
    final tab = workspace.require(id);
    final first = settings.models.firstOrNull;
    final model = settings.models.contains(selectedModel?.$1)
        ? selectedModel
        : first == null
        ? null
        : (first, first.model);
    await internal.approvals.check(
      tab,
      'MCP input',
      text,
      model,
      external: true,
    );
    workspace.require(id).session.write(text);
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  Future<void>? shutdown;
  Future<void> _shutdown() => shutdown ??= _closeResources();
  Future<void> _closeResources() async {
    internal.approvals.cancelAll();
    internal.stop();
    await server?.close();
    await Future.wait([for (final tab in workspace.tabs) tab.session.close()]);
  }

  @override
  void dispose() {
    lifecycle.setMethodCallHandler(null);
    _shutdown();
    internal.dispose();
    workspace.removeListener(_refresh);
    workspace.dispose();
    for (final controller in terminalControllers.values) {
      controller.dispose();
    }
    taskDraft.dispose();
    super.dispose();
  }

  Widget _terminal(TerminalSession session) => Padding(
    padding: const EdgeInsets.all(12),
    child: TerminalView(
      session.terminal,
      key: ValueKey(session),
      controller: terminalControllers.putIfAbsent(
        session,
        TerminalController.new,
      ),
      onSecondaryTapDown: (details, offset) =>
          _terminalMenu(session, details.globalPosition),
      autofocus: true,
      textStyle: terminalTextStyle,
      backgroundOpacity: 0,
      hardwareKeyboardOnly: true,
    ),
  );
  Widget _divider(String id, ValueChanged<double> drag) => MouseRegion(
    cursor: SystemMouseCursors.resizeColumn,
    child: GestureDetector(
      key: Key(id),
      behavior: HitTestBehavior.opaque,
      onHorizontalDragUpdate: (e) => drag(e.delta.dx),
      child: const SizedBox(
        width: 16,
        height: double.infinity,
        child: Center(child: Icon(Icons.drag_indicator, size: 16)),
      ),
    ),
  );
  double tabWidth = 120;
  double agentFraction = .31;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Column(
        children: [
          if (error != null)
            Text(error!, style: const TextStyle(color: Colors.orange)),
          Expanded(
            child: LayoutBuilder(
              builder: (context, bounds) {
                final width = (bounds.maxWidth * agentFraction).clamp(
                  248.0,
                  bounds.maxWidth - 320,
                );
                final maxSidebar =
                    bounds.maxWidth -
                    width -
                    200; // Space for the terminal and both handles.
                final sidebar = tabWidth.clamp(120.0, maxSidebar);
                return Row(
                  children: [
                    SizedBox(
                      width: sidebar,
                      child: Column(
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Tooltip(
                                  message: '新建终端',
                                  child: TextButton(
                                    onPressed: _newTerminal,
                                    child: const Text('New'),
                                  ),
                                ),
                              ),
                              PopupMenuButton<Object>(
                                tooltip: '打开 SSH',
                                icon: const Icon(Icons.arrow_drop_down),
                                itemBuilder: (_) => [
                                  for (final p in settings.ssh)
                                    PopupMenuItem(
                                      value: p,
                                      child: Text(p.name),
                                    ),
                                  const PopupMenuItem(
                                    value: 'settings',
                                    child: Text('管理 SSH 入口'),
                                  ),
                                ],
                                onSelected: (v) {
                                  if (v is SshProfile) {
                                    _newTerminal(v);
                                  } else {
                                    _openSettings(ssh: true);
                                  }
                                },
                              ),
                            ],
                          ),
                          Expanded(
                            child: ListView(
                              children: [
                                for (final tab in workspace.tabs)
                                  Material(
                                    color: tab == workspace.selected
                                        ? Theme.of(
                                            context,
                                          ).colorScheme.secondaryContainer
                                        : Colors.transparent,
                                    child: Row(
                                      children: [
                                        Expanded(
                                          child: InkWell(
                                            onTap: () =>
                                                workspace.select(tab.id),
                                            onDoubleTap: () => _rename(tab),
                                            onLongPress: () => _rename(tab),
                                            child: Padding(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 8,
                                                    vertical: 12,
                                                  ),
                                              child: Text(
                                                tab.name,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                          ),
                                        ),
                                        IconButton(
                                          tooltip: '关闭 ${tab.name}',
                                          visualDensity: VisualDensity.compact,
                                          icon: const Icon(
                                            Icons.close,
                                            size: 16,
                                          ),
                                          onPressed: () {
                                            workspace.close(tab.id);
                                            terminalControllers
                                                .remove(tab.session)
                                                ?.dispose();
                                          },
                                        ),
                                      ],
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          TextButton.icon(
                            onPressed: () => _openSettings(ssh: true),
                            icon: const Icon(Icons.settings, size: 16),
                            label: const Text('SSH 设置'),
                          ),
                        ],
                      ),
                    ),
                    _divider(
                      'tabs-divider',
                      (dx) => setState(
                        () =>
                            tabWidth = (sidebar + dx).clamp(120.0, maxSidebar),
                      ),
                    ),
                    Expanded(
                      child: Container(
                        margin: const EdgeInsets.symmetric(vertical: 8),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Colors.white24),
                        ),
                        child: workspace.selected == null
                            ? Center(
                                child: TextButton(
                                  onPressed: _newTerminal,
                                  child: const Text('新建终端'),
                                ),
                              )
                            : _terminal(workspace.selected!.session),
                      ),
                    ),
                    _divider(
                      'panel-divider',
                      (dx) => setState(
                        () => agentFraction =
                            ((width - dx).clamp(
                              248.0,
                              bounds.maxWidth - sidebar - 200,
                            )) /
                            bounds.maxWidth,
                      ),
                    ),
                    SizedBox(
                      width: width,
                      child: InternalAgentView(
                        agent: internal,
                        task: taskDraft,
                        selected: selectedModel,
                        select: (m) => setState(() => selectedModel = m),
                        configure: () => _openSettings(),
                        settings: settings,
                        workspace: workspace,
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    ),
  );

  Future<void> _openSettings({bool ssh = false}) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SettingsView(
          settings: settings,
          ssh: ssh,
          connection: ready ? server!.environment : const {},
        ),
      ),
    );
    if (mounted) setState(() {});
  }

  void _newTerminal([SshProfile? ssh]) {
    try {
      workspace.add(
        name: ssh?.name,
        executable: ssh == null ? null : 'ssh',
        arguments: ssh?.arguments ?? const [],
      );
    } catch (e) {
      setState(() => error = '$e');
    }
  }

  Future<void> _rename(TerminalTab tab) async {
    final controller = TextEditingController(text: tab.name);
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('终端改名'),
        content: TextField(
          controller: controller,
          autofocus: true,
          onSubmitted: (v) => Navigator.pop(context, v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (name != null && workspace.tabs.contains(tab)) {
      workspace.rename(tab.id, name);
    }
    await Future<void>.delayed(const Duration(milliseconds: 300));
    controller.dispose();
  }

  Future<void> _copyTerminal(TerminalSession? session) async {
    if (session == null) return;
    final selection = terminalControllers[session]?.selection;
    if (selection == null) return;
    await Clipboard.setData(
      ClipboardData(text: session.terminal.buffer.getText(selection)),
    );
  }

  Future<void> _pasteTerminal(TerminalSession? session) async {
    if (session == null) return;
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (mounted && session.running && data?.text != null) {
      session.terminal.paste(data!.text!);
    }
  }

  Future<void> _terminalMenu(TerminalSession session, Offset position) async {
    final choice = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy,
        position.dx,
        position.dy,
      ),
      items: const [
        PopupMenuItem(value: 'copy', child: Text('复制选中内容')),
        PopupMenuItem(value: 'paste', child: Text('粘贴')),
      ],
    );
    if (choice == 'copy') await _copyTerminal(session);
    if (choice == 'paste') await _pasteTerminal(session);
  }
}

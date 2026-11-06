import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:xterm/xterm.dart';
import 'src/agent_server.dart';
import 'src/app_theme.dart';
import 'src/mac_controls.dart';
import 'src/terminal_session.dart';
import 'src/terminal_workspace.dart';
import 'src/settings.dart';
import 'src/ssh_credentials.dart';
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
  if (kDebugMode) debugPrint('[startup] Dart main entered');
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
    theme: desktopTheme(Brightness.light),
    darkTheme: desktopTheme(Brightness.dark),
    themeMode: ThemeMode.system,
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
  final terminalFocus = <TerminalSession, FocusNode>{};
  final agentInputFocus = FocusNode(debugLabel: 'Agent input');
  bool settingsOpen = false;
  bool agentCollapsed = false;
  bool tabsCollapsed = false;

  Future<void> _workspaceAction(String action) async {
    if (action == 'closeTab' && settingsOpen) {
      Navigator.of(context).maybePop();
      return;
    }
    if (settingsOpen) return;
    switch (action) {
      case 'newTerminal':
        _newTerminal();
      case 'closeTab':
        final tab = workspace.selected;
        if (tab != null) {
          _closeTerminal(tab);
        } else if (defaultTargetPlatform == TargetPlatform.macOS) {
          await lifecycle.invokeMethod<void>('closeWindow');
        }
      case 'settings':
        await _openSettings();
      case 'nextTab':
        _cycleTerminal(1);
      case 'previousTab':
        _cycleTerminal(-1);
      case 'focusAgent':
        if (agentCollapsed) {
          setState(() => agentCollapsed = false);
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) agentInputFocus.requestFocus();
          });
        } else {
          agentInputFocus.requestFocus();
        }
      case 'focusTerminal':
        _focusTerminal();
    }
  }

  void _collapseAgent() {
    agentInputFocus.unfocus();
    setState(() => agentCollapsed = true);
    _focusTerminal();
  }

  void _focusTerminal() {
    final selected = workspace.selected;
    if (selected != null) terminalFocus[selected.session]?.requestFocus();
  }

  void _selectTerminal(String id) {
    workspace.select(id);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusTerminal();
    });
  }

  void _cycleTerminal(int delta) {
    if (workspace.tabs.isEmpty) return;
    final current = workspace.tabs.indexOf(workspace.selected!);
    _selectTerminal(
      workspace.tabs[(current + delta) % workspace.tabs.length].id,
    );
  }

  void _closeTerminal(TerminalTab tab) {
    workspace.close(tab.id);
    terminalControllers.remove(tab.session)?.dispose();
    final focus = terminalFocus.remove(tab.session);
    // TerminalView's focus attachment is removed on the next frame.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      focus?.dispose();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusTerminal();
    });
  }

  Future<void> _tabMenu(TerminalTab tab, Offset position) async {
    final value = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy,
        position.dx,
        position.dy,
      ),
      items: const [
        PopupMenuItem(height: 28, value: 'rename', child: Text('重命名…')),
        PopupMenuItem(height: 28, value: 'close', child: Text('关闭终端')),
      ],
    );
    if (!mounted || !workspace.tabs.contains(tab)) return;
    if (value == 'rename') await _rename(tab);
    if (value == 'close') _closeTerminal(tab);
  }

  String get defaultTerminalId {
    final id = legacyId;
    if (id == null) throw StateError('尚未创建终端，请先新建终端');
    workspace.require(id);
    return id;
  }

  AgentServer? server;
  String? error;
  bool ready = false;
  final _startupWatch = Stopwatch()..start();

  void _startupMark(String phase) {
    if (kDebugMode) {
      debugPrint('[startup] $phase: ${_startupWatch.elapsedMilliseconds} ms');
    }
  }

  @override
  void initState() {
    super.initState();
    lifecycle.setMethodCallHandler((call) async {
      if (call.method.startsWith('edit:')) {
        return _nativeEdit(call.method.substring(5));
      }
      if (call.method == 'shutdown') {
        await _shutdown();
      } else {
        await _workspaceAction(call.method);
      }
    });
    workspace.addListener(_refresh);
    WidgetsBinding.instance.waitUntilFirstFrameRasterized.then((_) {
      if (mounted) _startupMark('first frame rasterized');
    });
    _start();
  }

  Future<void> _start() async {
    // Let the empty workspace paint before loading settings and the bridge.
    await WidgetsBinding.instance.endOfFrame;
    await Future<void>.delayed(Duration.zero);
    if (!mounted || shutdown != null) return;
    _startupMark('workspace frame submitted');
    try {
      if (defaultTargetPlatform == TargetPlatform.macOS) {
        // Install after Flutter's platform menu initialization as well as launch.
        // The native operation is idempotent, including on hot restart.
        await lifecycle.invokeMethod<bool>('installMenus');
      }
      try {
        await settings.load();
      } catch (e) {
        error = '配置读取失败，原文件已保留：$e';
      }
      _startupMark('settings loaded');
      if (!mounted || shutdown != null) return;
      final api = AgentServer(
        read: () => workspace.require(defaultTerminalId).session.snapshot(),
        write: (text) => _externalInput(defaultTerminalId, text),
        interrupt: () => _externalInput(defaultTerminalId, '\x03'),
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
      if (!mounted || shutdown != null) {
        await api.close();
        return;
      }
      setState(() => ready = true);
      _startupMark('bridge ready');
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
    final watch = Stopwatch()..start();
    await Future.wait<void>([
      if (server != null) server!.close(),
      for (final tab in workspace.tabs) tab.session.close(),
    ]);
    if (kDebugMode) {
      debugPrint(
        '[shutdown] resources closed: ${watch.elapsedMilliseconds} ms',
      );
    }
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
    for (final focus in terminalFocus.values) {
      focus.dispose();
    }
    agentInputFocus.dispose();
    taskDraft.dispose();
    super.dispose();
  }

  Future<bool> _nativeEdit(String action) async {
    final tab = workspace.selected;
    if (settingsOpen ||
        tab == null ||
        terminalFocus[tab.session]?.hasFocus != true) {
      final editable = FocusManager.instance.primaryFocus?.context
          ?.findAncestorStateOfType<EditableTextState>();
      if (editable == null) return false;
      switch (action) {
        case 'copy':
          editable.copySelection(SelectionChangedCause.keyboard);
        case 'paste':
          await editable.pasteText(SelectionChangedCause.keyboard);
        case 'selectAll':
          editable.selectAll(SelectionChangedCause.keyboard);
        default:
          return false;
      }
      return true;
    }
    switch (action) {
      case 'copy':
        await _copyTerminal(tab.session);
      case 'paste':
        await _pasteTerminal(tab.session);
      case 'selectAll':
        final terminal = tab.session.terminal;
        terminalControllers[tab.session]?.setSelection(
          terminal.buffer.createAnchor(0, 0),
          terminal.buffer.createAnchor(
            terminal.viewWidth,
            terminal.buffer.height - 1,
          ),
          mode: SelectionMode.line,
        );
      default:
        return false;
    }
    return true;
  }

  Widget _terminal(TerminalSession session) => Padding(
    padding: const EdgeInsets.all(8),
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
      focusNode: terminalFocus.putIfAbsent(
        session,
        () => FocusNode(debugLabel: 'Terminal'),
      ),
      textStyle: terminalTextStyle,
      backgroundOpacity: 0,
      hardwareKeyboardOnly: false,
      onKeyEvent: (_, event) {
        if (event is! KeyDownEvent ||
            !HardwareKeyboard.instance.isMetaPressed) {
          return KeyEventResult.ignored;
        }
        final action = switch (event.logicalKey) {
          LogicalKeyboardKey.keyT => 'newTerminal',
          LogicalKeyboardKey.keyW => 'closeTab',
          LogicalKeyboardKey.comma => 'settings',
          LogicalKeyboardKey.arrowLeft
              when HardwareKeyboard.instance.isAltPressed =>
            'previousTab',
          LogicalKeyboardKey.arrowRight
              when HardwareKeyboard.instance.isAltPressed =>
            'nextTab',
          LogicalKeyboardKey.keyA
              when HardwareKeyboard.instance.isShiftPressed =>
            'focusAgent',
          _ => null,
        };
        if (action == null) return KeyEventResult.ignored;
        // Never dispose a focused terminal from inside its key event callback.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _workspaceAction(action);
        });
        WidgetsBinding.instance.scheduleFrame();
        return KeyEventResult.handled;
      },
    ),
  );
  double tabWidth = 180;
  double agentFraction = .31;

  @override
  Widget build(BuildContext context) => CallbackShortcuts(
    bindings: {
      const SingleActivator(LogicalKeyboardKey.keyT, meta: true): () =>
          _workspaceAction('newTerminal'),
      const SingleActivator(LogicalKeyboardKey.keyW, meta: true): () =>
          _workspaceAction('closeTab'),
      const SingleActivator(LogicalKeyboardKey.comma, meta: true): () =>
          _workspaceAction('settings'),
      const SingleActivator(
        LogicalKeyboardKey.arrowRight,
        meta: true,
        alt: true,
      ): () =>
          _workspaceAction('nextTab'),
      const SingleActivator(
        LogicalKeyboardKey.arrowLeft,
        meta: true,
        alt: true,
      ): () =>
          _workspaceAction('previousTab'),
      const SingleActivator(
        LogicalKeyboardKey.keyA,
        meta: true,
        shift: true,
      ): () =>
          _workspaceAction('focusAgent'),
    },
    child: Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            _workspaceToolbar(),
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
                      (agentCollapsed ? 0 : width) -
                      200; // Space for the terminal and both handles.
                  final sidebar = tabWidth.clamp(120.0, maxSidebar);
                  return Row(
                    children: [
                      Offstage(
                        offstage: tabsCollapsed,
                        child: ExcludeFocus(
                          excluding: tabsCollapsed,
                          child: SizedBox(
                            key: const Key('terminal-sidebar'),
                            width: sidebar,
                            child: Column(
                              children: [
                                Expanded(
                                  child: ListView(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 4,
                                      vertical: 4,
                                    ),
                                    children: [
                                      for (final tab in workspace.tabs)
                                        MacSidebarItem(
                                          key: ValueKey(tab.id),
                                          label: tab.name,
                                          selected: tab == workspace.selected,
                                          running: tab.session.running,
                                          onSelect: () =>
                                              _selectTerminal(tab.id),
                                          onClose: () => _closeTerminal(tab),
                                          onRename: () => _rename(tab),
                                          onContextMenu: (p) =>
                                              _tabMenu(tab, p),
                                        ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      Visibility(
                        visible: !tabsCollapsed,
                        maintainState: true,
                        child: MacSplitHandle(
                          key: const Key('tabs-divider'),
                          axis: Axis.horizontal,
                          label: '终端侧栏宽度',
                          onReset: () => setState(() => tabWidth = 180),
                          onDelta: (dx) => setState(
                            () => tabWidth = (sidebar + dx).clamp(
                              120.0,
                              maxSidebar,
                            ),
                          ),
                        ),
                      ),
                      Expanded(
                        child: Container(
                          color: workspace.selected == null
                              ? Theme.of(
                                  context,
                                ).colorScheme.surfaceContainerLowest
                              : const Color(0xff15171a),
                          child: workspace.selected == null
                              ? Center(
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        CupertinoIcons
                                            .chevron_left_slash_chevron_right,
                                        size: 32,
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.onSurfaceVariant,
                                      ),
                                      const SizedBox(height: 14),
                                      const Text(
                                        '没有打开的终端',
                                        style: TextStyle(
                                          fontSize: 15,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        '打开本地 Shell，或从侧栏连接 SSH。',
                                        style: TextStyle(
                                          color: Theme.of(
                                            context,
                                          ).colorScheme.onSurfaceVariant,
                                        ),
                                      ),
                                      const SizedBox(height: 18),
                                      MacButton(
                                        onPressed: _newTerminal,
                                        label: '新建终端',
                                        icon: Icons.fiber_new,
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        '⌘T',
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall!
                                            .copyWith(
                                              color: Theme.of(
                                                context,
                                              ).colorScheme.onSurfaceVariant,
                                            ),
                                      ),
                                    ],
                                  ),
                                )
                              : _terminal(workspace.selected!.session),
                        ),
                      ),
                      Visibility(
                        visible: !agentCollapsed,
                        maintainState: true,
                        child: MacSplitHandle(
                          key: const Key('panel-divider'),
                          axis: Axis.horizontal,
                          label: 'Agent 面板宽度',
                          onReset: () => setState(() => agentFraction = .31),
                          onDelta: (dx) => setState(
                            () => agentFraction =
                                ((width - dx).clamp(
                                  248.0,
                                  bounds.maxWidth -
                                      (tabsCollapsed ? 0 : sidebar) -
                                      200,
                                )) /
                                bounds.maxWidth,
                          ),
                        ),
                      ),
                      // Keep the complete panel mounted at its expanded width.
                      // Collapsing must not dispose local UI or conversation state.
                      Offstage(
                        offstage: agentCollapsed,
                        child: ExcludeFocus(
                          excluding: agentCollapsed,
                          child: SizedBox(
                            width: width,
                            child: InternalAgentView(
                              agent: internal,
                              inputFocus: agentInputFocus,
                              task: taskDraft,
                              selected: selectedModel,
                              select: (m) => setState(() => selectedModel = m),
                              configure: () => _openSettings(),
                              settings: settings,
                              workspace: workspace,
                            ),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
            Container(
              constraints: const BoxConstraints(minHeight: 22),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(
                    color: Theme.of(context).colorScheme.outlineVariant,
                  ),
                ),
              ),
              child: DefaultTextStyle(
                style: Theme.of(context).textTheme.bodySmall!.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                child: Row(
                  children: [
                    const Icon(Icons.terminal_rounded, size: 13),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        workspace.selected?.id ?? '未选择终端',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );

  Widget _workspaceToolbar() => LayoutBuilder(
    builder: (context, bounds) {
      final colors = Theme.of(context).colorScheme;
      final agentWidth = (bounds.maxWidth * agentFraction).clamp(
        248.0,
        bounds.maxWidth - 320,
      );
      return Container(
        key: const Key('workspace-toolbar'),
        height: 36,
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: colors.outlineVariant)),
        ),
        child: Row(
          children: [
            SizedBox(
              width: tabsCollapsed ? 42 : 220,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Row(
                  children: [
                    Semantics(
                      expanded: !tabsCollapsed,
                      child: MacButton(
                        key: const Key('toggle-tabs'),
                        tooltip: tabsCollapsed ? '展开终端列表' : '收起终端列表',
                        icon: CupertinoIcons.sidebar_left,
                        toolbar: true,
                        onPressed: () {
                          setState(() => tabsCollapsed = !tabsCollapsed);
                          if (tabsCollapsed) _focusTerminal();
                        },
                      ),
                    ),
                    if (!tabsCollapsed) ...[
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          '${workspace.tabs.length} 个终端',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.labelMedium,
                        ),
                      ),
                      MacButton(
                        tooltip: '终端设置',
                        icon: CupertinoIcons.gear,
                        toolbar: true,
                        onPressed: () => _openSettings(ssh: true),
                      ),
                      MacButton(
                        tooltip: '新建终端',
                        icon: Icons.fiber_new,
                        toolbar: true,
                        onPressed: _newTerminal,
                      ),
                      MacPopup<SshProfile>(
                        label: '',
                        tooltip: '打开 SSH',
                        icon: Icons.view_list,
                        showChevron: false,
                        toolbar: true,
                        entries: [
                          for (final p in settings.ssh)
                            MacMenuEntry<SshProfile>(
                              p,
                              p.name,
                              icon: Icons.view_list,
                            ),
                        ],
                        onSelected: _newTerminal,
                      ),
                    ],
                  ],
                ),
              ),
            ),
            VerticalDivider(
              key: const Key('toolbar-left-divider'),
              width: 1,
              thickness: 1,
              indent: 9,
              endIndent: 9,
              color: colors.outlineVariant.withValues(alpha: .8),
            ),
            Expanded(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: MacButton(
                    key: const Key('rename-active-terminal'),
                    tooltip: workspace.selected == null ? '未选择终端' : '重命名当前终端',
                    toolbar: true,
                    onPressed: workspace.selected == null
                        ? null
                        : () => _rename(workspace.selected!),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(
                          child: Text(
                            workspace.selected?.name ?? '未选择终端',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (workspace.selected != null) ...[
                          const SizedBox(width: 6),
                          const Icon(CupertinoIcons.pencil, size: 12),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
            VerticalDivider(
              key: const Key('toolbar-right-divider'),
              width: 1,
              thickness: 1,
              indent: 9,
              endIndent: 9,
              color: colors.outlineVariant.withValues(alpha: .8),
            ),
            SizedBox(
              width: agentCollapsed ? 42 : agentWidth,
              child: ListenableBuilder(
                listenable: internal,
                builder: (context, _) => Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Row(
                    children: [
                      if (!agentCollapsed) ...[
                        const Icon(CupertinoIcons.sparkles, size: 14),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Tooltip(
                            message: internal.conversationTitle ?? 'Agent',
                            child: Text(
                              internal.conversationTitle ?? 'Agent',
                              key: const Key('agent-conversation-title'),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                        if (internal.running)
                          const Padding(
                            padding: EdgeInsets.only(right: 6),
                            child: Text('运行中', style: TextStyle(fontSize: 11)),
                          ),
                        MacButton(
                          tooltip: '新建 Agent 会话',
                          icon: CupertinoIcons.square_pencil,
                          toolbar: true,
                          onPressed: internal.running
                              ? null
                              : () {
                                  internal.newConversation();
                                  taskDraft.clear();
                                },
                        ),
                        MacButton(
                          tooltip: 'Agent 设置',
                          icon: CupertinoIcons.gear,
                          toolbar: true,
                          onPressed: () => _openSettings(),
                        ),
                      ],
                      Semantics(
                        expanded: !agentCollapsed,
                        child: MacButton(
                          key: const Key('toggle-agent'),
                          tooltip: agentCollapsed ? '展开 Agent' : '收起 Agent',
                          icon: CupertinoIcons.sidebar_right,
                          toolbar: true,
                          onPressed: () {
                            if (agentCollapsed) {
                              setState(() => agentCollapsed = false);
                            } else {
                              _collapseAgent();
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    },
  );

  Future<void> _openSettings({bool ssh = false}) async {
    if (settingsOpen) return;
    settingsOpen = true;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => Dialog(
        insetPadding: const EdgeInsets.all(20),
        clipBehavior: Clip.antiAlias,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720, maxHeight: 640),
          child: SettingsView(
            settings: settings,
            ssh: ssh,
            connection: ready ? server!.environment : const {},
          ),
        ),
      ),
    );
    settingsOpen = false;
    if (mounted) setState(() {});
  }

  Future<void> _newTerminal([SshProfile? ssh]) async {
    if (settingsOpen) return;
    try {
      final environment = ssh == null
          ? <String, String>{}
          : await SshCredentials.environment(ssh);
      if (!mounted) return;
      final tab = workspace.add(
        environment: environment,
        name: ssh?.name,
        executable: ssh == null ? null : 'ssh',
        arguments: ssh?.arguments ?? const [],
      );
      legacyId ??= tab.id;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _focusTerminal();
      });
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
          MacButton(onPressed: () => Navigator.pop(context), label: '取消'),
          MacButton(
            onPressed: () => Navigator.pop(context, controller.text),
            label: '保存',
            primary: true,
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
      terminalControllers[session]?.clearSelection();
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
        PopupMenuItem(height: 28, value: 'copy', child: Text('复制选中内容')),
        PopupMenuItem(height: 28, value: 'paste', child: Text('粘贴')),
      ],
    );
    if (choice == 'copy') await _copyTerminal(session);
    if (choice == 'paste') await _pasteTerminal(session);
  }
}

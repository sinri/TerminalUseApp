import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:xterm/xterm.dart';
import 'src/agent_server.dart';
import 'src/about_view.dart';
import 'src/app_theme.dart';
import 'src/mac_controls.dart';
import 'src/terminal_session.dart';
import 'src/terminal_workspace.dart';
import 'src/settings.dart';
import 'src/windows_shell.dart';
import 'src/ssh_credentials.dart';
import 'src/settings_view.dart';
import 'src/internal_agent.dart';
import 'src/agent_conversations.dart';
import 'src/agent_history_view.dart';
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
      'Terminal Use APP',
    ], await rootBundle.loadString('LICENSE'));
    yield LicenseEntryWithLineBreaks([
      'Nerd Fonts Symbols',
    ], await rootBundle.loadString('assets/fonts/NERD-FONTS-LICENSE.txt'));
  });
  runApp(const TerminalUseApp());
}

class TerminalUseApp extends StatelessWidget {
  const TerminalUseApp({super.key, this.historyFile});
  final File? historyFile;
  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    title: 'Terminal Use APP',
    theme: desktopTheme(Brightness.light),
    darkTheme: desktopTheme(Brightness.dark),
    themeMode: ThemeMode.system,
    home: Workspace(historyFile: historyFile),
  );
}

class Workspace extends StatefulWidget {
  const Workspace({super.key, this.historyFile});
  final File? historyFile;
  @override
  State<Workspace> createState() => _WorkspaceState();
}

class _WorkspaceState extends State<Workspace> {
  static const lifecycle = MethodChannel('terminal_use/lifecycle');
  final workspace = TerminalWorkspace();
  final settings = AppSettings();
  late final windowsShellDiscovery = WindowsShell.discover();
  final windowsShellMenuKey = GlobalKey();
  late final conversations = AgentConversations(
    workspace,
    settings,
    file: widget.historyFile,
  );
  InternalAgent get internal => conversations.active.agent;
  String? _visibleConversationId;
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
      case 'about':
        await showTerminalUseAbout(context);
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
      items: [
        if (Platform.isWindows && tab.windowsShell != null)
          const PopupMenuItem(
            height: 28,
            value: 'duplicate',
            child: Text('使用相同配置新建终端'),
          ),
        PopupMenuItem(height: 28, value: 'rename', child: Text('重命名…')),
        PopupMenuItem(
          height: 28,
          value: 'bind-agent',
          child: Text('绑定 Agent 会话…'),
        ),
        PopupMenuItem(
          height: 28,
          value: 'unbind-agent',
          child: Text('解绑 Agent 会话'),
        ),
        PopupMenuItem(height: 28, value: 'close', child: Text('关闭终端')),
      ],
    );
    if (!mounted || !workspace.tabs.contains(tab)) return;
    if (value == 'rename') await _rename(tab);
    if (value == 'duplicate') await _newTerminal(null, tab.windowsShell);
    if (value == 'close') _closeTerminal(tab);
    if (value == 'bind-agent') await _showHistory(tab: tab);
    if (value == 'unbind-agent') conversations.bind(tab, null);
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
    conversations.addListener(_conversationChanged);
    _visibleConversationId = conversations.active.id;
    taskDraft.addListener(_draftChanged);
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
      await conversations.load();
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

  void _draftChanged() => conversations.updateDraft(taskDraft.text);

  void _conversationChanged() {
    if (!mounted) return;
    if (_visibleConversationId != conversations.active.id) {
      _visibleConversationId = conversations.active.id;
      taskDraft.text = conversations.active.draft;
    }
    setState(() {});
  }

  Future<void> _showHistory({TerminalTab? tab}) => showDialog<void>(
    context: context,
    builder: (context) =>
        AgentHistoryDialog(conversations: conversations, tab: tab),
  );

  void _refresh() {
    if (mounted) setState(() {});
  }

  Future<void>? shutdown;
  Future<void> _shutdown() => shutdown ??= _closeResources();
  Future<void> _closeResources() async {
    conversations.clearBindings();
    conversations.stopAll();
    final watch = Stopwatch()..start();
    await Future.wait<void>([
      conversations.flush(),
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
    conversations.removeListener(_conversationChanged);
    taskDraft.removeListener(_draftChanged);
    workspace.removeListener(_refresh);
    _shutdown();
    conversations.dispose();
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
    // xterm paints partially visible rows while scrolling. Clip its viewport
    // so glyphs and row backgrounds cannot cover the workspace toolbar.
    child: ClipRect(
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
                              conversations: conversations,
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
                        onPressed: Platform.isWindows
                            ? _manageWindowsShells
                            : () => _openSettings(ssh: true),
                      ),
                      MacButton(
                        tooltip: '新建终端',
                        icon: Icons.fiber_new,
                        toolbar: true,
                        onPressed: _newTerminal,
                      ),
                      if (Platform.isWindows)
                        MacButton(
                          key: windowsShellMenuKey,
                          tooltip: '选择本地 Shell',
                          icon: Icons.expand_more,
                          toolbar: true,
                          onPressed: _chooseWindowsShell,
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
                listenable: conversations,
                builder: (context, _) => Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Row(
                    children: [
                      if (!agentCollapsed) ...[
                        const Icon(CupertinoIcons.sparkles, size: 14),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Tooltip(
                            message: conversations.active.title,
                            child: Text(
                              conversations.active.name ??
                                  internal.conversationTitle ??
                                  'Agent',
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
                          onPressed: conversations.create,
                        ),
                        MacButton(
                          key: const Key('agent-history'),
                          tooltip: conversations.storageError ?? 'Agent 会话历史',
                          icon: conversations.storageError == null
                              ? CupertinoIcons.clock
                              : CupertinoIcons.exclamationmark_triangle,
                          toolbar: true,
                          onPressed: () => _showHistory(),
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

  Future<void> _chooseWindowsShell() async {
    final shells = [...await windowsShellDiscovery, ...settings.windowsShells];
    if (!mounted) return;
    final selected = await showMenu<int>(
      context: context,
      positionBuilder: (context, constraints) {
        final button =
            windowsShellMenuKey.currentContext!.findRenderObject()!
                as RenderBox;
        final overlay =
            Overlay.of(context).context.findRenderObject()! as RenderBox;
        final bottomLeft = button.localToGlobal(
          Offset(0, button.size.height),
          ancestor: overlay,
        );
        return RelativeRect.fromRect(
          Rect.fromLTWH(bottomLeft.dx, bottomLeft.dy, button.size.width, 0),
          Offset.zero & overlay.size,
        );
      },
      items: [
        for (var i = 0; i < shells.length; i++)
          PopupMenuItem(value: i, child: Text(shells[i].name)),
        const PopupMenuItem(value: -1, child: Text('管理终端配置')),
      ],
    );
    if (!mounted || selected == null) return;
    if (selected == -1) {
      await _manageWindowsShells();
    } else {
      await _newTerminal(null, shells[selected]);
    }
  }

  Future<void> _manageWindowsShells() async {
    if (!Platform.isWindows || settingsOpen) return;
    final discovered = await windowsShellDiscovery;
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, update) {
          final shells = [...discovered, ...settings.windowsShells];
          Future<void> save() async {
            try {
              await settings.save();
            } catch (e) {
              if (mounted) setState(() => error = '$e');
            }
            if (context.mounted) update(() {});
            if (mounted) setState(() {});
          }

          return AlertDialog(
            title: const Text('Windows 终端配置'),
            content: SizedBox(
              width: 640,
              height: 400,
              child: ListView(
                children: [
                  for (final shell in shells)
                    ListTile(
                      title: Text(shell.name),
                      subtitle: Text(shell.executable),
                      trailing: Wrap(
                        children: [
                          IconButton(
                            tooltip: '设为默认',
                            icon: Icon(
                              shell.name ==
                                      (settings.defaultWindowsShell ??
                                          shells.first.name)
                                  ? Icons.star
                                  : Icons.star_border,
                            ),
                            onPressed: () async {
                              settings.defaultWindowsShell = shell.name;
                              await save();
                            },
                          ),
                          IconButton(
                            tooltip: '复制并编辑',
                            icon: const Icon(Icons.copy),
                            onPressed: () async {
                              final edited = await editWindowsShell(
                                context,
                                shell,
                              );
                              if (edited == null) return;
                              if (shells.any((s) => s.name == edited.name)) {
                                if (mounted) {
                                  setState(() => error = '名称已存在，请为复制的配置使用新名称');
                                }
                                return;
                              }
                              settings.windowsShells.add(edited);
                              await save();
                            },
                          ),
                          if (settings.windowsShells.contains(shell)) ...[
                            IconButton(
                              tooltip: '编辑',
                              icon: const Icon(Icons.edit),
                              onPressed: () async {
                                final edited = await editWindowsShell(
                                  context,
                                  shell,
                                );
                                if (edited == null) return;
                                if (shells.any(
                                  (s) =>
                                      !identical(s, shell) &&
                                      s.name == edited.name,
                                )) {
                                  if (mounted) setState(() => error = '名称已存在');
                                  return;
                                }
                                settings.windowsShells[settings.windowsShells
                                        .indexOf(shell)] =
                                    edited;
                                if (settings.defaultWindowsShell ==
                                    shell.name) {
                                  settings.defaultWindowsShell = edited.name;
                                }
                                await save();
                              },
                            ),
                            IconButton(
                              tooltip: '删除',
                              icon: const Icon(Icons.delete_outline),
                              onPressed: () async {
                                settings.windowsShells.remove(shell);
                                if (settings.defaultWindowsShell ==
                                    shell.name) {
                                  settings.defaultWindowsShell = null;
                                }
                                await save();
                              },
                            ),
                          ],
                        ],
                      ),
                    ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () async {
                  final shell = await editWindowsShell(context);
                  if (shell == null) return;
                  if (shells.any((s) => s.name == shell.name)) {
                    if (mounted) setState(() => error = '名称已存在');
                    return;
                  }
                  settings.windowsShells.add(shell);
                  await save();
                },
                child: const Text('添加自定义配置'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('完成'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _newTerminal([SshProfile? ssh, WindowsShell? localShell]) async {
    if (settingsOpen) return;
    try {
      if (Platform.isWindows && ssh == null) {
        final shells = [
          ...await windowsShellDiscovery,
          ...settings.windowsShells,
        ];
        localShell ??= shells
            .where((s) => s.name == settings.defaultWindowsShell)
            .firstOrNull;
        if (localShell == null && settings.defaultWindowsShell != null) {
          throw StateError('默认终端不可用，请从下拉菜单选择终端或管理配置');
        }
        localShell ??= shells.first;
      }
      final environment = ssh == null
          ? <String, String>{}
          : await SshCredentials.environment(ssh);
      if (!mounted) return;
      final tab = workspace.add(
        environment: {...environment, ...?localShell?.environment},
        name: ssh?.name ?? localShell?.name,
        executable: ssh == null ? localShell?.executable : 'ssh',
        arguments: ssh?.arguments ?? localShell?.arguments ?? const [],
        workingDirectory: localShell?.directory.isNotEmpty == true
            ? localShell!.directory
            : null,
        shellKind: ssh != null ? 'ssh' : localShell?.kind,
      );
      legacyId ??= tab.id;
      tab.windowsShell = localShell;
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

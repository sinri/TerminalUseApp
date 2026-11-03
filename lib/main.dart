import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:xterm/xterm.dart';
import 'src/agent_server.dart';
import 'src/agent_launcher.dart';
import 'src/terminal_session.dart';

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
  final shell = TerminalSession();
  TerminalSession? agent;
  AgentServer? server;
  final command = TextEditingController();
  String? error;
  bool ready = false;
  bool launching = false;
  bool get canLaunch => ready && !launching && !(agent?.running ?? false);
  String? activeAgent;
  Timer? connectionPoll;
  bool mcpConnected = false;
  bool automaticMcp = false;
  final Set<AgentLaunch> launches = {};
  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    try {
      shell.start();
      final api = AgentServer(
        read: shell.snapshot,
        write: shell.write,
        interrupt: shell.interrupt,
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

  Future<void> _launch([BuiltInAgent? choice]) async {
    if (!canLaunch || (choice == null && command.text.trim().isEmpty)) return;
    setState(() {
      launching = true;
      error = null;
    });
    AgentLaunch? launch;
    TerminalSession? session;
    try {
      if (choice != null) {
        launch = await AgentLauncher.prepare(choice, server!.environment);
        if (!mounted) {
          await launch.dispose();
          return;
        }
        launches.add(launch);
      }
      if (!mounted) return;
      connectionPoll?.cancel();
      mcpConnected = false;
      automaticMcp = choice != null;
      agent?.dispose();
      agent = null;
      session = TerminalSession();
      session.start(
        command: choice == null ? command.text.trim() : null,
        executable: launch?.executable,
        arguments: launch?.arguments ?? const [],
        environment: launch?.environment ?? server!.environment,
      );
      agent = session;
      activeAgent = choice?.name ?? '自定义命令';
      session.addListener(_refresh);
      if (launch != null) {
        final resources = launch;
        connectionPoll = Timer.periodic(const Duration(milliseconds: 500), (
          timer,
        ) {
          if (!mounted || session!.exitCode != null) {
            timer.cancel();
            return;
          }
          try {
            final marker = File(
              resources.environment['TERMINAL_USE_MCP_STATUS']!,
            );
            if (marker.existsSync() &&
                marker.readAsStringSync().contains('tools_listed')) {
              timer.cancel();
              setState(() => mcpConnected = true);
            }
          } on FileSystemException {
            /* A marker may be being written. */
          }
        });
        session.addListener(() {
          if (session!.exitCode != null) _release(resources);
        });
      }
    } catch (e) {
      session?.dispose();
      if (launch != null) await _release(launch);
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => launching = false);
    }
  }

  Future<void> _release(AgentLaunch launch) async {
    if (launches.remove(launch)) await launch.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    connectionPoll?.cancel();
    agent?.dispose();
    shell.dispose();
    server?.close();
    for (final launch in launches.toList()) {
      _release(launch);
    }
    command.dispose();
    super.dispose();
  }

  Widget _terminal(TerminalSession session) => Padding(
    padding: const EdgeInsets.all(12),
    child: TerminalView(
      session.terminal,
      autofocus: true,
      textStyle: terminalTextStyle,
      backgroundOpacity: 0,
      hardwareKeyboardOnly: true,
    ),
  );
  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: Color(0xff29333c))),
            ),
            child: Row(
              children: [
                const Icon(Icons.terminal, color: Color(0xff87e0bf)),
                const SizedBox(width: 12),
                const Text(
                  'TERMINAL USE',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    letterSpacing: 2,
                  ),
                ),
                const SizedBox(width: 18),
                const Text(
                  'Local workspace',
                  style: TextStyle(color: Colors.white38),
                ),
                const Spacer(),
                Icon(
                  Icons.circle,
                  size: 8,
                  color: ready ? const Color(0xff87e0bf) : Colors.orange,
                ),
                const SizedBox(width: 8),
                Text(ready ? 'Agent bridge ready' : 'Starting…'),
              ],
            ),
          ),
          if (error != null)
            MaterialBanner(
              content: Text(error!),
              actions: [
                TextButton(
                  onPressed: () => setState(() => error = null),
                  child: const Text('关闭'),
                ),
              ],
            ),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final left = Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _bar('01 / TERMINAL', [
                      TextButton.icon(
                        onPressed: () {
                          try {
                            shell.interrupt();
                          } catch (_) {}
                        },
                        icon: const Icon(Icons.stop_circle_outlined, size: 16),
                        label: const Text('Ctrl+C'),
                      ),
                    ]),
                    Expanded(child: _terminal(shell)),
                  ],
                );
                final right = Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _bar('02 / AGENT', [
                      if (agent?.running ?? false)
                        TextButton(
                          onPressed: () => agent?.stop(),
                          child: const Text('停止'),
                        ),
                    ]),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 340),
                      child: SingleChildScrollView(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                '让 agent 操作同一个终端',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 8),
                              const Text(
                                '选择已安装的 CLI，自动连接左侧终端。沿用 CLI 的模型和登录配置。',
                                style: TextStyle(
                                  color: Colors.white54,
                                  height: 1.6,
                                ),
                              ),
                              const SizedBox(height: 16),
                              Wrap(
                                spacing: 12,
                                runSpacing: 8,
                                children: [
                                  FilledButton.icon(
                                    onPressed: canLaunch
                                        ? () => _launch(BuiltInAgent.opencode)
                                        : null,
                                    icon: const Icon(Icons.code),
                                    label: const Text('启动 OpenCode'),
                                  ),
                                  FilledButton.tonalIcon(
                                    onPressed: canLaunch
                                        ? () => _launch(BuiltInAgent.codex)
                                        : null,
                                    icon: const Icon(Icons.terminal),
                                    label: const Text('启动 Codex'),
                                  ),
                                ],
                              ),
                              if (launching)
                                const Padding(
                                  padding: EdgeInsets.only(top: 12),
                                  child: Text('正在准备 CLI 并检查 MCP 连接…'),
                                ),
                              if (activeAgent != null && !launching)
                                Padding(
                                  padding: const EdgeInsets.only(top: 12),
                                  child: Text(
                                    '$activeAgent · ${agent?.running == true ? "运行中" : "已退出"}${automaticMcp && agent?.running == true ? (mcpConnected ? " · MCP 已连接" : " · MCP 连接中") : ""}',
                                    style: const TextStyle(
                                      color: Colors.white54,
                                    ),
                                  ),
                                ),
                              ExpansionTile(
                                tilePadding: EdgeInsets.zero,
                                title: const Text(
                                  '高级：其他启动命令',
                                  style: TextStyle(fontSize: 13),
                                ),
                                children: [
                                  TextField(
                                    controller: command,
                                    decoration: const InputDecoration(
                                      labelText: 'Agent 启动命令',
                                      border: OutlineInputBorder(),
                                    ),
                                    onSubmitted: (_) => _launch(),
                                  ),
                                  const SizedBox(height: 8),
                                  Wrap(
                                    spacing: 8,
                                    children: [
                                      TextButton.icon(
                                        onPressed: canLaunch
                                            ? () => _launch()
                                            : null,
                                        icon: const Icon(Icons.play_arrow),
                                        label: const Text('启动自定义命令'),
                                      ),
                                      TextButton(
                                        onPressed: ready
                                            ? () async {
                                                await Clipboard.setData(
                                                  ClipboardData(
                                                    text:
                                                        'TERMINAL_USE_URL=${server!.url}\nTERMINAL_USE_TOKEN=${server!.token}',
                                                  ),
                                                );
                                                if (context.mounted) {
                                                  ScaffoldMessenger.of(
                                                    context,
                                                  ).showSnackBar(
                                                    const SnackBar(
                                                      content: Text(
                                                        '连接参数已复制，包含访问令牌',
                                                      ),
                                                    ),
                                                  );
                                                }
                                              }
                                            : null,
                                        child: const Text('复制连接参数'),
                                      ),
                                    ],
                                  ),
                                  const Text(
                                    '自定义命令需自行配置 MCP。',
                                    style: TextStyle(color: Colors.white38),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: agent != null
                          ? _terminal(agent!)
                          : const Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.hub_outlined,
                                    size: 40,
                                    color: Colors.white24,
                                  ),
                                  SizedBox(height: 16),
                                  Text(
                                    '等待 Agent 连接',
                                    style: TextStyle(color: Colors.white38),
                                  ),
                                ],
                              ),
                            ),
                    ),
                  ],
                );
                if (constraints.maxWidth < 800) {
                  return Column(
                    children: [
                      Expanded(child: left),
                      const Divider(height: 1),
                      Expanded(child: right),
                    ],
                  );
                }
                return Row(
                  children: [
                    Expanded(flex: 3, child: left),
                    const VerticalDivider(width: 1),
                    Expanded(flex: 2, child: right),
                  ],
                );
              },
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 9),
            color: const Color(0xff192128),
            child: Row(
              children: [
                const Text(
                  'PTY  /  UTF-8  /  xterm-256color',
                  style: TextStyle(fontSize: 11, color: Colors.white54),
                ),
                const Spacer(),
                Text(
                  server == null || !ready ? 'LOCAL ONLY' : server!.url,
                  style: const TextStyle(fontSize: 11, color: Colors.white54),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
  Widget _bar(String title, List<Widget> actions) => Container(
    height: 48,
    padding: const EdgeInsets.symmetric(horizontal: 20),
    color: const Color(0xff151b21),
    child: Row(
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 11,
            letterSpacing: 1.5,
            color: Colors.white54,
          ),
        ),
        const Spacer(),
        ...actions,
      ],
    ),
  );
}

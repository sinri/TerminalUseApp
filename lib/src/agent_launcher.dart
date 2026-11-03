import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

enum BuiltInAgent { opencode, codex }

/// Per-launch settings; the user's CLI config and authentication stay in place.
class AgentLaunch {
  AgentLaunch({
    required this.executable,
    required this.arguments,
    required this.environment,
    required this.directory,
  });
  final String executable;
  final List<String> arguments;
  final Map<String, String> environment;
  final Directory directory;
  Future<void> dispose() async {
    if (await directory.exists()) await directory.delete(recursive: true);
  }
}

class AgentLauncher {
  static const serverName = 'terminal_use';

  static List<String> codexConfig(String python, String bridge) => [
    '-c',
    'mcp_servers.$serverName.command=${jsonEncode(python)}',
    '-c',
    'mcp_servers.$serverName.args=${jsonEncode([bridge, 'mcp'])}',
    '-c',
    'mcp_servers.$serverName.env_vars=["TERMINAL_USE_URL","TERMINAL_USE_TOKEN","TERMINAL_USE_MCP_STATUS"]',
    '-c',
    'mcp_servers.$serverName.enabled=true',
  ];

  static Map<String, dynamic> openCodeConfig(
    String python,
    String bridge, {
    bool v2 = false,
    Map<String, dynamic> inherited = const {},
  }) {
    final mcp = Map<String, dynamic>.from(inherited['mcp'] as Map? ?? {});
    final definition = {
      'type': 'local',
      'command': [python, bridge, 'mcp'],
      if (v2) 'disabled': false else 'enabled': true,
      if (v2) 'codemode': false,
      'environment': {
        'TERMINAL_USE_URL': '{env:TERMINAL_USE_URL}',
        'TERMINAL_USE_TOKEN': '{env:TERMINAL_USE_TOKEN}',
        'TERMINAL_USE_MCP_STATUS': '{env:TERMINAL_USE_MCP_STATUS}',
      },
    };
    if (v2) {
      mcp['servers'] = {
        ...?mcp['servers'] as Map<String, dynamic>?,
        serverName: definition,
      };
    } else {
      mcp[serverName] = definition;
    }
    return {...inherited, 'mcp': mcp};
  }

  static Future<Map<String, String>> _environment() async {
    final env = Map<String, String>.from(Platform.environment);
    if (!Platform.isWindows) {
      // Finder-launched apps do not inherit the user's login-shell PATH.
      final result = await Process.run(env['SHELL'] ?? '/bin/sh', [
        '-lc',
        r'''printf '\nTERMINAL_USE_PATH=%s\n' "$PATH"''',
      ]).timeout(const Duration(seconds: 10));
      for (final line in const LineSplitter().convert(
        result.stdout as String,
      )) {
        if (line.startsWith('TERMINAL_USE_PATH=')) {
          env['PATH'] = line.substring('TERMINAL_USE_PATH='.length);
        }
      }
    }
    return env;
  }

  static String _resolve(String name, Map<String, String> env) {
    final separator = Platform.isWindows ? ';' : ':';
    final extensions = Platform.isWindows ? ['', '.exe', '.cmd', '.bat'] : [''];
    for (final directory in (env['PATH'] ?? '').split(separator)) {
      if (directory.isEmpty) continue;
      for (final extension in extensions) {
        final file = File('$directory${Platform.pathSeparator}$name$extension');
        if (file.existsSync()) return file.absolute.path;
      }
    }
    throw StateError('未找到 $name，请先安装，并确认可在登录 shell 中运行。');
  }

  static Future<AgentLaunch> prepare(
    BuiltInAgent agent,
    Map<String, String> connection,
  ) async {
    final env = await _environment();
    env.addAll(connection);
    final executable = _resolve(agent.name, env);
    final python = _resolve(Platform.isWindows ? 'python' : 'python3', env);
    final help = await Process.run(executable, [
      '--help',
    ], environment: env).timeout(const Duration(seconds: 10));
    if (help.exitCode != 0) {
      throw StateError('${agent.name} 无法启动：${help.stderr}');
    }
    final helpText = '${help.stdout}';
    final directory = await Directory.systemTemp.createTemp('terminal-use-');
    try {
      final bridge = File('${directory.path}/terminal_bridge.py');
      await bridge.writeAsString(
        await rootBundle.loadString('tools/terminal_bridge.py'),
      );
      await _checkBridge(python, bridge.path, env);
      env['TERMINAL_USE_MCP_STATUS'] = '${directory.path}/mcp-status.json';
      late List<String> args;
      if (agent == BuiltInAgent.codex) {
        args = [
          if (helpText.contains('--no-daemon')) '--no-daemon',
          ...codexConfig(python, bridge.path),
        ];
      } else {
        final inherited = env['OPENCODE_CONFIG_CONTENT'];
        env['OPENCODE_CONFIG_CONTENT'] = jsonEncode(
          openCodeConfig(
            python,
            bridge.path,
            v2: helpText.contains('--standalone'),
            inherited: inherited == null
                ? {}
                : jsonDecode(inherited) as Map<String, dynamic>,
          ),
        );
        args = [if (helpText.contains('--standalone')) '--standalone'];
      }
      return AgentLaunch(
        executable: executable,
        arguments: args,
        environment: env,
        directory: directory,
      );
    } catch (_) {
      await directory.delete(recursive: true);
      rethrow;
    }
  }

  static Future<void> _checkBridge(
    String python,
    String bridge,
    Map<String, String> env,
  ) async {
    final process = await Process.start(python, [
      bridge,
      'mcp',
    ], environment: env);
    final output = process.stdout.transform(utf8.decoder).join();
    final errors = process.stderr.transform(utf8.decoder).join();
    try {
      for (final request in [
        {
          'jsonrpc': '2.0',
          'id': 1,
          'method': 'initialize',
          'params': {
            'protocolVersion': '2024-11-05',
            'capabilities': {},
            'clientInfo': {'name': 'terminal-use', 'version': '1.0'},
          },
        },
        {'jsonrpc': '2.0', 'method': 'notifications/initialized'},
        {
          'jsonrpc': '2.0',
          'id': 2,
          'method': 'tools/call',
          'params': {'name': 'terminal_read', 'arguments': {}},
        },
      ]) {
        process.stdin.writeln(jsonEncode(request));
      }
      await process.stdin.close();
      final code = await process.exitCode.timeout(const Duration(seconds: 10));
      final replies = const LineSplitter()
          .convert(await output)
          .map(jsonDecode)
          .toList();
      final read = replies.firstWhere((reply) => reply['id'] == 2);
      if (code != 0 ||
          read['result'] == null ||
          read['result']['isError'] == true) {
        throw StateError('MCP 连接检查失败：${await errors} $read');
      }
    } finally {
      process.kill();
    }
  }
}

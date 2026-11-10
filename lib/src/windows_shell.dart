import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';

class WindowsShell {
  const WindowsShell({
    required this.name,
    required this.executable,
    this.arguments = const [],
    this.directory = '',
    this.environment = const {},
    this.kind = 'custom',
  });
  final String name, executable, directory, kind;
  final List<String> arguments;
  final Map<String, String> environment;
  Map<String, dynamic> toJson() => {
    'name': name,
    'executable': executable,
    'arguments': arguments,
    'directory': directory,
    'environment': environment,
    'kind': kind,
  };
  factory WindowsShell.fromJson(Map<String, dynamic> j) => WindowsShell(
    name: j['name'] as String,
    executable: j['executable'] as String,
    arguments: (j['arguments'] as List? ?? []).cast<String>(),
    directory: j['directory'] as String? ?? '',
    kind: j['kind'] as String? ?? 'custom',
    environment: Map<String, String>.from(j['environment'] as Map? ?? {}),
  );

  static Future<List<WindowsShell>> discover() async {
    if (!Platform.isWindows) return [];
    final env = Platform.environment;
    final system = '${env['SystemRoot'] ?? r'C:\Windows'}\\System32';
    final shells = <WindowsShell>[];
    final pwshPaths = [
      '${env['ProgramFiles']}\\PowerShell\\7\\pwsh.exe',
      for (final path in (env['PATH'] ?? '').split(';')) '$path\\pwsh.exe',
    ];
    final pwsh = pwshPaths.where((p) => File(p).existsSync()).firstOrNull;
    if (pwsh != null) {
      shells.add(
        WindowsShell(
          name: 'PowerShell 7',
          executable: pwsh,
          kind: 'powershell',
        ),
      );
    }
    shells.add(
      WindowsShell(
        name: 'Windows PowerShell',
        executable: '$system\\WindowsPowerShell\\v1.0\\powershell.exe',
        kind: 'powershell',
      ),
    );
    shells.add(
      WindowsShell(name: '命令提示符', executable: '$system\\cmd.exe', kind: 'cmd'),
    );
    for (final base in [
      env['ProgramFiles'],
      env['ProgramFiles(x86)'],
      '${env['LOCALAPPDATA']}\\Programs',
    ]) {
      final bash = '$base\\Git\\bin\\bash.exe';
      if (File(bash).existsSync()) {
        shells.add(
          WindowsShell(
            name: 'Git Bash',
            executable: bash,
            arguments: const ['--login', '-i'],
            kind: 'bash',
          ),
        );
        break;
      }
    }
    if (File('$system\\wsl.exe').existsSync()) {
      try {
        final result = await Process.run('$system\\wsl.exe', [
          '--list',
          '--quiet',
        ], stdoutEncoding: null).timeout(const Duration(seconds: 5));
        if (result.exitCode == 0) {
          final bytes = result.stdout as List<int>;
          final output = bytes.contains(0)
              ? String.fromCharCodes([
                  for (var i = 0; i + 1 < bytes.length; i += 2)
                    bytes[i] | bytes[i + 1] << 8,
                ])
              : utf8.decode(bytes, allowMalformed: true);
          for (final distro
              in output
                  .replaceAll('\ufeff', '')
                  .split(RegExp(r'[\r\n]+'))
                  .map((s) => s.trim())
                  .where((s) => s.isNotEmpty)) {
            shells.add(
              WindowsShell(
                name: 'WSL · $distro',
                executable: '$system\\wsl.exe',
                arguments: ['-d', distro],
                kind: 'wsl',
              ),
            );
          }
        }
      } catch (_) {
        /* WSL may be installed without configured distributions. */
      }
    }
    return shells;
  }
}

Future<WindowsShell?> editWindowsShell(
  BuildContext context, [
  WindowsShell? shell,
]) async {
  final fields = [
    TextEditingController(text: shell?.name ?? ''),
    TextEditingController(text: shell?.executable ?? ''),
    TextEditingController(text: jsonEncode(shell?.arguments ?? [])),
    TextEditingController(text: shell?.directory ?? ''),
    TextEditingController(text: jsonEncode(shell?.environment ?? {})),
  ];
  String? error;
  var kind = shell?.kind ?? 'custom';
  var skipProfile = shell?.arguments.contains('-NoProfile') ?? false;
  final result = await showDialog<WindowsShell>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, update) => AlertDialog(
        title: const Text('终端启动配置'),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: kind,
                  decoration: const InputDecoration(labelText: 'Shell 类型'),
                  items: [
                    for (final value in [
                      'powershell',
                      'cmd',
                      'bash',
                      'wsl',
                      'custom',
                    ])
                      DropdownMenuItem(value: value, child: Text(value)),
                  ],
                  onChanged: (value) => update(() => kind = value!),
                ),
                if (kind == 'powershell')
                  CheckboxListTile(
                    title: const Text('跳过 PowerShell Profile'),
                    value: skipProfile,
                    onChanged: (value) => update(() => skipProfile = value!),
                  ),
                for (var i = 0; i < fields.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: TextField(
                      controller: fields[i],
                      decoration: InputDecoration(
                        labelText: [
                          '名称',
                          '程序路径',
                          '参数（JSON 数组）',
                          '启动目录（留空使用用户目录）',
                          '环境变量（JSON 对象）',
                        ][i],
                      ),
                    ),
                  ),
                if (error != null)
                  Text(
                    error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              try {
                if (fields[0].text.trim().isEmpty ||
                    fields[1].text.trim().isEmpty) {
                  throw const FormatException('请填写名称和程序路径');
                }
                final arguments = (jsonDecode(fields[2].text) as List)
                    .cast<String>()
                    .toList();
                if (kind == 'powershell') {
                  arguments.removeWhere((a) => a.toLowerCase() == '-noprofile');
                  if (skipProfile) arguments.add('-NoProfile');
                }
                Navigator.pop(
                  context,
                  WindowsShell(
                    name: fields[0].text.trim(),
                    executable: fields[1].text.trim(),
                    arguments: arguments,
                    directory: fields[3].text.trim(),
                    environment: Map<String, String>.from(
                      jsonDecode(fields[4].text) as Map,
                    ),
                    kind: kind,
                  ),
                );
              } catch (e) {
                update(() => error = '配置无效：$e');
              }
            },
            child: const Text('保存'),
          ),
        ],
      ),
    ),
  );
  // Dialog route animations can still reference the controllers.
  await Future<void>.delayed(const Duration(milliseconds: 300));
  for (final field in fields) {
    field.dispose();
  }
  return result;
}

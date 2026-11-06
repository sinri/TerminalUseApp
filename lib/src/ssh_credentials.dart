import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'settings.dart';

/// Secrets live in Keychain; only a non-secret account identifier reaches SSH.
class SshCredentials {
  static const channel = MethodChannel('terminal_use/ssh_credentials');
  static String account(SshProfile p) =>
      base64Url.encode(utf8.encode(jsonEncode([p.host, p.port, p.user])));

  static Future<String> read(SshProfile p) async => !Platform.isMacOS
      ? ''
      : await channel.invokeMethod<String>('read', {'account': account(p)}) ??
            '';

  static Future<void> save(SshProfile p, String password) async {
    await channel.invokeMethod<void>('save', {
      'account': account(p),
      'password': password,
    });
  }

  static Directory? _helperDirectory;
  static Future<Map<String, String>> environment(SshProfile p) async {
    if (!Platform.isMacOS || !p.password || (await read(p)).isEmpty) return {};
    if (_helperDirectory == null) {
      final directory = await Directory.systemTemp.createTemp(
        'terminal-use-askpass-',
      );
      final helper = File('${directory.path}/askpass');
      await helper.writeAsString(r'''#!/bin/sh
case "$1" in
  *[Pp]assword:|*[Pp]assword:\ )
    exec /usr/bin/security find-generic-password -s com.terminal-use.ssh -a "$TERMINAL_USE_SSH_ACCOUNT" -w
    ;;
  *)
    printf '%s ' "$1" > /dev/tty
    IFS= read -r answer < /dev/tty || exit 1
    printf '%s\n' "$answer"
    ;;
esac
''');
      final result = await Process.run('/bin/chmod', ['700', helper.path]);
      if (result.exitCode != 0) {
        await directory.delete(recursive: true);
        throw const FileSystemException('无法创建 SSH 密码助手');
      }
      _helperDirectory = directory;
    }
    return {
      'SSH_ASKPASS': '${_helperDirectory!.path}/askpass',
      'SSH_ASKPASS_REQUIRE': 'prefer',
      'DISPLAY': 'terminal-use',
      'TERMINAL_USE_SSH_ACCOUNT': account(p),
    };
  }
}

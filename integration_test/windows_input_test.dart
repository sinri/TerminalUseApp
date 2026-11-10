import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:terminal_use_app/src/terminal_session.dart';
import 'package:terminal_use_app/src/windows_shell.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('Git Bash preserves executable and command arguments', (
    tester,
  ) async {
    if (!Platform.isWindows) return;
    await tester.runAsync(() async {
      final shells = await WindowsShell.discover();
      final bash = shells.where((s) => s.kind == 'bash').firstOrNull;
      if (bash == null) return;
      final session = TerminalSession();
      try {
        session.start(
          executable: bash.executable,
          arguments: [
            '--noprofile',
            '--norc',
            '-c',
            "printf '%s' 'BASH ARG 中文'; sleep 1",
          ],
          kind: 'bash',
        );
        for (var i = 0; i < 100; i++) {
          if (session.terminal.buffer.getText().contains('BASH ARG 中文')) return;
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }
        fail(session.terminal.buffer.getText());
      } finally {
        await session.close();
        session.dispose();
      }
    });
  });
  testWidgets('PowerShell accepts consecutive interactive input', (
    tester,
  ) async {
    if (!Platform.isWindows) return;
    final session = TerminalSession();
    try {
      session.start();
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(seconds: 3));
        for (final character in "Write-Output ('INPUT_' + 'OK')\r".split('')) {
          session.terminal.textInput(character);
          await Future<void>.delayed(const Duration(milliseconds: 20));
        }
        for (var i = 0; i < 100; i++) {
          if (session.terminal.buffer.getText().contains('INPUT_OK')) return;
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }
        fail(session.terminal.buffer.getText());
      });
    } finally {
      await session.close();
      session.dispose();
    }
  });
}

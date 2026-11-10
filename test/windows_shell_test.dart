import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:terminal_use_app/src/settings.dart';
import 'package:terminal_use_app/src/windows_shell.dart';

void main() {
  test(
    'Windows shell settings preserve paths, arguments and environment',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'shell-settings-',
      );
      try {
        final file = File('${directory.path}/settings.json');
        final settings = AppSettings();
        settings.windowsShells.add(
          const WindowsShell(
            name: '开发环境',
            executable: r'C:\Program Files\PowerShell\7\pwsh.exe',
            arguments: ['-NoProfile', '-NoLogo'],
            directory: r'C:\My Projects',
            environment: {'TEST_VALUE': '中文 value'},
            kind: 'powershell',
          ),
        );
        settings.defaultWindowsShell = '开发环境';
        await settings.save(file: file);
        final loaded = AppSettings();
        await loaded.load(file: file);
        expect(loaded.defaultWindowsShell, '开发环境');
        expect(
          loaded.windowsShells.single.toJson(),
          settings.windowsShells.single.toJson(),
        );
        await file.writeAsString('{}');
        await loaded.load(file: file);
        expect(loaded.windowsShells, isEmpty);
        expect(loaded.defaultWindowsShell, isNull);
      } finally {
        await directory.delete(recursive: true);
      }
    },
  );
  test('shell discovery follows the host platform', () async {
    final shells = await WindowsShell.discover();
    if (Platform.isWindows) {
      expect(shells.map((s) => s.kind), containsAll(['powershell', 'cmd']));
      expect(shells.every((s) => File(s.executable).existsSync()), isTrue);
    } else {
      expect(shells, isEmpty);
    }
  });
}

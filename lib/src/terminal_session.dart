import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_pty/flutter_pty.dart';
import 'package:xterm/xterm.dart';

class TerminalSession extends ChangeNotifier {
  final terminal = Terminal(maxLines: 10000);
  Pty? _pty;
  StreamSubscription<String>? _subscription;
  int? exitCode;
  bool _disposed = false;
  bool _stopping = false;
  Future<void>? _closing;
  bool get running => _pty != null && exitCode == null;
  int? get pid => _pty?.pid;

  void start({
    String? command,
    String? executable,
    List<String> arguments = const [],
    Map<String, String> environment = const {},
  }) {
    if (_pty != null) throw StateError('Session already started');
    final shell = Platform.isWindows
        ? 'powershell.exe'
        : Platform.environment['SHELL'] ?? '/bin/sh';
    final args = command == null
        ? (Platform.isWindows ? <String>[] : ['-l'])
        : (Platform.isWindows
              ? ['-NoLogo', '-Command', command]
              : ['-lc', command]);
    final pty = Pty.start(
      executable ?? shell,
      arguments: executable == null ? args : arguments,
      workingDirectory: Platform.environment['HOME'] ?? Directory.current.path,
      environment: {
        ...Platform.environment,
        ...environment,
        'TERM': 'xterm-256color',
        'COLORTERM': 'truecolor',
      },
      columns: terminal.viewWidth,
      rows: terminal.viewHeight,
    );
    _pty = pty;
    _subscription = pty.output
        .cast<List<int>>()
        .transform(const Utf8Decoder(allowMalformed: true))
        .listen(terminal.write);
    terminal.onOutput = write;
    terminal.onResize = (w, h, pw, ph) => pty.resize(h, w);
    pty.exitCode.then((code) {
      exitCode = code;
      if (_disposed) return;
      terminal.write('\r\n[Process exited: $code]\r\n');
      notifyListeners();
    });
    notifyListeners();
  }

  void write(String data) {
    if (!running) throw StateError('Terminal process is not running');
    _pty!.write(Uint8List.fromList(utf8.encode(data)));
  }

  void interrupt() => write('\x03');
  void stop() {
    if (!running || _stopping) return;
    _stopping = true;
    _closing = _hangup();
  }

  Future<void> close() {
    stop();
    return _closing ?? Future<void>.value();
  }

  Future<void> _hangup() async {
    final processId = pid!;
    if (Platform.isWindows) {
      await Process.run('taskkill', ['/PID', '$processId', '/T', '/F']);
      return;
    }
    if (!Platform.isWindows) {
      try {
        // Job-control shells give foreground jobs separate process groups.
        // Send HUP to all members of this PTY, preserving nohup's ignored HUP.
        final result = await Process.run('/bin/ps', [
          '-axo',
          'pid=,tty=',
        ]).timeout(const Duration(milliseconds: 500));
        final rows = (result.stdout as String)
            .split('\n')
            .map((line) => line.trim().split(RegExp(r'\s+')))
            .where((row) => row.length == 2)
            .toList();
        final own = rows.where((row) => row[0] == '$processId').firstOrNull;
        if (own != null && own[1] != '??' && own[1] != '?') {
          for (final row in rows.where(
            (row) => row[1] == own[1] && row[0] != '$processId',
          )) {
            Process.killPid(int.parse(row[0]), ProcessSignal.sighup);
          }
        }
        if (exitCode == null) Process.killPid(processId, ProcessSignal.sighup);
      } catch (_) {
        /* Fall back to terminating the shell. */
      }
    }
    if (exitCode == null) _pty!.kill();
    // Finish promptly when the shell exits; the grace period is an upper bound.
    try {
      await _pty!.exitCode.timeout(const Duration(milliseconds: 500));
    } on TimeoutException {
      if (exitCode == null) _pty!.kill(ProcessSignal.sigkill);
    }
  }

  Map<String, dynamic> snapshot() => {
    'pid': pid,
    'running': running,
    'exitCode': exitCode,
    'columns': terminal.viewWidth,
    'rows': terminal.viewHeight,
    'text': terminal.buffer.getText(),
  };
  @override
  void dispose() {
    _disposed = true;
    stop();
    _subscription?.cancel();
    terminal.onOutput = null;
    terminal.onResize = null;
    super.dispose();
  }
}

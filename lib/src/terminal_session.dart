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
      if (_disposed) return;
      exitCode = code;
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
    if (running) _pty!.kill();
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

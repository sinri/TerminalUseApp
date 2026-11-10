import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'dart:math';

/// Loopback-only capability API. No credentials are written to disk.
class AgentServer {
  AgentServer({
    required this.read,
    required this.write,
    required this.interrupt,
    this.list,
    this.readTerminal,
    this.writeTerminal,
    this.interruptTerminal,
  });
  final List<Map<String, dynamic>> Function()? list;
  final Map<String, dynamic> Function(String)? readTerminal;
  final FutureOr<void> Function(String, String)? writeTerminal;
  final FutureOr<void> Function(String)? interruptTerminal;
  final Map<String, dynamic> Function() read;
  final FutureOr<void> Function(String) write;
  final FutureOr<void> Function() interrupt;
  final token = List.generate(
    32,
    (_) => Random.secure().nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();
  HttpServer? _server;
  String get url => 'http://127.0.0.1:${_server!.port}';
  Map<String, String> get environment => {
    'TERMINAL_USE_URL': url,
    'TERMINAL_USE_TOKEN': token,
  };
  Future<void> start() async {
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server!.listen(_handle);
  }

  Future<void> _handle(HttpRequest request) async {
    final response = request.response;
    response.headers.contentType = ContentType.json;
    try {
      if (request.headers.value('authorization') != 'Bearer $token') {
        response.statusCode = 401;
        response.write(jsonEncode({'error': 'Unauthorized'}));
      } else if (request.method == 'GET' && request.uri.path == '/terminals') {
        response.write(jsonEncode({'terminals': list?.call() ?? []}));
      } else if (request.method == 'GET' && request.uri.path == '/terminal') {
        final id = request.uri.queryParameters['terminal_id'];
        response.write(jsonEncode(id == null ? read() : _read(id)));
      } else if (request.method == 'POST' && request.uri.path == '/input') {
        final bytes = <int>[];
        var oversized = false;
        await for (final chunk in request.timeout(const Duration(seconds: 5))) {
          if (!oversized && bytes.length + chunk.length <= 65536) {
            bytes.addAll(chunk);
          } else {
            oversized = true;
          }
        }
        if (oversized) throw const FormatException('Input exceeds 64 KiB');
        final body = jsonDecode(utf8.decode(bytes));
        if (body is! Map || body['text'] is! String) {
          throw const FormatException('Expected text string');
        }
        final id = request.uri.queryParameters['terminal_id'];
        if (id == null) {
          await write(body['text'] as String);
        } else {
          _read(id);
          await writeTerminal!(id, body['text'] as String);
        }
        response.write('{"ok":true}');
      } else if (request.method == 'POST' && request.uri.path == '/interrupt') {
        final id = request.uri.queryParameters['terminal_id'];
        if (id == null) {
          await interrupt();
        } else {
          _read(id);
          await interruptTerminal!(id);
        }
        response.write('{"ok":true}');
      } else {
        response.statusCode = 404;
        response.write('{"error":"Unknown endpoint"}');
      }
    } on FormatException catch (e) {
      response.statusCode = 400;
      response.write(jsonEncode({'error': e.message}));
    } catch (e) {
      response.statusCode = 409;
      response.write(jsonEncode({'error': e.toString()}));
    } finally {
      await response.close();
    }
  }

  Map<String, dynamic> _read(String id) {
    if (readTerminal == null) {
      throw StateError('Targeted terminals unavailable');
    }
    return readTerminal!(id);
  }

  Future<void> close() async => _server?.close(force: true);
}

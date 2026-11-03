import 'dart:convert';
import 'dart:io';
import 'dart:math';

/// Loopback-only capability API. No credentials are written to disk.
class AgentServer {
  AgentServer({
    required this.read,
    required this.write,
    required this.interrupt,
  });
  final Map<String, dynamic> Function() read;
  final void Function(String) write;
  final void Function() interrupt;
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
      } else if (request.method == 'GET' && request.uri.path == '/terminal') {
        response.write(jsonEncode(read()));
      } else if (request.method == 'POST' && request.uri.path == '/input') {
        final bytes = <int>[];
        await for (final chunk in request.timeout(const Duration(seconds: 5))) {
          bytes.addAll(chunk);
          if (bytes.length > 65536) {
            throw const FormatException('Input exceeds 64 KiB');
          }
        }
        final body = jsonDecode(utf8.decode(bytes));
        if (body is! Map || body['text'] is! String) {
          throw const FormatException('Expected text string');
        }
        write(body['text'] as String);
        response.write('{"ok":true}');
      } else if (request.method == 'POST' && request.uri.path == '/interrupt') {
        interrupt();
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

  Future<void> close() async => _server?.close(force: true);
}

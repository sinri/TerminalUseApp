import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:terminal_use_app/src/agent_server.dart';

void main() {
  late AgentServer server;
  late HttpClient client;
  final inputs = <String>[];
  var interrupted = false;
  setUp(() async {
    inputs.clear();
    interrupted = false;
    server = AgentServer(
      read: () => {'text': 'hello', 'running': true},
      write: inputs.add,
      interrupt: () => interrupted = true,
    );
    await server.start();
    client = HttpClient();
  });
  tearDown(() async {
    client.close(force: true);
    await server.close();
  });
  Future<(int, dynamic)> send(
    String method,
    String path, {
    Object? body,
    bool auth = true,
  }) async {
    final req = await client.openUrl(method, Uri.parse('${server.url}$path'));
    if (auth) req.headers.set('authorization', 'Bearer ${server.token}');
    if (body != null) req.add(utf8.encode(jsonEncode(body)));
    final res = await req.close();
    return (res.statusCode, jsonDecode(await utf8.decoder.bind(res).join()));
  }

  test('rejects unauthenticated reads and writes', () async {
    expect((await send('GET', '/terminal', auth: false)).$1, 401);
    expect(
      (await send('POST', '/input', body: {'text': 'bad'}, auth: false)).$1,
      401,
    );
    expect(inputs, isEmpty);
  });
  test('reads shared state and forwards exact interactive input', () async {
    expect((await send('GET', '/terminal')).$2['text'], 'hello');
    expect((await send('POST', '/input', body: {'text': 'echo 你好\r'})).$1, 200);
    expect(inputs.single, 'echo 你好\r');
    await send('POST', '/interrupt', body: {});
    expect(interrupted, isTrue);
  });
  test('rejects malformed and oversized requests without input', () async {
    expect((await send('POST', '/input', body: {'text': 3})).$1, 400);
    expect((await send('POST', '/input', body: {'text': 'a' * 66000})).$1, 400);
    expect((await send('GET', '/missing')).$1, 404);
    expect(inputs, isEmpty);
  });
}

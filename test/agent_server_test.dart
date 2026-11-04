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
      list: () => [
        {'id': 'a', 'name': 'first'},
        {'id': 'b', 'name': 'second'},
      ],
      readTerminal: (id) {
        if (!['a', 'b'].contains(id)) throw StateError('closed');
        return {'id': id, 'text': id};
      },
      writeTerminal: (id, text) => inputs.add('$id:$text'),
      interruptTerminal: (id) => inputs.add('$id:interrupt'),
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
  test(
    'explicit terminal IDs route independently and closed IDs never fall back',
    () async {
      expect((await send('GET', '/terminals')).$2['terminals'].length, 2);
      expect((await send('GET', '/terminal?terminal_id=b')).$2['text'], 'b');
      await send('POST', '/input?terminal_id=b', body: {'text': 'pwd\r'});
      await send('POST', '/interrupt?terminal_id=a', body: {});
      expect(inputs, ['b:pwd\r', 'a:interrupt']);
      expect(
        (await send(
          'POST',
          '/input?terminal_id=closed',
          body: {'text': 'bad'},
        )).$1,
        409,
      );
      expect(inputs.length, 2);
    },
  );
  test('rejects malformed and oversized requests without input', () async {
    expect((await send('POST', '/input', body: {'text': 3})).$1, 400);
    expect((await send('POST', '/input', body: {'text': 'a' * 66000})).$1, 400);
    expect((await send('GET', '/missing')).$1, 404);
    expect(inputs, isEmpty);
  });
}

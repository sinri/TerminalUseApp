import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:terminal_use_app/src/api_request.dart';
import 'package:terminal_use_app/src/model_request.dart';
import 'package:terminal_use_app/src/settings.dart';

void main() {
  test('405 retains risk request context and redacts credentials', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final client = HttpClient();
    addTearDown(() async {
      client.close(force: true);
      await server.close(force: true);
    });
    server.listen((request) async {
      expect(request.method, 'POST');
      expect(request.uri.path, '/v1/chat/completions');
      request.response.statusCode = 405;
      request.response.headers.set('allow', 'GET');
      request.response.headers.set('x-request-id', 'upstream-request-123');
      request.response.write('route rejected; Bearer secret-key; query-secret');
      await request.response.close();
    });
    final profile = LlmProfile(
      name: 'test service',
      endpoint:
          'http://127.0.0.1:${server.port}/v1/chat/completions?token=query-secret',
      model: 'test-model',
      apiKey: 'secret-key',
    );
    try {
      await modelRequest(client, profile, {
        'model': 'test-model',
        'messages': [
          {'content': 'PRIVATE_PROMPT'},
        ],
      }, stage: '终端风险评估');
      fail('Expected diagnostic failure');
    } on ApiRequestFailure catch (error) {
      expect(error.summary, contains('终端风险评估失败：HTTP 405'));
      for (final text in [
        'Trace ID:',
        'POST http://127.0.0.1:',
        '/v1/chat/completions',
        'allow: GET',
        'upstream-request-123',
        'test-model',
        'route rejected',
        '本次命令未写入终端',
      ]) {
        expect(error.details, contains(text));
      }
      for (final secret in ['secret-key', 'query-secret', 'PRIVATE_PROMPT']) {
        expect(error.toString(), isNot(contains(secret)));
      }
    }
  });

  test(
    'model discovery and malformed successful response are traceable',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      var status = 401;
      server.listen((request) async {
        expect(request.method, 'GET');
        expect(request.uri.path, '/v1/models');
        request.response.statusCode = status;
        request.response.write(
          status == 401 ? '{"error":"unauthorized"}' : 'not json',
        );
        await request.response.close();
      });
      final profile = LlmProfile(
        name: 'service',
        endpoint: 'http://127.0.0.1:${server.port}',
        model: 'm',
      );
      await expectLater(
        profile.discoverModels(),
        throwsA(
          isA<ApiRequestFailure>().having(
            (e) => e.details,
            'details',
            allOf(contains('加载模型'), contains('GET'), contains('unauthorized')),
          ),
        ),
      );
      status = 200;
      await expectLater(
        profile.discoverModels(),
        throwsA(
          isA<ApiRequestFailure>().having(
            (e) => e.details,
            'details',
            allOf(contains('FormatException'), contains('not json')),
          ),
        ),
      );
    },
  );
}

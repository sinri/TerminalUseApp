import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'agent_trace.dart';
import 'model_stream.dart';

class ApiRequestFailure implements Exception {
  ApiRequestFailure(this.summary, this.details);
  final String summary, details;
  @override
  String toString() => '$summary\n$details';
}

/// Diagnostics never include request bodies or authentication headers.
Future<Map<String, dynamic>> apiJsonRequest(
  HttpClient client,
  Uri uri, {
  required String method,
  required String stage,
  required String service,
  required String protocol,
  required String auth,
  required String apiKey,
  String? model,
  Map<String, dynamic>? body,
  Duration timeout = const Duration(seconds: 90),
  void Function(String kind, String text)? onDelta,
}) async {
  final started = DateTime.now().toUtc();
  final watch = Stopwatch()..start();
  final trace = 'api-${started.microsecondsSinceEpoch.toRadixString(16)}';
  HttpClientResponse? response;
  var responseText = '';
  String redact(String value) {
    if (apiKey.isNotEmpty) value = value.replaceAll(apiKey, '[REDACTED]');
    for (final item in uri.queryParameters.values) {
      if (item.isNotEmpty) value = value.replaceAll(item, '[REDACTED]');
    }
    return value.replaceAllMapped(
      RegExp(r'(Bearer\s+)[^\s"<>]+', caseSensitive: false),
      (m) => '${m[1]}[REDACTED]',
    );
  }

  String safeUri(Uri value) => value
      .replace(
        userInfo: '',
        query: value.hasQuery ? '[REDACTED]' : null,
      )
      .removeFragment()
      .toString();
  try {
    agentTrace(
      'http.request',
      {
        'stage': stage,
        'service': service,
        'protocol': protocol,
        'model': model,
        'method': method,
        'url': safeUri(uri),
        'headers': {
          'content-type': 'application/json',
          if (body?['stream'] == true) 'accept': 'text/event-stream',
          if (auth == 'bearer') 'authorization': '[REDACTED]',
          if (auth == 'api-key') 'x-api-key': '[REDACTED]',
          if (protocol == 'anthropic') 'anthropic-version': '2023-06-01',
        },
        'payload': body,
      },
      traceId: trace,
      secrets: [apiKey, ...uri.queryParameters.values],
    );
    final request = await client
        .openUrl(method, uri)
        .timeout(const Duration(seconds: 30));
    request.followRedirects = false;
    request.headers.contentType = ContentType.json;
    if (body?['stream'] == true) {
      request.headers.set('Accept', 'text/event-stream');
    }
    if (auth == 'bearer') {
      request.headers.set('Authorization', 'Bearer $apiKey');
    }
    if (auth == 'api-key') request.headers.set('x-api-key', apiKey);
    if (protocol == 'anthropic') {
      request.headers.set('anthropic-version', '2023-06-01');
    }
    if (body != null) request.write(jsonEncode(body));
    response = await request.close().timeout(timeout);
    agentTrace(
      'http.headers',
      {
        'stage': stage,
        'status': response.statusCode,
        'elapsedMs': watch.elapsedMilliseconds,
        'headers': {
          for (final name in [
            'content-type',
            'allow',
            'x-request-id',
            'request-id',
            'x-correlation-id',
            'traceparent',
            'cf-ray',
          ])
            if (response.headers[name] != null) name: response.headers[name],
        },
      },
      traceId: trace,
      secrets: [apiKey, ...uri.queryParameters.values],
    );
    if (response.statusCode == 200 &&
        response.headers.contentType?.mimeType == 'text/event-stream') {
      final assembly = ModelStream(protocol, onDelta: onDelta);
      final raw = StringBuffer();
      var count = 0, events = 0;
      final frames = SseFrames((event, data) {
        agentTrace(
          'http.sse',
          {
            'stage': stage,
            'sequence': ++events,
            'eventType': event,
            'elapsedMs': watch.elapsedMilliseconds,
            'data': redact(data),
          },
          traceId: trace,
          secrets: [apiKey, ...uri.queryParameters.values],
        );
        assembly.add(event, data);
      });
      try {
        final stream = response
            .timeout(timeout)
            .map((chunk) {
              count += chunk.length;
              if (count > 4 * 1024 * 1024) throw StateError('响应超过 4 MiB');
              return chunk;
            })
            .transform(utf8.decoder)
            .map((chunk) {
              raw.write(chunk);
              return chunk;
            })
            .transform(const LineSplitter());
        await for (final line in stream) {
          frames.line(line);
          if (assembly.done) break;
        }
        final result = assembly.finish();
        agentTrace(
          'http.response',
          {
            'stage': stage,
            'transport': 'sse',
            'status': response.statusCode,
            'elapsedMs': watch.elapsedMilliseconds,
            'bytes': count,
            'body': result,
          },
          traceId: trace,
          secrets: [apiKey, ...uri.queryParameters.values],
        );
        return result;
      } finally {
        responseText = raw.toString();
      }
    }
    final bytes = <int>[];
    await for (final chunk in response.timeout(timeout)) {
      bytes.addAll(chunk);
      if (bytes.length > 4 * 1024 * 1024) throw StateError('响应超过 4 MiB');
    }
    responseText = utf8.decode(bytes, allowMalformed: true);
    agentTrace(
      'http.response',
      {
        'stage': stage,
        'status': response.statusCode,
        'elapsedMs': watch.elapsedMilliseconds,
        'bytes': bytes.length,
        'body': redact(responseText),
      },
      traceId: trace,
      secrets: [apiKey, ...uri.queryParameters.values],
    );
    if (response.statusCode != 200) {
      throw HttpException('HTTP ${response.statusCode}');
    }
    return jsonDecode(responseText) as Map<String, dynamic>;
  } catch (error) {
    agentTrace(
      'http.error',
      {
        'stage': stage,
        'status': response?.statusCode,
        'elapsedMs': watch.elapsedMilliseconds,
        'error': redact('$error'),
      },
      traceId: trace,
      secrets: [apiKey, ...uri.queryParameters.values],
    );
    final status = response?.statusCode;
    final summary =
        '$stage失败：${status == null
            ? error.runtimeType
            : status == 200
            ? "响应无效（HTTP 200）"
            : "HTTP $status"}';
    final headers = response?.headers;
    final preview = redact(responseText);
    final details = [
      'Trace ID: $trace',
      '时间: ${started.toIso8601String()} · 耗时: ${watch.elapsedMilliseconds} ms',
      '阶段: $stage · 服务: $service · 协议: $protocol',
      if (model != null) '模型: $model',
      '请求: $method ${safeUri(uri)}',
      if (status != null) '响应: $status ${response?.reasonPhrase ?? ""}',
      for (final key in [
        'x-request-id',
        'request-id',
        'x-correlation-id',
        'traceparent',
        'cf-ray',
        'allow',
        'content-type',
      ])
        if (headers?[key] != null) '$key: ${headers![key]!.join(", ")}',
      if (status == 405) '排查: 当前路径不接受 $method。核对协议、完整请求路径和代理路由；参照 Allow 响应头。',
      if (stage == '终端风险评估') '本次命令未写入终端：独立风险评估请求失败。',
      if (status != null && status >= 300 && status < 400)
        '排查: 服务返回重定向；请配置最终 API 地址，本应用不会自动跟随重定向。',
      '错误: $error',
      if (preview.isNotEmpty)
        '响应正文（最多 8000 字符）:\n${preview.length > 8000 ? '${preview.substring(0, 8000)}\n[已截断]' : preview}',
    ].join('\n');
    throw ApiRequestFailure(redact(summary), redact(details));
  }
}

import 'dart:io';
import 'api_request.dart';
import 'settings.dart';
import 'agent_trace.dart';

class ModelOutputTruncated extends FormatException {
  ModelOutputTruncated(
    String stage,
    Object? model,
    Object? limit,
    Object? usage,
  ) : super(
        '$stage输出达到 token 上限（model=$model，max_tokens=$limit，usage=$usage），响应不完整；未采用部分结果。',
      );
}

Future<Map<String, dynamic>> modelRequest(
  HttpClient client,
  LlmProfile p,
  Map<String, dynamic> body, {
  String stage = 'Agent 推理',
  Duration timeout = const Duration(seconds: 90),
  void Function(String kind, String text)? onDelta,
}) async {
  final response = await apiJsonRequest(
    client,
    p.requestUri,
    method: 'POST',
    stage: stage,
    service: p.name,
    protocol: p.protocol,
    auth: p.auth,
    apiKey: p.apiKey,
    model: body['model'] as String?,
    body: {
      ...body,
      'stream': true,
      if (p.protocol == 'openai' && p.requestUri.host == 'api.deepseek.com')
        'stream_options': {'include_usage': true},
    },
    timeout: timeout,
    onDelta: onDelta,
  );
  final finish = p.protocol == 'anthropic'
      ? response['stop_reason']
      : (response['choices'] as List?)?.firstOrNull?['finish_reason'];
  if (finish == 'length' || finish == 'max_tokens') {
    agentTrace('model.truncated', {
      'stage': stage,
      'model': body['model'],
      'max_tokens': body['max_tokens'],
      'finish_reason': finish,
      'usage': response['usage'],
    });
    throw ModelOutputTruncated(
      stage,
      body['model'],
      body['max_tokens'],
      response['usage'],
    );
  }
  return response;
}

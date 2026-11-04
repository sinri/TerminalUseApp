import 'dart:convert';
import 'dart:io';
import 'settings.dart';

Future<Map<String, dynamic>> modelRequest(
  HttpClient client,
  LlmProfile p,
  Map<String, dynamic> body,
) async {
  final request = await client
      .postUrl(p.requestUri)
      .timeout(const Duration(seconds: 30));
  request.followRedirects = false;
  request.headers.contentType = ContentType.json;
  if (p.auth == 'bearer') {
    request.headers.set('Authorization', 'Bearer ${p.apiKey}');
  }
  if (p.auth == 'api-key') request.headers.set('x-api-key', p.apiKey);
  if (p.protocol == 'anthropic') {
    request.headers.set('anthropic-version', '2023-06-01');
  }
  request.write(jsonEncode(body));
  final response = await request.close().timeout(const Duration(seconds: 90));
  final bytes = <int>[];
  await for (final chunk in response.timeout(const Duration(seconds: 90))) {
    bytes.addAll(chunk);
    if (bytes.length > 4 * 1024 * 1024) throw StateError('模型响应超过 4 MiB');
  }
  if (response.statusCode != 200) {
    throw HttpException('模型请求失败：HTTP ${response.statusCode}');
  }
  return jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
}

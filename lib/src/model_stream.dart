import 'dart:convert';

/// Reassembles complete protocol messages; tool arguments remain inert until EOF
/// has been replaced by an explicit protocol completion event.
class ModelStream {
  ModelStream(this.protocol, {this.onDelta});
  final String protocol;
  final void Function(String kind, String text)? onDelta;
  final _text = StringBuffer(), _reasoning = StringBuffer();
  final _tools = <int, Map<String, dynamic>>{};
  final _blocks = <int, Map<String, dynamic>>{};
  final _arguments = <int, StringBuffer>{};
  final _openBlocks = <int>{};
  final _usage = <String, dynamic>{};
  Map<String, dynamic> _message = {};
  String? _finish;
  bool done = false;

  void add(String event, String data) {
    if (done) return;
    if (protocol != 'anthropic' && data.trim() == '[DONE]') {
      if (_finish == null) throw const FormatException('SSE 缺少 finish_reason');
      done = true;
      return;
    }
    final value = jsonDecode(data) as Map<String, dynamic>;
    if (event == 'error' ||
        value['error'] != null ||
        value['type'] == 'error') {
      throw FormatException('SSE 服务错误：${jsonEncode(value['error'] ?? value)}');
    }
    if (protocol == 'anthropic') {
      _anthropic(value);
    } else {
      _openai(value);
    }
  }

  void _openai(Map<String, dynamic> value) {
    if (value['usage'] is Map) {
      _usage.addAll(Map<String, dynamic>.from(value['usage']));
    }
    for (final choice in value['choices'] as List? ?? []) {
      if ((choice['index'] ?? 0) != 0) continue;
      if (choice['finish_reason'] != null) {
        _finish = choice['finish_reason'] as String;
      }
      final delta = choice['delta'] as Map? ?? {};
      if (delta['content'] is String) {
        _text.write(delta['content']);
        onDelta?.call('text', delta['content']);
      }
      if (delta['reasoning_content'] is String) {
        _reasoning.write(delta['reasoning_content']);
        onDelta?.call('reasoning', delta['reasoning_content']);
      }
      for (final part in delta['tool_calls'] as List? ?? []) {
        final index = part['index'] as int? ?? 0;
        final tool = _tools.putIfAbsent(
          index,
          () => {
            'type': 'function',
            'function': <String, dynamic>{'name': '', 'arguments': ''},
          },
        );
        if (part['id'] != null) tool['id'] = part['id'];
        final function = part['function'] as Map? ?? {};
        final target = tool['function'] as Map<String, dynamic>;
        for (final key in ['name', 'arguments']) {
          if (function[key] is String) {
            target[key] = '${target[key]}${function[key]}';
          }
        }
        onDelta?.call('tool', '');
      }
    }
  }

  void _anthropic(Map<String, dynamic> value) {
    switch (value['type']) {
      case 'message_start':
        _message = Map<String, dynamic>.from(value['message'] as Map);
        if (_message['usage'] is Map) {
          _usage.addAll(Map<String, dynamic>.from(_message['usage']));
        }
      case 'content_block_start':
        final index = value['index'] as int;
        _openBlocks.add(index);
        final block = _blocks[index] = Map<String, dynamic>.from(
          value['content_block'] as Map,
        );
        if (block['type'] == 'text' &&
            block['text'] is String &&
            (block['text'] as String).isNotEmpty) {
          onDelta?.call('text', block['text']);
        }
      case 'content_block_delta':
        final index = value['index'] as int;
        final block = _blocks[index];
        if (block == null) {
          throw const FormatException('SSE content block 顺序无效');
        }
        final delta = value['delta'] as Map;
        switch (delta['type']) {
          case 'text_delta':
            block['text'] = '${block['text'] ?? ''}${delta['text']}';
            onDelta?.call('text', delta['text']);
          case 'input_json_delta':
            (_arguments[index] ??= StringBuffer()).write(delta['partial_json']);
            onDelta?.call('tool', '');
          case 'thinking_delta':
            block['thinking'] =
                '${block['thinking'] ?? ''}${delta['thinking']}';
            onDelta?.call('reasoning', delta['thinking']);
          case 'signature_delta':
            block['signature'] =
                '${block['signature'] ?? ''}${delta['signature']}';
        }
      case 'content_block_stop':
        final index = value['index'] as int;
        _openBlocks.remove(index);
      case 'message_delta':
        final delta = value['delta'] as Map? ?? {};
        _message.addAll(Map<String, dynamic>.from(delta));
        if (value['usage'] is Map) {
          _usage.addAll(Map<String, dynamic>.from(value['usage']));
        }
      case 'message_stop':
        if (_message['stop_reason'] == null) {
          throw const FormatException('SSE 缺少 stop_reason');
        }
        done = true;
    }
  }

  Map<String, dynamic> finish() {
    if (!done) throw const FormatException('SSE 连接提前结束，未收到完成事件；未采用部分工具参数');
    if (protocol == 'anthropic') {
      if (_message['stop_reason'] != 'max_tokens') {
        if (_openBlocks.isNotEmpty) throw const FormatException('SSE 内容块未完整结束');
        for (final entry in _arguments.entries) {
          _blocks[entry.key]!['input'] = jsonDecode(entry.value.toString());
        }
      }
      return {
        ..._message,
        'content': [
          for (final index in _blocks.keys.toList()..sort()) _blocks[index],
        ],
        'usage': _usage,
      };
    }
    return {
      'choices': [
        {
          'index': 0,
          'finish_reason': _finish,
          'message': {
            'role': 'assistant',
            'content': _text.toString(),
            if (_reasoning.isNotEmpty)
              'reasoning_content': _reasoning.toString(),
            if (_tools.isNotEmpty)
              'tool_calls': [
                for (final index in _tools.keys.toList()..sort()) _tools[index],
              ],
          },
        },
      ],
      'usage': _usage,
    };
  }
}

/// UTF-8 decoding is performed by the caller before line framing. Network
/// packets need not align with SSE lines, JSON values or Unicode characters.
class SseFrames {
  SseFrames(this.onEvent);
  final void Function(String event, String data) onEvent;
  String _event = '';
  final _data = <String>[];
  void line(String line) {
    if (line.isEmpty) {
      if (_data.isNotEmpty) onEvent(_event, _data.join('\n'));
      _event = '';
      _data.clear();
      return;
    }
    if (line.startsWith(':')) return;
    final colon = line.indexOf(':');
    final field = colon < 0 ? line : line.substring(0, colon);
    var value = colon < 0 ? '' : line.substring(colon + 1);
    if (value.startsWith(' ')) value = value.substring(1);
    if (field == 'event') _event = value;
    if (field == 'data') _data.add(value);
  }
}

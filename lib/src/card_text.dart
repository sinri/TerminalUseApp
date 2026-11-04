import 'package:flutter/widgets.dart';

const cardFontFallback = [
  'TerminalSymbols',
  'PingFang SC',
  'Microsoft YaHei',
  'Noto Sans CJK SC',
  'Apple Color Emoji',
  'Segoe UI Emoji',
  'Noto Color Emoji',
];

String visibleControls(String text) => text.replaceAllMapped(
  RegExp(
    r'[\x00-\x08\x0b-\x1f\x7f-\x9f\u061c\u200e\u200f\u202a-\u202e\u2066-\u2069]',
  ),
  (m) => '\\u${m[0]!.codeUnitAt(0).toRadixString(16).padLeft(4, '0')}',
);

String displayInput(String text) => visibleControls(
  text
      .replaceAll('\r', '⟨回车⟩')
      .replaceAll('\n', '⟨换行⟩\n')
      .replaceAll('\t', '⟨Tab⟩'),
);

String toolResultText(String tool, Object result) {
  if (result is! Map) return '工具已返回';
  switch (tool) {
    case 'terminal_run':
      return '命令已提交，请读取终端确认执行结果。';
    case 'terminal_input':
      return '按键已发送';
    case 'terminal_interrupt':
      return '已发送 Ctrl+C';
    case 'terminal_read':
      final text = result['text'] as String;
      return text.isEmpty
          ? '终端暂无输出'
          : visibleControls(textTail(text, 2000, '…'));
    case 'terminal_list':
      final tabs = result['terminals'] as List;
      return tabs.isEmpty
          ? '没有打开的终端'
          : tabs
                .map(
                  (t) => visibleControls(
                    '${t["name"]}（${t["id"]}） · ${t["running"] == true ? "运行中" : "已退出"}',
                  ),
                )
                .join('\n');
    case 'skill_read':
      return visibleControls(
        '${result["name"]}\n${result["path"]}\n\n${textTail(result["content"] as String, 2000, "…")}',
      );
    default:
      return '工具已返回';
  }
}

String textTail(String text, int limit, String prefix) =>
    text.length <= limit ? text : '$prefix${text.characters.takeLast(limit)}';

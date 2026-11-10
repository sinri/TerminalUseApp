import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

const projectUrl = 'https://github.com/sinri/TerminalUseApp';

Future<String?> _appVersion() async {
  try {
    return await const MethodChannel(
      'terminal_use/lifecycle',
    ).invokeMethod<String>('appVersion');
  } on MissingPluginException {
    return null;
  } on PlatformException {
    return null;
  }
}

Future<void> showTerminalUseAbout(BuildContext context) => showDialog<void>(
  context: context,
  builder: (context) => AlertDialog(
    title: const Text('Terminal Use APP'),
    content: SizedBox(
      width: 440,
      child: SingleChildScrollView(
        child: SelectionArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('桌面多终端与运维 Agent 工作区'),
              FutureBuilder<String?>(
                future: _appVersion(),
                builder: (context, snapshot) => snapshot.data == null
                    ? const SizedBox.shrink()
                    : Text('版本：${snapshot.data}'),
              ),
              const SizedBox(height: 16),
              const Text('作者：sinri'),
              const Text('Copyright © 2026 sinri'),
              const SizedBox(height: 16),
              const Text('GitHub 开源项目'),
              const Text(projectUrl),
              const SizedBox(height: 16),
              const Text('许可证：GNU General Public License v3.0'),
              const SizedBox(height: 8),
              const Text('本软件按 GPL v3.0 提供，允许依照许可证使用、修改和再分发，不提供任何担保。'),
              const SizedBox(height: 8),
              const Text(
                '“许可证与第三方声明”包含本项目及 Flutter、依赖库和 Nerd Fonts Symbols 的完整许可文本。',
              ),
            ],
          ),
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () async {
          if (Theme.of(context).platform == TargetPlatform.macOS) {
            try {
              final opened = await const MethodChannel(
                'terminal_use/lifecycle',
              ).invokeMethod<bool>('openProject');
              if (opened == true) return;
            } on PlatformException {
              // Keep the project address available if the browser cannot open.
            } on MissingPluginException {
              // Other hosts can still copy the project address.
            }
          }
          await Clipboard.setData(const ClipboardData(text: projectUrl));
          if (context.mounted) {
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(const SnackBar(content: Text('已复制 GitHub 地址')));
          }
        },
        child: const Text('GitHub 项目'),
      ),
      TextButton(
        onPressed: () => showDialog<void>(
          context: context,
          builder: (dialogContext) => Dialog(
            clipBehavior: Clip.antiAlias,
            child: SizedBox(
              width: 760,
              height: 560,
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 8, 8),
                    child: Row(
                      children: [
                        const Expanded(child: Text('许可证与第三方声明')),
                        IconButton(
                          tooltip: '关闭许可证',
                          onPressed: () => Navigator.of(dialogContext).pop(),
                          icon: const Icon(Icons.close),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  Expanded(
                    child: Navigator(
                      onGenerateRoute: (_) => MaterialPageRoute<void>(
                        builder: (_) => const LicensePage(
                          applicationName: 'Terminal Use APP',
                          applicationLegalese:
                              'Copyright © 2026 sinri · GPL v3.0',
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        child: const Text('许可证与第三方声明'),
      ),
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('关闭'),
      ),
    ],
  ),
);

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

const projectUrl = 'https://github.com/sinri/TerminalUseApp';

Future<void> showTerminalUseAbout(BuildContext context) => showDialog<void>(
  context: context,
  builder: (context) => AlertDialog(
    title: const Text('Terminal Use APP'),
    content: const SizedBox(
      width: 440,
      child: SingleChildScrollView(
        child: SelectionArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('桌面多终端与运维 Agent 工作区'),
              SizedBox(height: 16),
              Text('作者：sinri'),
              Text('Copyright © 2026 sinri'),
              SizedBox(height: 16),
              Text('GitHub 开源项目'),
              Text(projectUrl),
              SizedBox(height: 16),
              Text('许可证：GNU General Public License v3.0'),
              SizedBox(height: 8),
              Text('本软件按 GPL v3.0 提供，允许依照许可证使用、修改和再分发，不提供任何担保。'),
              SizedBox(height: 8),
              Text(
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
        onPressed: () => showLicensePage(
          context: context,
          applicationName: 'Terminal Use APP',
          applicationLegalese: 'Copyright © 2026 sinri · GPL v3.0',
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

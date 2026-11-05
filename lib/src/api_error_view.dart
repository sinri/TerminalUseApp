import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'api_request.dart';
import 'mac_controls.dart';

class ApiErrorView extends StatelessWidget {
  const ApiErrorView(this.failure, {super.key});
  final ApiRequestFailure failure;
  @override
  Widget build(BuildContext context) => ExpansionTile(
    title: Text(
      failure.summary,
      style: TextStyle(
        fontSize: 13,
        color: Theme.of(context).colorScheme.error,
      ),
    ),
    subtitle: const Text(
      '展开查看请求路径、响应与 Trace ID',
      style: TextStyle(fontSize: 12),
    ),
    tilePadding: const EdgeInsets.symmetric(horizontal: 8),
    childrenPadding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
    children: [
      Align(
        alignment: Alignment.centerLeft,
        child: MacButton(
          label: '复制诊断详情',
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: failure.toString()));
            if (context.mounted) {
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(const SnackBar(content: Text('诊断详情已复制')));
            }
          },
        ),
      ),
      const SizedBox(height: 8),
      SelectableText(
        failure.details,
        style: const TextStyle(fontSize: 12, height: 1.5),
      ),
    ],
  );
}

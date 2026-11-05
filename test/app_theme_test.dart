import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:terminal_use_app/src/app_theme.dart';

void main() {
  testWidgets('buttons animate from default to compact and between themes', (
    tester,
  ) async {
    final theme = ValueNotifier<ThemeData>(
      ThemeData(brightness: Brightness.dark),
    );
    addTearDown(theme.dispose);
    await tester.pumpWidget(
      ValueListenableBuilder<ThemeData>(
        valueListenable: theme,
        builder: (context, value, child) => MaterialApp(
          theme: value,
          home: Scaffold(
            body: Column(
              children: [
                TextButton(onPressed: () {}, child: const Text('新建终端')),
                FilledButton(onPressed: () {}, child: const Text('发送')),
                OutlinedButton(onPressed: () {}, child: const Text('允许本次执行')),
              ],
            ),
          ),
        ),
      ),
    );
    for (final brightness in [
      Brightness.dark,
      Brightness.light,
      Brightness.dark,
    ]) {
      theme.value = desktopTheme(brightness);
      await tester.pump();
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 50));
        expect(tester.takeException(), isNull);
      }
    }
  });
}

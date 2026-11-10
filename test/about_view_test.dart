import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:terminal_use_app/src/about_view.dart';
import 'package:terminal_use_app/src/app_theme.dart';

void main() {
  for (final brightness in Brightness.values) {
    testWidgets('About information and licenses in $brightness', (
      tester,
    ) async {
      const channel = MethodChannel('terminal_use/lifecycle');
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        (call) async => call.method == 'appVersion' ? '1.2.3+42' : null,
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          null,
        ),
      );
      LicenseRegistry.reset();
      addTearDown(LicenseRegistry.reset);
      final projectLicense = await tester.runAsync(
        () => rootBundle.loadString('LICENSE'),
      );
      final fontLicense = await tester.runAsync(
        () => rootBundle.loadString('assets/fonts/NERD-FONTS-LICENSE.txt'),
      );
      LicenseRegistry.addLicense(() async* {
        yield LicenseEntryWithLineBreaks(['Terminal Use APP'], projectLicense!);
        yield LicenseEntryWithLineBreaks(['Nerd Fonts Symbols'], fontLicense!);
      });
      await tester.pumpWidget(
        MaterialApp(
          theme: desktopTheme(brightness),
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showTerminalUseAbout(context),
                child: const Text('About'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('About'));
      await tester.pumpAndSettle();
      expect(find.text('作者：sinri'), findsOneWidget);
      expect(find.text('版本：1.2.3+42'), findsOneWidget);
      expect(find.text(projectUrl), findsOneWidget);
      expect(find.text('许可证：GNU General Public License v3.0'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('许可证与第三方声明'));
      await tester.pumpAndSettle();
      expect(find.text('Nerd Fonts Symbols'), findsOneWidget);
      final dialogSize = tester.getSize(find.byType(Dialog).last);
      expect(dialogSize.width, lessThan(tester.view.physicalSize.width));
      await tester.tap(find.text('Nerd Fonts Symbols'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.tap(find.byTooltip('关闭许可证'));
      await tester.pumpAndSettle();
      expect(find.text('作者：sinri'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.text('作者：sinri'), findsNothing);
    });
  }
}

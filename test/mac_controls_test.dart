import 'dart:ui' show Tristate;
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:terminal_use_app/src/app_theme.dart';
import 'package:terminal_use_app/src/mac_controls.dart';
import 'package:terminal_use_app/src/settings.dart';
import 'package:terminal_use_app/src/settings_view.dart';

Widget host(Widget child, {Brightness brightness = Brightness.light}) =>
    MaterialApp(
      theme: desktopTheme(brightness),
      home: Scaffold(body: Center(child: child)),
    );

void main() {
  testWidgets(
    'desktop button supports keyboard activation and disabled state',
    (tester) async {
      var calls = 0;
      final focus = FocusNode();
      addTearDown(focus.dispose);
      await tester.pumpWidget(
        host(
          MacButton(label: '执行', focusNode: focus, onPressed: () => calls++),
        ),
      );
      focus.requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(calls, 1);
      await tester.pumpWidget(host(MacButton(label: '执行', onPressed: null)));
      await tester.tap(find.text('执行'));
      await tester.pump();
      expect(calls, 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('popup selection and Escape dismiss without accidental changes', (
    tester,
  ) async {
    String? selected;
    await tester.pumpWidget(
      host(
        MacPopup<String>(
          label: '模型',
          value: 'a',
          entries: const [MacMenuEntry('a', '模型 A'), MacMenuEntry('b', '模型 B')],
          onSelected: (v) => selected = v,
        ),
      ),
    );
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(tester.getCenter(find.text('模型')));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('模型 B'), findsNothing);
    await mouse.removePointer();
    await tester.tap(find.text('模型'));
    await tester.pumpAndSettle();
    expect(find.text('模型 B'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('模型 B'), findsNothing);
    expect(selected, isNull);
    await tester.tap(find.text('模型'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('模型 B'));
    await tester.pumpAndSettle();
    expect(selected, 'b');
    selected = null;
    await tester.tap(find.text('模型'));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(selected, isNotNull);
  });

  testWidgets(
    'split handles support keyboard resize and reset without dragging',
    (tester) async {
      var size = 180.0;
      await tester.pumpWidget(
        host(
          SizedBox(
            height: 300,
            child: MacSplitHandle(
              axis: Axis.horizontal,
              label: '侧栏',
              onDelta: (d) => size += d,
              onReset: () => size = 180,
            ),
          ),
        ),
      );
      await tester.tap(find.byType(MacSplitHandle));
      await tester.pump(const Duration(milliseconds: 350));
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      expect(size, 196);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      expect(size, 180);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.sendKeyEvent(LogicalKeyboardKey.home);
      expect(size, 180);
    },
  );

  testWidgets(
    'sidebar provides selected semantics and a context menu entry point',
    (tester) async {
      final semantics = tester.ensureSemantics();
      var selected = false;
      Offset? contextPosition;
      await tester.pumpWidget(
        host(
          SizedBox(
            width: 180,
            child: MacSidebarItem(
              label: '本地',
              selected: true,
              running: true,
              onSelect: () => selected = true,
              onClose: () {},
              onRename: () {},
              onContextMenu: (p) => contextPosition = p,
            ),
          ),
        ),
      );
      await tester.tap(find.text('本地'));
      await tester.pump();
      expect(selected, isTrue);
      expect(
        tester
            .getSemantics(find.byType(MacSidebarItem))
            .getSemanticsData()
            .flagsCollection
            .isSelected,
        Tristate.isTrue,
      );
      final mouse = await tester.createGesture(
        kind: PointerDeviceKind.mouse,
        buttons: kSecondaryMouseButton,
      );
      await mouse.addPointer(location: tester.getCenter(find.text('本地')));
      await mouse.down(tester.getCenter(find.text('本地')));
      await mouse.up();
      await tester.pump();
      expect(contextPosition, isNotNull);
      await mouse.removePointer();
      await tester.pump(const Duration(milliseconds: 350));
      semantics.dispose();
    },
  );

  testWidgets('toolbar popup lays out in a tight source-list header', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        SizedBox(
          width: 120,
          height: 36,
          child: Row(
            children: [
              const Expanded(child: Text('终端')),
              MacButton(onPressed: () {}, icon: Icons.add, toolbar: true),
              MacPopup<String>(
                label: '',
                toolbar: true,
                entries: const [MacMenuEntry('ssh', 'SSH')],
                onSelected: (_) {},
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'settings support larger text, reduced motion and keyboard cancellation',
    (tester) async {
      final settings = AppSettings();
      await tester.pumpWidget(
        MaterialApp(
          theme: desktopTheme(Brightness.dark),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.linear(1.4),
              disableAnimations: true,
            ),
            child: child!,
          ),
          home: SizedBox(
            width: 680,
            height: 560,
            child: SettingsView(
              settings: settings,
              ssh: true,
              connection: const {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('添加 SSH 入口'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      expect(find.textContaining('请填写名称'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 400));
      expect(settings.ssh, isEmpty);
      expect(find.text('添加 SSH 入口'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('compact controls tolerate theme transitions and long labels', (
    tester,
  ) async {
    for (final brightness in [
      Brightness.light,
      Brightness.dark,
      Brightness.light,
    ]) {
      await tester.pumpWidget(
        host(
          SizedBox(
            width: 248,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                MacButton(label: '发送', primary: true, onPressed: () {}),
                MacPopup<String>(
                  label: 'a-very-long-model-name-for-a-compact-desktop-panel',
                  expanded: true,
                  entries: const [MacMenuEntry('a', '模型 A')],
                  onSelected: (_) {},
                ),
              ],
            ),
          ),
          brightness: brightness,
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }
  });
}

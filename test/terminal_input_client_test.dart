import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xterm/xterm.dart';

void main() {
  testWidgets('terminal input client identifies its Flutter view', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: TerminalView(Terminal(), autofocus: true),
    ));
    await tester.pump();
    final calls = tester.testTextInput.log.where(
      (call) => call.method == 'TextInput.setClient',
    );
    expect(calls, isNotEmpty);
    final configuration = (calls.last.arguments as List)[1] as Map;
    expect(configuration['viewId'], tester.view.viewId);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}

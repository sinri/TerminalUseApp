import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:terminal_use_app/src/settings.dart';
import 'package:terminal_use_app/src/ssh_credentials.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'SSH credentials are separate from config and process environment',
    () async {
      if (!Platform.isMacOS) return;
      final calls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SshCredentials.channel, (call) async {
            calls.add(call);
            return call.method == 'read' ? 'sensitive-password' : null;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(SshCredentials.channel, null),
      );
      final profile = SshProfile(
        name: 'host',
        host: 'example.com',
        user: 'user',
        password: true,
      );
      await SshCredentials.save(profile, 'sensitive-password');
      expect(calls.single.arguments['password'], 'sensitive-password');
      final environment = await SshCredentials.environment(profile);
      expect(environment['SSH_ASKPASS_REQUIRE'], 'prefer');
      expect(environment.toString(), isNot(contains('sensitive-password')));
      expect(
        profile.toJson().toString(),
        isNot(contains('sensitive-password')),
      );
      expect(
        profile.arguments.toString(),
        isNot(contains('sensitive-password')),
      );
      final helper = File(environment['SSH_ASKPASS']!);
      expect(
        await helper.readAsString(),
        isNot(contains('sensitive-password')),
      );
      expect((await Process.run('/bin/sh', ['-n', helper.path])).exitCode, 0);
      await helper.parent.delete(recursive: true);
      expect(
        SshCredentials.account(profile),
        SshCredentials.account(
          SshProfile(name: 'renamed', host: 'example.com', user: 'user'),
        ),
      );
      expect(
        SshCredentials.account(profile),
        isNot(
          SshCredentials.account(
            SshProfile(name: 'host', host: 'different.com', user: 'user'),
          ),
        ),
      );
    },
  );
}

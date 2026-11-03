import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:terminal_use_app/src/agent_launcher.dart';

void main() {
  test('OpenCode V1 and V2 preserve unrelated inline settings and servers', () {
    for (final v2 in [false, true]) {
      final existing = {
        'remote': {'type': 'remote', 'url': 'https://example.com'},
      };
      final inherited = {
        'model': 'my/model',
        'mcp': v2
            ? {
                'servers': existing,
                'timeout': {'startup': 5000},
              }
            : existing,
      };
      final config = AgentLauncher.openCodeConfig(
        '/path with spaces/python3',
        '/tmp/quote"/bridge.py',
        v2: v2,
        inherited: inherited,
      );
      final mcp = config['mcp'] as Map;
      final servers = v2 ? mcp['servers'] as Map : mcp;
      expect(config['model'], 'my/model');
      expect(servers['remote'], existing['remote']);
      expect(servers['terminal_use']['command'], [
        '/path with spaces/python3',
        '/tmp/quote"/bridge.py',
        'mcp',
      ]);
      expect(
        servers['terminal_use']['environment']['TERMINAL_USE_TOKEN'],
        '{env:TERMINAL_USE_TOKEN}',
      );
      if (v2) {
        expect(mcp['timeout']['startup'], 5000);
        expect(servers['terminal_use']['disabled'], false);
        expect(servers['terminal_use'].containsKey('enabled'), false);
      }
      expect(existing.containsKey('terminal_use'), false);
    }
  });
  test(
    'Codex passes paths as TOML values without interpolating credentials',
    () {
      final args = AgentLauncher.codexConfig(
        '/path with spaces/python',
        '/tmp/back\\slash/"bridge.py',
      );
      expect(jsonDecode(args[1].split('=').last), '/path with spaces/python');
      expect(jsonDecode(args[3].substring(args[3].indexOf('=') + 1)), [
        '/tmp/back\\slash/"bridge.py',
        'mcp',
      ]);
      expect(args.join(' '), contains('env_vars='));
      expect(args.join(' '), isNot(contains('probe-secret')));
    },
  );
}

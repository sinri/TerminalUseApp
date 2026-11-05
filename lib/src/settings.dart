import 'dart:convert';
import 'dart:io';
import 'api_request.dart';

String expandHome(String path) => path.startsWith('~/')
    ? '${Platform.environment['HOME'] ?? '.'}/${path.substring(2)}'
    : path;

class SshProfile {
  SshProfile({
    required this.name,
    required this.host,
    this.user = '',
    this.port = 22,
    this.key = '~/.ssh/id_rsa',
    this.password = false,
  });
  final String name, host, user, key;
  final int port;
  final bool password;
  List<String> get arguments {
    if (host.isEmpty ||
        host.startsWith('-') ||
        host.contains(RegExp(r'\s')) ||
        port < 1 ||
        port > 65535 ||
        user.startsWith('-')) {
      throw const FormatException('SSH 主机、用户或端口无效');
    }
    return [
      '-o',
      'ServerAliveInterval=30',
      '-o',
      'ServerAliveCountMax=3',
      '-p',
      '$port',
      if (user.isNotEmpty) ...['-l', user],
      if (password) ...[
        '-o',
        'PubkeyAuthentication=no',
        '-o',
        'PreferredAuthentications=keyboard-interactive,password',
      ] else ...[
        '-i',
        expandHome(key.isEmpty ? '~/.ssh/id_rsa' : key),
      ],
      host,
    ];
  }

  Map<String, dynamic> toJson() => {
    'name': name,
    'host': host,
    'user': user,
    'port': port,
    'key': key,
    'password': password,
  };
  factory SshProfile.fromJson(Map<String, dynamic> j) => SshProfile(
    name: j['name'] as String,
    host: j['host'] as String,
    user: j['user'] as String? ?? '',
    port: j['port'] as int? ?? 22,
    key: j['key'] as String? ?? '~/.ssh/id_rsa',
    password: j['password'] == true,
  );
}

class LlmProfile {
  LlmProfile({
    required this.name,
    required this.endpoint,
    required this.model,
    this.additionalModels = const [],
    this.exactEndpoint = false,
    this.protocol = 'openai',
    this.auth = 'bearer',
    this.apiKey = '',
  });
  final String name, endpoint, model, protocol, auth, apiKey;
  final List<String> additionalModels;
  List<String> get modelIds =>
      {model, ...additionalModels}.where((id) => id.isNotEmpty).toList();
  final bool exactEndpoint;
  Uri _resolve({bool models = false}) {
    final uri = Uri.parse(endpoint);
    if (!['https', 'http'].contains(uri.scheme) ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty) {
      throw const FormatException('请填写 HTTP(S) 服务地址');
    }
    final path = uri.path.replaceFirst(RegExp(r'/+$'), '');
    final route = protocol == 'anthropic' ? '/messages' : '/chat/completions';
    if (!models && (exactEndpoint || path.endsWith(route))) return uri;
    final base = path.endsWith(route)
        ? path.substring(0, path.length - route.length)
        : path;
    final prefix = base.isEmpty && !exactEndpoint && !path.endsWith(route)
        ? '/v1'
        : base;
    return uri.replace(path: '$prefix${models ? "/models" : route}');
  }

  Uri get requestUri => _resolve();
  Future<List<String>> discoverModels() async {
    final uri = _resolve(models: true);
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 10);
    try {
      final json = await apiJsonRequest(
        client,
        uri,
        method: 'GET',
        stage: '加载模型',
        service: name,
        protocol: protocol,
        auth: auth,
        apiKey: apiKey,
        timeout: const Duration(seconds: 15),
      );
      final ids =
          (json['data'] as List)
              .whereType<Map>()
              .map((m) => m['id'])
              .whereType<String>()
              .where((id) => id.isNotEmpty)
              .toSet()
              .toList()
            ..sort();
      if (ids.isEmpty) throw const FormatException('未返回可用模型');
      return ids;
    } finally {
      client.close(force: true);
    }
  }

  Map<String, dynamic> toJson() => {
    'name': name,
    'endpoint': endpoint,
    'exactEndpoint': exactEndpoint,
    'model': model,
    'additionalModels': additionalModels,
    'protocol': protocol,
    'auth': auth,
    'apiKey': apiKey,
  };
  factory LlmProfile.fromJson(Map<String, dynamic> j) => LlmProfile(
    name: j['name'] as String,
    endpoint: j['endpoint'] as String,
    exactEndpoint: j['exactEndpoint'] as bool? ?? true,
    model: j['model'] as String,
    additionalModels: (j['additionalModels'] as List? ?? []).cast<String>(),
    protocol: j['protocol'] as String? ?? 'openai',
    auth: j['auth'] as String? ?? 'bearer',
    apiKey: j['apiKey'] as String? ?? '',
  );
}

enum CommandRisk {
  low('低', '只读查询，例如查看当前路径、磁盘使用量。'),
  medium('中', '普通写操作，或执行内容明确且不含高风险操作的脚本或命令。'),
  high('高', '删除文件、启动或停止服务、运行不明脚本，以及涉及敏感数据、提权或影响不明的操作。');

  const CommandRisk(this.label, this.description);
  final String label, description;
}

class AppSettings {
  final autoAllow = <CommandRisk>{};
  final ssh = <SshProfile>[];
  final models = <LlmProfile>[];
  String skillRoot = '';
  Future<void> _saveQueue = Future<void>.value();
  static File get defaultFile {
    final base = Platform.isWindows
        ? Platform.environment['APPDATA']
        : Platform.environment['HOME'];
    return File(
      '${base ?? Directory.current.path}/.terminal-use/settings.json',
    );
  }

  Future<void> load({File? file}) async {
    final source = file ?? defaultFile;
    if (!await source.exists()) return;
    final j = jsonDecode(await source.readAsString()) as Map<String, dynamic>;
    final loadedSsh = (j['ssh'] as List? ?? [])
        .map((v) => SshProfile.fromJson(Map<String, dynamic>.from(v as Map)))
        .toList();
    final loadedModels = (j['models'] as List? ?? [])
        .map((v) => LlmProfile.fromJson(Map<String, dynamic>.from(v as Map)))
        .toList();
    ssh
      ..clear()
      ..addAll(loadedSsh);
    models
      ..clear()
      ..addAll(loadedModels);
    autoAllow
      ..clear()
      ..addAll(
        CommandRisk.values.where(
          (risk) =>
              j['autoAllow'] is List &&
              (j['autoAllow'] as List).contains(risk.name),
        ),
      );
    skillRoot = j['skillRoot'] as String? ?? '';
  }

  Future<void> save({File? file}) {
    final target = file ?? defaultFile;
    final content = jsonEncode({
      'ssh': ssh.map((v) => v.toJson()).toList(),
      'models': models.map((v) => v.toJson()).toList(),
      'skillRoot': skillRoot,
      'autoAllow': autoAllow.map((risk) => risk.name).toList(),
    });
    final saved = _saveQueue.then((_) => _write(target, content));
    _saveQueue = saved.then((_) {}, onError: (Object error) {});
    return saved;
  }

  Future<void> _write(File target, String content) async {
    await target.parent.create(recursive: true);
    if (!Platform.isWindows) {
      final result = await Process.run('chmod', ['700', target.parent.path]);
      if (result.exitCode != 0) throw const FileSystemException('无法保护配置目录');
    }
    final temporary = File('${target.path}.tmp');
    await temporary.writeAsString(content, flush: true);
    if (!Platform.isWindows) {
      final result = await Process.run('chmod', ['600', temporary.path]);
      if (result.exitCode != 0) throw const FileSystemException('无法保护配置文件');
    }
    await temporary.rename(target.path);
  }
}

typedef ModelChoice = (LlmProfile, String);

import 'package:flutter/material.dart';
import 'settings.dart';
import 'package:flutter/services.dart';

class SettingsView extends StatefulWidget {
  const SettingsView({
    super.key,
    required this.settings,
    required this.ssh,
    required this.connection,
  });
  final bool ssh;
  final Map<String, String> connection;
  final AppSettings settings;
  @override
  State<SettingsView> createState() => _SettingsViewState();
}

class _SettingsViewState extends State<SettingsView> {
  late final root = TextEditingController(text: widget.settings.skillRoot);
  String? error;
  Future<void> _save() async {
    try {
      await widget.settings.save();
      if (mounted) setState(() => error = null);
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    }
  }

  Future<void> _edit({
    SshProfile? ssh,
    LlmProfile? llm,
    required bool isSsh,
  }) async {
    final labels = isSsh
        ? ['名称', '主机', '用户名', '端口', '密钥路径']
        : ['名称', 'API Endpoint', '可用模型（每行一个 ID）', 'API Key'];
    final values = isSsh
        ? [
            ssh?.name ?? '',
            ssh?.host ?? '',
            ssh?.user ?? '',
            '${ssh?.port ?? 22}',
            ssh?.key ?? '~/.ssh/id_rsa',
          ]
        : [
            llm?.name ?? '',
            llm?.endpoint ?? '',
            llm?.modelIds.join('\n') ?? '',
            llm?.apiKey ?? '',
          ];
    final controllers = values
        .map((v) => TextEditingController(text: v))
        .toList();
    var password = ssh?.password ?? false;
    var protocol = llm?.protocol ?? 'openai';
    var auth = llm?.auth ?? 'bearer';
    String? validation;
    List<String> modelIds() => controllers[2].text
        .split('\n')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toSet()
        .toList();
    var loadingModels = false;
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: Text(isSsh ? 'SSH 入口' : '模型配置'),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var i = 0; i < labels.length; i++)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: TextField(
                        controller: controllers[i],
                        maxLines: !isSsh && i == 2 ? 5 : 1,
                        minLines: 1,
                        enabled: !loadingModels,
                        obscureText: !isSsh && i == 3,
                        decoration: InputDecoration(
                          labelText: labels[i],
                          hintText: !isSsh && i == 1
                              ? 'https://host 或 https://host/v1'
                              : null,
                        ),
                      ),
                    ),
                  if (isSsh)
                    SwitchListTile(
                      title: const Text('密码登录（在终端输入，不保存密码）'),
                      value: password,
                      onChanged: (v) => update(() => password = v),
                    )
                  else ...[
                    TextButton(
                      onPressed: loadingModels
                          ? null
                          : () async {
                              update(() {
                                loadingModels = true;
                                validation = null;
                              });
                              try {
                                final found = await LlmProfile(
                                  name: '',
                                  endpoint: controllers[1].text.trim(),
                                  exactEndpoint:
                                      llm?.exactEndpoint == true &&
                                      llm?.endpoint ==
                                          controllers[1].text.trim(),
                                  model: '',
                                  protocol: protocol,
                                  auth: auth,
                                  apiKey: controllers[3].text,
                                ).discoverModels();
                                if (context.mounted) {
                                  controllers[2].text = found.join('\n');
                                }
                              } catch (e) {
                                if (context.mounted) {
                                  update(() => validation = '$e');
                                }
                              } finally {
                                if (context.mounted) {
                                  update(() => loadingModels = false);
                                }
                              }
                            },
                      child: Text(loadingModels ? '正在加载…' : '从 API 加载模型'),
                    ),
                    DropdownButtonFormField<String>(
                      initialValue: protocol,
                      decoration: const InputDecoration(labelText: '协议'),
                      items: const [
                        DropdownMenuItem(
                          value: 'openai',
                          child: Text('OpenAI-compatible Chat Completions'),
                        ),
                        DropdownMenuItem(
                          value: 'anthropic',
                          child: Text('Anthropic Messages'),
                        ),
                      ],
                      onChanged: loadingModels
                          ? null
                          : (v) => update(() => protocol = v!),
                    ),
                    DropdownButtonFormField<String>(
                      initialValue: auth,
                      decoration: const InputDecoration(labelText: '认证'),
                      items: const [
                        DropdownMenuItem(
                          value: 'bearer',
                          child: Text('Bearer Token'),
                        ),
                        DropdownMenuItem(
                          value: 'api-key',
                          child: Text('x-api-key'),
                        ),
                        DropdownMenuItem(value: 'none', child: Text('无认证')),
                      ],
                      onChanged: loadingModels
                          ? null
                          : (v) => update(() => auth = v!),
                    ),
                  ],
                  if (validation != null)
                    Text(
                      validation!,
                      style: const TextStyle(color: Colors.orange),
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: loadingModels
                  ? null
                  : () {
                      try {
                        if (controllers[0].text.trim().isEmpty) {
                          throw const FormatException('请填写名称');
                        }
                        if (isSsh) {
                          SshProfile(
                            name: controllers[0].text,
                            host: controllers[1].text.trim(),
                            user: controllers[2].text.trim(),
                            port: int.parse(controllers[3].text),
                            key: controllers[4].text,
                          ).arguments;
                        } else {
                          final uri = Uri.parse(controllers[1].text.trim());
                          if (!['http', 'https'].contains(uri.scheme) ||
                              uri.host.isEmpty ||
                              uri.userInfo.isNotEmpty ||
                              modelIds().isEmpty) {
                            throw const FormatException(
                              '请填写有效 Endpoint，并加载或填写模型列表',
                            );
                          }
                        }
                        Navigator.pop(context, true);
                      } catch (e) {
                        update(() => validation = '$e');
                      }
                    },
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );
    if (accepted == true) {
      final s = widget.settings;
      if (isSsh) {
        final profile = SshProfile(
          name: controllers[0].text.trim(),
          host: controllers[1].text.trim(),
          user: controllers[2].text.trim(),
          port: int.parse(controllers[3].text),
          key: controllers[4].text.trim(),
          password: password,
        );
        if (ssh == null) {
          s.ssh.add(profile);
        } else {
          s.ssh[s.ssh.indexOf(ssh)] = profile;
        }
      } else {
        final profile = LlmProfile(
          name: controllers[0].text.trim(),
          endpoint: controllers[1].text.trim(),
          exactEndpoint:
              llm?.exactEndpoint == true &&
              llm?.endpoint == controllers[1].text.trim(),
          model: modelIds().first,
          additionalModels: modelIds().skip(1).toList(),
          apiKey: controllers[3].text,
          protocol: protocol,
          auth: auth,
        );
        if (llm == null) {
          s.models.add(profile);
        } else {
          s.models[s.models.indexOf(llm)] = profile;
        }
      }
      await _save();
      if (mounted) setState(() {});
    }
    // Dialog route animations may still reference the controllers for this frame.
    await Future<void>.delayed(const Duration(milliseconds: 300));
    for (final c in controllers) {
      c.dispose();
    }
  }

  @override
  void dispose() {
    root.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.ssh ? 'SSH 设置' : 'Agent 设置')),
    body: ListView(
      padding: const EdgeInsets.all(24),
      children: [
        if (error != null)
          Text(error!, style: const TextStyle(color: Colors.orange)),
        if (widget.ssh) ...[
          const Text('SSH 入口', style: TextStyle(fontSize: 20)),
          for (final p in widget.settings.ssh.toList())
            ListTile(
              title: Text(p.name),
              subtitle: Text('${p.user}@${p.host}:${p.port}'),
              onTap: () => _edit(ssh: p, isSsh: true),
              trailing: IconButton(
                tooltip: '删除入口',
                icon: const Icon(Icons.delete_outline),
                onPressed: () async {
                  widget.settings.ssh.remove(p);
                  await _save();
                  if (mounted) setState(() {});
                },
              ),
            ),
          TextButton.icon(
            onPressed: () => _edit(isSsh: true),
            icon: const Icon(Icons.add),
            label: const Text('添加 SSH 入口'),
          ),
        ] else ...[
          const Text('LLM 配置', style: TextStyle(fontSize: 20)),
          const Text(
            'Endpoint 可填服务地址、API 基础路径或标准完整请求地址。API Key 保存在仅当前用户可访问的本地配置文件中。',
          ),
          for (final p in widget.settings.models.toList())
            ListTile(
              title: Text(p.name),
              subtitle: Text('${p.protocol} · ${p.modelIds.length} 个模型'),
              onTap: () => _edit(llm: p, isSsh: false),
              trailing: IconButton(
                tooltip: '删除模型',
                icon: const Icon(Icons.delete_outline),
                onPressed: () async {
                  widget.settings.models.remove(p);
                  await _save();
                  if (mounted) setState(() {});
                },
              ),
            ),
          TextButton.icon(
            onPressed: () => _edit(isSsh: false),
            icon: const Icon(Icons.add),
            label: const Text('添加 LLM 配置'),
          ),
          const Divider(),
          const Text('命令自动放行', style: TextStyle(fontSize: 20)),
          const Text('适用于内置 Agent 和外部 MCP。开启后，该等级的操作通过风险评估即执行；关闭时逐次确认。'),
          for (final risk in CommandRisk.values)
            SwitchListTile(
              title: Text('${risk.label}风险自动放行'),
              subtitle: Text(risk.description),
              value: widget.settings.autoAllow.contains(risk),
              onChanged: (enabled) async {
                setState(() {
                  if (enabled) {
                    widget.settings.autoAllow.add(risk);
                  } else {
                    widget.settings.autoAllow.remove(risk);
                  }
                });
                await _save();
              },
            ),
          const Divider(),
          const Text('Skills', style: TextStyle(fontSize: 20)),
          TextField(
            controller: root,
            decoration: const InputDecoration(
              labelText: 'Skills 根目录',
              helperText: '递归发现 SKILL.md，支持 ~/ 路径；留空禁用',
            ),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton(
              onPressed: () async {
                widget.settings.skillRoot = root.text.trim();
                await _save();
              },
              child: const Text('保存 Skills 目录'),
            ),
          ),
          if (widget.connection.isNotEmpty)
            TextButton(
              onPressed: () => Clipboard.setData(
                ClipboardData(
                  text: widget.connection.entries
                      .map((e) => '${e.key}=${e.value}')
                      .join('\n'),
                ),
              ),
              child: const Text('复制 Terminal MCP 连接参数'),
            ),
        ],
        const SizedBox(height: 24),
        SelectableText('配置位置：${AppSettings.defaultFile.path}'),
      ],
    ),
  );
}

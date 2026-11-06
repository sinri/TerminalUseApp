import 'dart:convert';
import 'dart:io';
import 'ssh_credentials.dart';
import 'api_request.dart';
import 'api_error_view.dart';

import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'mac_controls.dart';
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
  String? notice;
  late bool ssh = widget.ssh;
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
        ? ['名称', '主机', '用户名', '端口', '密钥路径', if (Platform.isMacOS) '保存的密码（可选）']
        : ['名称', 'API Endpoint', '可用模型（每行一个 ID）', 'API Key'];
    var savedPassword = '';
    if (isSsh && ssh != null && Platform.isMacOS) {
      try {
        savedPassword = await SshCredentials.read(ssh);
      } catch (e) {
        if (mounted) setState(() => error = '$e');
        return;
      }
      if (!mounted) return;
    }
    final values = isSsh
        ? [
            ssh?.name ?? '',
            ssh?.host ?? '',
            ssh?.user ?? '',
            '${ssh?.port ?? 22}',
            ssh?.key ?? '~/.ssh/id_rsa',
            if (Platform.isMacOS) savedPassword,
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
    var showSshPassword = false;
    var protocol = llm?.protocol ?? 'openai';
    var auth = llm?.auth ?? 'bearer';
    String? validation;
    ApiRequestFailure? apiFailure;
    List<String> modelIds() => controllers[2].text
        .split('\n')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toSet()
        .toList();
    var loadingModels = false;
    final errorAnchor = GlobalKey();
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, update) {
          void reportValidation(Object error) {
            update(() {
              apiFailure = error is ApiRequestFailure ? error : null;
              validation = error is ApiRequestFailure
                  ? error.summary
                  : '$error';
            });
            WidgetsBinding.instance.addPostFrameCallback((_) {
              final target = errorAnchor.currentContext;
              if (target != null) {
                Scrollable.ensureVisible(
                  target,
                  alignment: .8,
                  duration: Duration.zero,
                );
              }
            });
          }

          Future<void> accept() async {
            if (loadingModels) return;

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
                  throw const FormatException('请填写有效 Endpoint，并加载或填写模型列表');
                }
              }
              if (isSsh && Platform.isMacOS) {
                update(() => loadingModels = true);
                try {
                  await SshCredentials.save(
                    SshProfile(
                      name: controllers[0].text.trim(),
                      host: controllers[1].text.trim(),
                      user: controllers[2].text.trim(),
                      port: int.parse(controllers[3].text),
                    ),
                    password ? controllers[5].text : '',
                  );
                } finally {
                  if (context.mounted) update(() => loadingModels = false);
                }
              }
              if (context.mounted) Navigator.pop(context, true);
            } catch (e) {
              reportValidation(e);
            }
          }

          return CallbackShortcuts(
            bindings: {
              const SingleActivator(LogicalKeyboardKey.enter, meta: true):
                  accept,
            },
            child: AlertDialog(
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
                            style: Theme.of(context).textTheme.bodyMedium!
                                .copyWith(fontSize: 13, height: 1.4),
                            textAlignVertical: TextAlignVertical.top,
                            autofocus: i == 0,
                            onSubmitted: !isSsh && i == 2
                                ? null
                                : (_) => accept(),
                            maxLines: !isSsh && i == 2 ? 5 : 1,
                            minLines: !isSsh && i == 2 ? 3 : 1,
                            enabled: !loadingModels,
                            obscureText:
                                (!isSsh && i == 3) ||
                                (isSsh && i == 5 && !showSshPassword),
                            enableSuggestions: !(isSsh && i == 5),
                            autocorrect: !(isSsh && i == 5),
                            decoration: InputDecoration(
                              labelText: labels[i],
                              suffixIcon: isSsh && i == 5
                                  ? IconButton(
                                      tooltip: showSshPassword
                                          ? '隐藏密码'
                                          : '显示密码',
                                      onPressed: () => update(
                                        () =>
                                            showSshPassword = !showSshPassword,
                                      ),
                                      icon: Icon(
                                        showSshPassword
                                            ? Icons.visibility_off
                                            : Icons.visibility,
                                      ),
                                    )
                                  : null,
                              helperText: isSsh && i == 5
                                  ? '存入系统钥匙串；清空后保存可移除密码。'
                                  : null,
                              labelStyle: Theme.of(context).textTheme.bodySmall,
                              floatingLabelStyle: Theme.of(context)
                                  .textTheme
                                  .bodySmall!
                                  .copyWith(
                                    // Floating labels are rendered at 75%.
                                    fontSize: 16,
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurfaceVariant,
                                  ),
                              hintStyle: Theme.of(context).textTheme.bodyMedium!
                                  .copyWith(
                                    fontSize: 13,
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurfaceVariant,
                                  ),
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 10,
                              ),
                              hintText: !isSsh && i == 1
                                  ? 'https://host 或 https://host/v1'
                                  : null,
                            ),
                          ),
                        ),
                      if (isSsh)
                        Row(
                          children: [
                            const Expanded(child: Text('密码登录')),
                            CupertinoSwitch(
                              value: password,
                              onChanged: (v) => update(() => password = v),
                            ),
                          ],
                        )
                      else ...[
                        MacButton(
                          onPressed: loadingModels
                              ? null
                              : () async {
                                  update(() {
                                    loadingModels = true;
                                    validation = null;
                                    apiFailure = null;
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
                                      reportValidation(e);
                                    }
                                  } finally {
                                    if (context.mounted) {
                                      update(() => loadingModels = false);
                                    }
                                  }
                                },
                          label: loadingModels ? '正在加载…' : '从 API 加载模型',
                        ),
                        const SizedBox(height: 8),
                        const Align(
                          alignment: Alignment.centerLeft,
                          child: Text('协议'),
                        ),
                        const SizedBox(height: 4),
                        MacPopup<String>(
                          label: protocol == 'openai'
                              ? 'OpenAI-compatible Chat Completions'
                              : 'Anthropic Messages',
                          value: protocol,
                          expanded: true,
                          entries: const [
                            MacMenuEntry(
                              'openai',
                              'OpenAI-compatible Chat Completions',
                            ),
                            MacMenuEntry('anthropic', 'Anthropic Messages'),
                          ],
                          onSelected: loadingModels
                              ? null
                              : (v) => update(() => protocol = v),
                        ),
                        const SizedBox(height: 12),
                        const Align(
                          alignment: Alignment.centerLeft,
                          child: Text('认证'),
                        ),
                        const SizedBox(height: 4),
                        MacPopup<String>(
                          label: {
                            'bearer': 'Bearer Token',
                            'api-key': 'x-api-key',
                            'none': '无认证',
                          }[auth]!,
                          value: auth,
                          expanded: true,
                          entries: const [
                            MacMenuEntry('bearer', 'Bearer Token'),
                            MacMenuEntry('api-key', 'x-api-key'),
                            MacMenuEntry('none', '无认证'),
                          ],
                          onSelected: loadingModels
                              ? null
                              : (v) => update(() => auth = v),
                        ),
                      ],
                      if (apiFailure != null)
                        ApiErrorView(apiFailure!, key: errorAnchor)
                      else if (validation != null)
                        SelectableText(
                          validation!,
                          key: errorAnchor,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              actions: [
                MacButton(
                  onPressed: () => Navigator.pop(context, false),
                  label: '取消',
                ),
                MacButton(
                  primary: true,
                  onPressed: loadingModels ? null : accept,
                  label: '保存',
                ),
              ],
            ),
          );
        },
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

  Widget _profileRow(
    String title,
    String subtitle,
    VoidCallback edit,
    VoidCallback remove,
  ) => ListTile(
    contentPadding: EdgeInsets.zero,
    title: Text(title, style: const TextStyle(fontSize: 13)),
    subtitle: Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
    onTap: edit,
    trailing: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        MacButton(
          onPressed: edit,
          icon: CupertinoIcons.pencil,
          toolbar: true,
          tooltip: '编辑 $title',
        ),
        MacButton(
          onPressed: remove,
          icon: CupertinoIcons.trash,
          toolbar: true,
          tooltip: '删除 $title',
        ),
      ],
    ),
  );

  Future<void> _remove(String name, VoidCallback remove) async {
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除配置？'),
        content: Text('将删除「$name」的本地配置。'),
        actions: [
          MacButton(
            onPressed: () => Navigator.pop(context, false),
            label: '取消',
          ),
          MacButton(
            onPressed: () => Navigator.pop(context, true),
            label: '删除',
            destructive: true,
          ),
        ],
      ),
    );
    if (accepted == true && mounted) {
      remove();
      await _save();
      if (mounted) setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) => CallbackShortcuts(
    bindings: {
      const SingleActivator(LogicalKeyboardKey.escape): () =>
          Navigator.of(context).maybePop(),
      const SingleActivator(LogicalKeyboardKey.keyW, meta: true): () =>
          Navigator.of(context).maybePop(),
    },
    child: Focus(
      autofocus: true,
      child: Scaffold(
        appBar: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: Theme.of(context).colorScheme.outlineVariant,
                ),
              ),
            ),
            child: SizedBox(
              height: 48,
              child: Row(
                children: [
                  const Text(
                    '设置',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                  const Spacer(),
                  CupertinoSlidingSegmentedControl<bool>(
                    groupValue: ssh,
                    children: const {
                      false: Padding(
                        padding: EdgeInsets.symmetric(horizontal: 18),
                        child: Text('Agent', style: TextStyle(fontSize: 12)),
                      ),
                      true: Padding(
                        padding: EdgeInsets.symmetric(horizontal: 18),
                        child: Text('SSH', style: TextStyle(fontSize: 12)),
                      ),
                    },
                    onValueChanged: (v) {
                      if (v != null) setState(() => ssh = v);
                    },
                  ),
                  const Spacer(),
                  MacButton(
                    onPressed: () => Navigator.pop(context),
                    icon: CupertinoIcons.xmark,
                    toolbar: true,
                    tooltip: '关闭设置',
                  ),
                ],
              ),
            ),
          ),
        ),
        body: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            if (error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            if (notice != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(notice!),
              ),
            if (ssh)
              MacSection(
                title: 'SSH 入口',
                trailing: MacButton(
                  onPressed: () => _edit(isSsh: true),
                  icon: CupertinoIcons.plus,
                  label: '添加 SSH 入口',
                ),
                description: '使用系统 OpenSSH 连接；macOS 支持将密码保存到系统钥匙串。',
                children: [
                  if (widget.settings.ssh.isEmpty)
                    const Padding(
                      padding: EdgeInsets.only(bottom: 12),
                      child: Text('还没有 SSH 入口。添加后可从侧栏菜单连接。'),
                    ),
                  for (final p in widget.settings.ssh.toList())
                    _profileRow(
                      p.name,
                      '${p.user}@${p.host}:${p.port}',
                      () => _edit(ssh: p, isSsh: true),
                      () =>
                          _remove(p.name, () => widget.settings.ssh.remove(p)),
                    ),
                ],
              )
            else ...[
              MacSection(
                title: '模型服务',
                trailing: MacButton(
                  onPressed: () => _edit(isSsh: false),
                  icon: CupertinoIcons.plus,
                  label: '添加 LLM 配置',
                ),
                description:
                    'Endpoint 支持服务地址、API 基础路径或标准完整请求地址。API Key 保存在仅当前用户可访问的本地配置文件中。',
                children: [
                  if (widget.settings.models.isEmpty)
                    const Padding(
                      padding: EdgeInsets.only(bottom: 12),
                      child: Text('添加模型服务，开始使用 Agent。'),
                    ),
                  for (final p in widget.settings.models.toList())
                    _profileRow(
                      p.name,
                      '${p.protocol} · ${p.modelIds.length} 个模型',
                      () => _edit(llm: p, isSsh: false),
                      () => _remove(
                        p.name,
                        () => widget.settings.models.remove(p),
                      ),
                    ),
                ],
              ),
              MacSection(
                title: '命令自动放行',
                description: '适用于内置 Agent 和外部 MCP。关闭时，每次操作均需确认。',
                children: [
                  for (final risk in CommandRisk.values)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('${risk.label}风险自动放行'),
                                const SizedBox(height: 2),
                                Text(
                                  risk.description,
                                  style: Theme.of(context).textTheme.bodySmall!
                                      .copyWith(
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.onSurfaceVariant,
                                      ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          Semantics(
                            label: '${risk.label}风险自动放行',
                            child: CupertinoSwitch(
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
                          ),
                        ],
                      ),
                    ),
                ],
              ),
              MacSection(
                title: 'Skills',
                children: [
                  TextField(
                    controller: root,
                    decoration: const InputDecoration(
                      labelText: 'Skills 根目录',
                      hintText: '~/…',
                      helperText: '递归发现 SKILL.md；留空禁用',
                    ),
                  ),
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: MacButton(
                      onPressed: () async {
                        widget.settings.skillRoot = root.text.trim();
                        await _save();
                        if (mounted && error == null) {
                          setState(() => notice = 'Skills 目录已保存');
                        }
                      },
                      label: '保存 Skills 目录',
                    ),
                  ),
                ],
              ),
              if (widget.connection.isNotEmpty)
                MacSection(
                  title: 'Terminal MCP',
                  description: '应用重启后需重新复制连接参数，并重启客户端的 MCP 服务。',
                  children: [
                    const Text(
                      '让支持本地 stdio MCP 的外部 Agent 操作这里的终端。内置 Agent 无需额外集成。',
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      '1. 保持本应用运行，并新建一个终端。\n'
                      '2. 在 MCP 客户端添加本地 stdio 服务：命令为 python3，参数为本项目 tools/terminal_bridge.py 的绝对路径和 mcp。需要本机已安装 Python 3，无需额外 Python 包。\n'
                      '3. 将下方复制的 TERMINAL_USE_URL 与 TERMINAL_USE_TOKEN 填入该服务的环境变量，启动或重新加载服务。此 URL 是桥接脚本使用的地址，不是客户端的远程 MCP 地址。\n'
                      '4. 让 Agent 先调用 terminal_list 选择终端 ID，再用 terminal_read 读取内容；执行命令用 terminal_run，随后再次读取结果。',
                      style: TextStyle(fontSize: 12, height: 1.6),
                    ),
                    const SizedBox(height: 12),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: MacButton(
                        onPressed: () async {
                          await Clipboard.setData(
                            ClipboardData(
                              text: widget.connection.entries
                                  .map((e) => '${e.key}=${e.value}')
                                  .join('\n'),
                            ),
                          );
                          if (mounted) {
                            setState(() => notice = 'Terminal MCP 连接参数已复制');
                          }
                        },
                        label: '复制 Terminal MCP 连接参数',
                        icon: CupertinoIcons.doc_on_clipboard,
                      ),
                    ),
                    const SizedBox(height: 8),
                    ExpansionTile(
                      tilePadding: EdgeInsets.zero,
                      childrenPadding: const EdgeInsets.only(bottom: 8),
                      title: const Text(
                        '查看 JSON 配置示例',
                        style: TextStyle(fontSize: 12),
                      ),
                      subtitle: const Text(
                        '适用于使用 mcpServers 配置格式的客户端；其他客户端填写相同命令、参数和环境变量。',
                      ),
                      children: [
                        SelectableText(
                          const JsonEncoder.withIndent('  ').convert({
                            'mcpServers': {
                              'terminal-use': {
                                'command': 'python3',
                                'args': [
                                  '/项目绝对路径/tools/terminal_bridge.py',
                                  'mcp',
                                ],
                                'env': {
                                  'TERMINAL_USE_URL': '<粘贴复制的 URL>',
                                  'TERMINAL_USE_TOKEN': '<粘贴复制的 TOKEN>',
                                },
                              },
                            },
                          }),
                          style: const TextStyle(
                            fontFamily: 'Menlo',
                            fontSize: 11,
                            height: 1.5,
                          ),
                        ),
                      ],
                    ),
                    const Text(
                      '写入操作会在本应用中请求风险确认（或按自动放行设置处理）。连接失败时检查应用是否仍在运行、脚本路径和本次令牌是否正确。连接参数只提供给受信任的客户端。',
                      style: TextStyle(fontSize: 12, height: 1.5),
                    ),
                  ],
                ),
            ],
            SelectableText(
              '配置位置：${AppSettings.defaultFile.path}',
              style: Theme.of(context).textTheme.bodySmall!.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

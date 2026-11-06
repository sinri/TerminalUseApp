import 'card_text.dart';
import 'terminal_approval.dart';
import 'package:flutter/material.dart';
import 'api_error_view.dart';
import 'api_request.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'mac_controls.dart';
import 'internal_agent.dart';
import 'settings.dart';
import 'terminal_workspace.dart';

class InternalAgentView extends StatefulWidget {
  const InternalAgentView({
    super.key,
    required this.agent,
    required this.task,
    required this.selected,
    required this.select,
    required this.configure,
    required this.settings,
    required this.workspace,
    this.inputFocus,
  });
  final FocusNode? inputFocus;
  final TextEditingController task;
  final ModelChoice? selected;
  final ValueChanged<ModelChoice?> select;
  final VoidCallback configure;
  final InternalAgent agent;
  final AppSettings settings;
  final TerminalWorkspace workspace;
  @override
  State<InternalAgentView> createState() => _InternalAgentViewState();
}

class _InternalAgentViewState extends State<InternalAgentView> {
  double desiredInputHeight = 136;

  Widget _mentionMenu(TextEditingValue value) {
    final caret = value.selection.extentOffset;
    if (caret < 0 || !value.selection.isCollapsed) {
      return const SizedBox.shrink();
    }
    final match = RegExp(
      r'@([^@\s]*)$',
    ).firstMatch(value.text.substring(0, caret));
    if (match == null) return const SizedBox.shrink();
    final query = match.group(1)!.toLowerCase();
    final tabs = widget.workspace.tabs
        .where(
          (t) => t.name.toLowerCase().contains(query) || t.id.contains(query),
        )
        .toList();
    if (tabs.isEmpty) return const SizedBox.shrink();
    return Material(
      elevation: 5,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 150),
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final tab in tabs)
              ListTile(
                dense: true,
                title: Text(tab.name),
                subtitle: Text(tab.id),
                onTap: () {
                  final token = '@${tab.id} ';
                  widget.task.value = TextEditingValue(
                    text: value.text.replaceRange(match.start, caret, token),
                    selection: TextSelection.collapsed(
                      offset: match.start + token.length,
                    ),
                  );
                  _focus.requestFocus();
                },
              ),
          ],
        ),
      ),
    );
  }

  final _localFocus = FocusNode(debugLabel: 'Agent input');
  FocusNode get _focus => widget.inputFocus ?? _localFocus;
  @override
  void dispose() {
    _localFocus.dispose();
    super.dispose();
  }

  Widget _approvalCard(
    TerminalReview review, {
    ApprovedOperation? approved,
  }) => Card(
    child: Padding(
      padding: const EdgeInsets.all(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${approved == null
                ? "确认终端操作"
                : approved.automatic
                ? "自动放行"
                : "手动同意"} · ${review.level}风险',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          Text(
            '${review.external ? "外部 MCP" : "Agent"} → ${review.target} · ${review.tool}',
          ),
          const SizedBox(height: 12),
          SelectableText(displayInput(review.text)),
          const SizedBox(height: 12),
          Text('命令解释：${review.explanation}'),
          const SizedBox(height: 6),
          Text('语法评估：${review.syntax}'),
          const SizedBox(height: 6),
          Text('风险依据：${review.reason}'),
          if (approved == null)
            Wrap(
              children: [
                MacButton(
                  onPressed: () => widget.agent.approvals.decide(review, false),
                  label: '拒绝',
                ),
                const SizedBox(width: 8),
                MacButton(
                  onPressed: () => widget.agent.approvals.decide(review, true),
                  label: '允许本次执行',
                  primary: true,
                ),
              ],
            ),
        ],
      ),
    ),
  );

  Widget _activityCard(ToolActivity? activity, ApprovedOperation? approval) {
    final review = approval?.review;
    final name = activity?.name ?? review!.tool;
    final label = switch (name) {
      'terminal_list' => '列出终端',
      'terminal_read' => '读取终端',
      'terminal_input' => '发送按键',
      'terminal_run' => '提交命令',
      'terminal_interrupt' => '中断前台任务',
      'skill_read' => '读取 Skill',
      _ => name,
    };
    final args = activity?.arguments;
    final preview =
        review?.text ?? args?['command'] ?? args?['text'] ?? args?['name'];
    final state = activity?.failed == true
        ? '失败'
        : approval != null
        ? '${approval.automatic ? "自动放行" : "手动同意"} · ${review!.level}风险'
        : activity?.result == null
        ? '处理中'
        : '已完成';
    final detail = review == null ? null : displayInput(review.text);
    return Card(
      child: ExpansionTile(
        key: ObjectKey(activity ?? approval),
        dense: true,
        tilePadding: const EdgeInsets.symmetric(horizontal: 10),
        title: Text(
          '$label · ${review?.target ?? activity?.target}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(state),
            if (preview is String)
              Text(
                detail ?? displayInput(preview),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontFamilyFallback: cardFontFallback,
                ),
              ),
          ],
        ),
        childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
        children: [
          if (activity?.apiFailure != null) ApiErrorView(activity!.apiFailure!),
          Align(
            alignment: Alignment.centerLeft,
            child: SelectableText(
              [
                '工具：$name',
                if (detail != null)
                  '实际输入：$detail'
                else if (preview is String)
                  '${name == "skill_read" ? "Skill" : "请求输入"}：${displayInput(preview)}',
                if (args?['terminal_id'] is String &&
                    args!['terminal_id'] != activity?.target)
                  '请求的目标：${displayInput(args["terminal_id"] as String)}',
                if (review != null) ...[
                  '命令解释：${review.explanation}',
                  '语法评估：${review.syntax}',
                  '风险依据：${review.reason}',
                ],
                if (activity?.result != null) '工具返回：${activity!.result}',
              ].join('\n\n'),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([widget.agent, widget.agent.approvals]),
    builder: (context, _) {
      final a = widget.agent;
      final review = a.approvals.pending;
      final models = [
        for (final p in widget.settings.models)
          for (final id in p.modelIds) (p, id),
      ];
      final selected = models.contains(widget.selected)
          ? widget.selected
          : models.firstOrNull;
      final task = widget.task;
      final active = widget.workspace.selected;
      return CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.enter, meta: true): () =>
              _submit(selected, active),
          const SingleActivator(LogicalKeyboardKey.period, meta: true): () {
            if (a.running) a.stop();
          },
        },
        child: Padding(
          padding: const EdgeInsets.fromLTRB(0, 0, 0, 0),
          child: LayoutBuilder(
            builder: (context, panel) => Column(
              children: [
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, body) {
                      const handleHeight = 8.0;
                      final maxHeight =
                          (body.maxHeight -
                                  handleHeight -
                                  panel.maxHeight / 2 -
                                  6)
                              .clamp(0.0, body.maxHeight);
                      final minHeight = 72.0.clamp(0.0, maxHeight);
                      final inputHeight = desiredInputHeight.clamp(
                        minHeight,
                        maxHeight,
                      );
                      return Column(
                        children: [
                          Expanded(
                            child: Container(
                              key: const Key("agent-context"),
                              width: double.infinity,
                              decoration: BoxDecoration(
                                color: Theme.of(
                                  context,
                                ).colorScheme.surfaceContainerLowest,
                              ),
                              child: Stack(
                                fit: StackFit.expand,
                                children: [
                                  SingleChildScrollView(
                                    reverse: a.log.isNotEmpty || review != null,
                                    padding: const EdgeInsets.all(12),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
                                      children: [
                                        if (a.log.isEmpty && review == null)
                                          Padding(
                                            padding: const EdgeInsets.symmetric(
                                              vertical: 16,
                                              horizontal: 8,
                                            ),
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Icon(
                                                  CupertinoIcons.chat_bubble_2,
                                                  size: 20,
                                                  color: Theme.of(
                                                    context,
                                                  ).colorScheme.primary,
                                                ),
                                                const SizedBox(height: 16),
                                                const Text(
                                                  '一起处理终端任务',
                                                  style: TextStyle(
                                                    fontSize: 14,
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                                ),
                                                const SizedBox(height: 8),
                                                Text(
                                                  active == null
                                                      ? '先新建终端，再描述需要完成的任务。'
                                                      : '描述任务，Agent 将在当前终端协助执行。\n输入 @ 可切换目标终端。',
                                                  style: TextStyle(
                                                    color: Theme.of(context)
                                                        .colorScheme
                                                        .onSurfaceVariant,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        for (final entry in a.log)
                                          if (entry is ToolActivity)
                                            if (identical(
                                                  entry,
                                                  a.activeTool,
                                                ) &&
                                                review != null &&
                                                !review.external)
                                              _approvalCard(review)
                                            else
                                              _activityCard(
                                                entry,
                                                entry.approval,
                                              )
                                          else if (entry is ApprovedOperation)
                                            _activityCard(null, entry)
                                          else if (entry is ApiRequestFailure)
                                            ApiErrorView(entry)
                                          else if (entry is AgentText)
                                            Padding(
                                              padding: const EdgeInsets.only(
                                                bottom: 8,
                                              ),
                                              child: SelectableText(
                                                '${entry.text}${entry.complete
                                                    ? ""
                                                    : a.running
                                                    ? "▍"
                                                    : "\n（输出未完成）"}',
                                              ),
                                            )
                                          else
                                            Padding(
                                              padding: const EdgeInsets.only(
                                                bottom: 8,
                                              ),
                                              child: SelectableText(
                                                entry as String,
                                              ),
                                            ),
                                        if (review != null &&
                                            (review.external ||
                                                a.activeTool == null))
                                          _approvalCard(review),
                                      ],
                                    ),
                                  ),
                                  Align(
                                    alignment: Alignment.bottomCenter,
                                    child:
                                        ValueListenableBuilder<
                                          TextEditingValue
                                        >(
                                          valueListenable: task,
                                          builder: (_, value, _) =>
                                              _mentionMenu(value),
                                        ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          MacSplitHandle(
                            key: const Key('agent-input-divider'),
                            axis: Axis.vertical,
                            label: '任务输入区高度',
                            onReset: () =>
                                setState(() => desiredInputHeight = 136),
                            onDelta: (dy) => setState(
                              () => desiredInputHeight =
                                  (desiredInputHeight.clamp(
                                            minHeight,
                                            maxHeight,
                                          ) -
                                          dy)
                                      .clamp(minHeight, maxHeight),
                            ),
                          ),
                          SizedBox(
                            height: inputHeight,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  SizedBox(
                                    height:
                                        (MediaQuery.textScalerOf(
                                                      context,
                                                    ).scale(12) *
                                                    1.4 +
                                                6)
                                            .clamp(24.0, 60.0),
                                    child: Align(
                                      alignment: Alignment.centerLeft,
                                      child: Text(
                                        active == null
                                            ? '无活跃 Tab'
                                            : '当前 Tab：${active.name}（${active.id}）',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall!
                                            .copyWith(
                                              color: Theme.of(
                                                context,
                                              ).colorScheme.onSurfaceVariant,
                                            ),
                                      ),
                                    ),
                                  ),
                                  Expanded(
                                    child: TextField(
                                      controller: task,
                                      focusNode: _focus,
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodyMedium!
                                          .copyWith(fontSize: 13, height: 1.4),
                                      expands: true,
                                      minLines: null,
                                      maxLines: null,
                                      textAlignVertical: TextAlignVertical.top,
                                      decoration: InputDecoration(
                                        hintText: '描述任务…  ⌘↵ 发送',
                                        hintMaxLines: 2,
                                        hintStyle: Theme.of(context)
                                            .textTheme
                                            .bodyMedium!
                                            .copyWith(
                                              fontSize: 13,
                                              height: 1.4,
                                              color: Theme.of(
                                                context,
                                              ).colorScheme.onSurfaceVariant,
                                            ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(10, 4, 10, 0),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      review != null ? '等待你确认本次终端操作' : a.status,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: Row(
                    children: [
                      Expanded(
                        child: MacPopup<ModelChoice>(
                          tooltip: '选择模型',
                          expanded: true,
                          label: selected == null
                              ? '选择模型'
                              : '${selected.$2} · ${selected.$1.name}',
                          value: selected,
                          entries: [
                            for (final m in models)
                              MacMenuEntry(m, '${m.$2} · ${m.$1.name}'),
                          ],
                          onSelected: a.running ? null : widget.select,
                        ),
                      ),
                      const SizedBox(width: 8),
                      ValueListenableBuilder<TextEditingValue>(
                        valueListenable: task,
                        builder: (_, value, _) => MacButton(
                          tooltip: a.running ? '停止后续操作（⌘.）' : '发送任务（⌘↵）',
                          onPressed: a.running
                              ? a.stop
                              : selected == null ||
                                    active == null ||
                                    value.text.trim().isEmpty
                              ? null
                              : () => _submit(selected, active),
                          label: a.running ? '停止' : '发送',
                          primary: !a.running,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );

  void _submit(ModelChoice? selected, TerminalTab? active) {
    final a = widget.agent;
    if (a.running || selected == null || active == null) return;
    if (!widget.task.value.composing.isCollapsed) return;
    final message = widget.task.text.trim();
    if (message.isEmpty) return;
    final mentions = RegExp(
      r'@(terminal-\d+)(?![A-Za-z0-9_-])',
    ).allMatches(message).map((m) => m.group(1)!).toSet();
    String? error;
    if (mentions.length > 1) error = '每条消息只能指定一个目标 Tab';
    final explicit = mentions.firstOrNull;
    if (explicit != null &&
        !widget.workspace.tabs.any((t) => t.id == explicit)) {
      error = '找不到 Tab：$explicit';
    }
    if (error != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error)));
      return;
    }
    widget.task.clear();
    a.run(
      selected.$1,
      message,
      explicit ?? active.id,
      SkillCatalog(widget.settings.skillRoot),
      modelId: selected.$2,
    );
  }
}

import 'card_text.dart';
import 'terminal_approval.dart';
import 'package:flutter/material.dart';
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
  });
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
  double desiredInputHeight = 112;

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

  final _focus = FocusNode();
  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  Widget _approvalCard(
    TerminalReview review, {
    ApprovedOperation? approved,
  }) => Card(
    child: Padding(
      padding: const EdgeInsets.all(12),
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
                TextButton(
                  onPressed: () => widget.agent.approvals.decide(review, false),
                  child: const Text('拒绝'),
                ),
                OutlinedButton(
                  onPressed: () => widget.agent.approvals.decide(review, true),
                  child: const Text('允许本次执行'),
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
      return Padding(
        padding: const EdgeInsets.fromLTRB(0, 4, 8, 8),
        child: LayoutBuilder(
          builder: (context, panel) => Column(
            children: [
              Row(
                children: [
                  IconButton(
                    tooltip: 'Agent 设置',
                    onPressed: widget.configure,
                    icon: const Icon(Icons.settings_outlined),
                  ),
                  const Expanded(child: Center(child: Text('Agent'))),
                  IconButton(
                    tooltip: '新建 Agent 会话',
                    onPressed: a.running
                        ? null
                        : () {
                            a.newConversation();
                            task.clear();
                          },
                    icon: const Icon(Icons.auto_awesome_outlined),
                  ),
                ],
              ),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, body) {
                    const handleHeight = 12.0;
                    final maxHeight =
                        (body.maxHeight -
                                handleHeight -
                                panel.maxHeight / 2 -
                                6)
                            .clamp(0.0, body.maxHeight);
                    final minHeight = 48.0.clamp(0.0, maxHeight);
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
                              border: Border.all(color: Colors.white24),
                            ),
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                SingleChildScrollView(
                                  reverse: true,
                                  padding: const EdgeInsets.all(12),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      if (a.log.isEmpty && review == null)
                                        const SelectableText('发送消息，开始终端运维会话。'),
                                      for (final entry in a.log)
                                        if (entry is ToolActivity)
                                          if (identical(entry, a.activeTool) &&
                                              review != null &&
                                              !review.external)
                                            _approvalCard(review)
                                          else
                                            _activityCard(entry, entry.approval)
                                        else if (entry is ApprovedOperation)
                                          _activityCard(null, entry)
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
                                      ValueListenableBuilder<TextEditingValue>(
                                        valueListenable: task,
                                        builder: (_, value, _) =>
                                            _mentionMenu(value),
                                      ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        MouseRegion(
                          cursor: SystemMouseCursors.resizeRow,
                          child: GestureDetector(
                            key: const Key('agent-input-divider'),
                            behavior: HitTestBehavior.opaque,
                            onVerticalDragUpdate: (e) => setState(
                              () => desiredInputHeight =
                                  (desiredInputHeight.clamp(
                                            minHeight,
                                            maxHeight,
                                          ) -
                                          e.delta.dy)
                                      .clamp(minHeight, maxHeight),
                            ),
                            child: const SizedBox(
                              width: double.infinity,
                              height: handleHeight,
                              child: Center(
                                child: SizedBox(
                                  width: 32,
                                  child: Divider(height: 1, thickness: 2),
                                ),
                              ),
                            ),
                          ),
                        ),
                        SizedBox(
                          height: inputHeight,
                          child: TextField(
                            controller: task,
                            focusNode: _focus,
                            expands: true,
                            minLines: null,
                            maxLines: null,
                            textAlignVertical: TextAlignVertical.top,
                            decoration: InputDecoration(
                              floatingLabelBehavior:
                                  FloatingLabelBehavior.always,
                              label: Text(
                                active == null
                                    ? '无活跃 Tab'
                                    : '当前 Tab：${active.name}（${active.id}）',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              hintText: '输入 @ 选择 Tab',
                              border: const OutlineInputBorder(),
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
              Row(
                children: [
                  Expanded(
                    child: DropdownButton<ModelChoice>(
                      isExpanded: true,
                      value: selected,
                      hint: const Text('选择模型'),
                      items: [
                        for (final m in models)
                          DropdownMenuItem(
                            value: m,
                            child: Text(
                              '${m.$2} · ${m.$1.name}',
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                      onChanged: a.running ? null : widget.select,
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: a.running
                        ? a.stop
                        : selected == null || widget.workspace.selected == null
                        ? null
                        : () {
                            final message = task.text.trim();
                            if (message.isEmpty) return;
                            final mentions =
                                RegExp(r'@(terminal-\d+)(?![A-Za-z0-9_-])')
                                    .allMatches(message)
                                    .map((m) => m.group(1)!)
                                    .toSet();
                            if (mentions.length > 1) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('每条消息只能指定一个目标 Tab'),
                                ),
                              );
                              return;
                            }
                            final explicit = mentions.firstOrNull;
                            if (explicit != null &&
                                !widget.workspace.tabs.any(
                                  (t) => t.id == explicit,
                                )) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('找不到 Tab：$explicit')),
                              );
                              return;
                            }
                            task.clear();
                            a.run(
                              selected.$1,
                              message,
                              explicit ?? active!.id,
                              SkillCatalog(widget.settings.skillRoot),
                              modelId: selected.$2,
                            );
                          },
                    child: Text(a.running ? '停止' : '发送'),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    },
  );
}

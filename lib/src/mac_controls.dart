import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Desktop-sized controls built on Flutter's focus, action and menu primitives.
/// They deliberately share system typography and semantic theme colors.
class MacButton extends StatelessWidget {
  const MacButton({
    super.key,
    required this.onPressed,
    this.label,
    this.icon,
    this.child,
    this.tooltip,
    this.primary = false,
    this.toolbar = false,
    this.destructive = false,
    this.focusNode,
    this.autofocus = false,
  }) : assert(label != null || icon != null || child != null);

  final VoidCallback? onPressed;
  final String? label, tooltip;
  final IconData? icon;
  final Widget? child;
  final bool primary, toolbar, destructive, autofocus;
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    final dark = c.brightness == Brightness.dark;
    final ink = destructive
        ? c.error
        : primary
        ? c.onPrimary
        : c.onSurface;
    final result = TextButton(
      onPressed: onPressed,
      focusNode: focusNode,
      autofocus: autofocus,
      style: ButtonStyle(
        textStyle: WidgetStatePropertyAll(
          Theme.of(context).textTheme.labelLarge!.copyWith(fontSize: 12),
        ),
        minimumSize: WidgetStatePropertyAll(
          Size(label == null && child == null ? 26 : 44, 26),
        ),
        padding: WidgetStatePropertyAll(
          EdgeInsets.symmetric(horizontal: toolbar ? 6 : 10, vertical: 4),
        ),
        visualDensity: VisualDensity.standard,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        animationDuration: Duration.zero,
        overlayColor: const WidgetStatePropertyAll(Colors.transparent),
        foregroundColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.disabled)
              ? c.onSurface.withValues(alpha: .38)
              : ink,
        ),
        backgroundColor: WidgetStateProperty.resolveWith((s) {
          if (s.contains(WidgetState.disabled)) {
            return toolbar ? Colors.transparent : c.surfaceContainer;
          }
          if (s.contains(WidgetState.pressed)) {
            return primary
                ? c.primary.withValues(alpha: .8)
                : c.onSurface.withValues(alpha: .15);
          }
          if (s.contains(WidgetState.hovered)) {
            return primary
                ? c.primary.withValues(alpha: .9)
                : c.onSurface.withValues(alpha: .08);
          }
          return primary
              ? c.primary
              : toolbar
              ? Colors.transparent
              : c.surfaceContainerLowest;
        }),
        side: WidgetStateProperty.resolveWith(
          (s) => BorderSide(
            color: s.contains(WidgetState.focused)
                ? c.primary
                : toolbar || primary
                ? Colors.transparent
                : c.outlineVariant,
            width: s.contains(WidgetState.focused) ? 2 : 1,
          ),
        ),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
        ),
        shadowColor: WidgetStatePropertyAll(
          dark ? Colors.transparent : Colors.black12,
        ),
        elevation: WidgetStatePropertyAll(toolbar || primary ? 0 : .5),
      ),
      child:
          child ??
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) Icon(icon, size: 14),
              if (icon != null && label != null) const SizedBox(width: 5),
              if (label != null) Text(label!, maxLines: 1),
            ],
          ),
    );
    return tooltip == null ? result : Tooltip(message: tooltip!, child: result);
  }
}

class MacMenuEntry<T> {
  const MacMenuEntry(this.value, this.label, {this.icon});
  final T value;
  final String label;
  final IconData? icon;
}

/// Anchored menus retain Flutter's arrow-key navigation, Enter and Escape.
class MacPopup<T> extends StatefulWidget {
  const MacPopup({
    super.key,
    required this.entries,
    required this.onSelected,
    required this.label,
    this.value,
    this.tooltip,
    this.icon,
    this.toolbar = false,
    this.expanded = false,
    this.showChevron = true,
  });
  final List<MacMenuEntry<T>> entries;
  final ValueChanged<T>? onSelected;
  final T? value;
  final String label;
  final String? tooltip;
  final IconData? icon;
  final bool toolbar, expanded, showChevron;

  @override
  State<MacPopup<T>> createState() => _MacPopupState<T>();
}

class _MacPopupState<T> extends State<MacPopup<T>> {
  final _buttonFocus = FocusNode();
  final _firstItemFocus = FocusNode();
  final _menu = MenuController();

  @override
  void dispose() {
    _buttonFocus.dispose();
    _firstItemFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final entries = widget.entries;
    final onSelected = widget.onSelected;
    final value = widget.value;
    final label = widget.label;
    final tooltip = widget.tooltip;
    final icon = widget.icon;
    final toolbar = widget.toolbar;
    final expanded = widget.expanded;
    final c = Theme.of(context).colorScheme;
    final button = SizedBox(
      width: expanded ? double.infinity : null,
      child: MenuAnchor(
        controller: _menu,
        childFocusNode: _buttonFocus,
        onOpen: () => WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _menu.isOpen) _firstItemFocus.requestFocus();
        }),
        builder: (context, controller, child) => CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.arrowDown): () {
              if (onSelected != null && entries.isNotEmpty) controller.open();
            },
          },
          child: TextButton(
            focusNode: _buttonFocus,
            onPressed: onSelected == null || entries.isEmpty
                ? null
                : () {
                    controller.isOpen ? controller.close() : controller.open();
                  },
            style: ButtonStyle(
              minimumSize: const WidgetStatePropertyAll(Size(26, 26)),
              padding: WidgetStatePropertyAll(
                EdgeInsets.symmetric(horizontal: toolbar ? 4 : 8, vertical: 4),
              ),
              textStyle: WidgetStatePropertyAll(
                Theme.of(context).textTheme.labelLarge!.copyWith(fontSize: 12),
              ),
              foregroundColor: toolbar
                  ? WidgetStateProperty.resolveWith(
                      (states) => states.contains(WidgetState.disabled)
                          ? c.onSurface.withValues(alpha: .38)
                          : c.onSurface,
                    )
                  : null,
              backgroundColor: WidgetStatePropertyAll(
                toolbar ? Colors.transparent : c.surfaceContainerLowest,
              ),
              side: WidgetStateProperty.resolveWith(
                (states) => BorderSide(
                  color: states.contains(WidgetState.focused)
                      ? c.primary
                      : toolbar
                      ? Colors.transparent
                      : c.outlineVariant,
                  width: states.contains(WidgetState.focused) ? 2 : 1,
                ),
              ),
              shape: WidgetStatePropertyAll(
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
              ),
              visualDensity: VisualDensity.standard,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              alignment: label.isEmpty && !widget.showChevron
                  ? Alignment.center
                  : Alignment.centerLeft,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 14),
                  if (label.isNotEmpty || widget.showChevron)
                    const SizedBox(width: 6),
                ],
                if (label.isNotEmpty) ...[
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                if (widget.showChevron)
                  const Icon(CupertinoIcons.chevron_down, size: 10),
              ],
            ),
          ),
        ),
        menuChildren: onSelected == null
            ? const []
            : [
                for (final entry in entries)
                  MenuItemButton(
                    focusNode: identical(entry, entries.first)
                        ? _firstItemFocus
                        : null,
                    onPressed: () => onSelected(entry.value),
                    leadingIcon: Icon(
                      value == entry.value
                          ? CupertinoIcons.check_mark
                          : entry.icon,
                      size: 13,
                    ),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 360),
                      child: Text(
                        entry.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
              ],
      ),
    );
    final sized = expanded
        ? button
        : label.isEmpty
        ? SizedBox(width: 28, child: button)
        : IntrinsicWidth(child: button);
    return tooltip == null ? sized : Tooltip(message: tooltip, child: sized);
  }
}

class MacSection extends StatelessWidget {
  const MacSection({
    super.key,
    required this.title,
    required this.children,
    this.description,
    this.trailing,
  });
  final String title;
  final String? description;
  final Widget? trailing;
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 20),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 2, bottom: 6),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              if (trailing != null) ...[const SizedBox(width: 12), trailing!],
            ],
          ),
        ),
        Material(
          color: Theme.of(context).colorScheme.surfaceContainerLowest,
          shape: RoundedRectangleBorder(
            side: BorderSide(
              color: Theme.of(context).colorScheme.outlineVariant,
            ),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: children,
            ),
          ),
        ),
        if (description != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(2, 6, 2, 0),
            child: Text(
              description!,
              style: Theme.of(context).textTheme.bodySmall!.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
      ],
    ),
  );
}

class MacSplitHandle extends StatefulWidget {
  const MacSplitHandle({
    super.key,
    required this.axis,
    required this.onDelta,
    required this.label,
    this.onReset,
  });
  final Axis axis;
  final ValueChanged<double> onDelta;
  final String label;
  final VoidCallback? onReset;
  @override
  State<MacSplitHandle> createState() => _MacSplitHandleState();
}

class _MacSplitHandleState extends State<MacSplitHandle> {
  final _focus = FocusNode(debugLabel: 'Split handle');
  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  bool hovered = false, focused = false;
  @override
  Widget build(BuildContext context) {
    final horizontal = widget.axis == Axis.horizontal;
    final c = Theme.of(context).colorScheme;
    return Semantics(
      label: '${widget.label}，使用方向键调整，双击恢复',
      onIncrease: () => widget.onDelta(16),
      onDecrease: () => widget.onDelta(-16),
      child: Focus(
        focusNode: _focus,
        onFocusChange: (v) => setState(() => focused = v),
        onKeyEvent: (_, e) {
          if (e is! KeyDownEvent && e is! KeyRepeatEvent) {
            return KeyEventResult.ignored;
          }
          if (e.logicalKey ==
              (horizontal
                  ? LogicalKeyboardKey.arrowRight
                  : LogicalKeyboardKey.arrowDown)) {
            widget.onDelta(16);
            return KeyEventResult.handled;
          }
          if (e.logicalKey ==
              (horizontal
                  ? LogicalKeyboardKey.arrowLeft
                  : LogicalKeyboardKey.arrowUp)) {
            widget.onDelta(-16);
            return KeyEventResult.handled;
          }
          if (e.logicalKey == LogicalKeyboardKey.home &&
              widget.onReset != null) {
            widget.onReset!();
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: MouseRegion(
          cursor: horizontal
              ? SystemMouseCursors.resizeColumn
              : SystemMouseCursors.resizeRow,
          onEnter: (_) => setState(() => hovered = true),
          onExit: (_) => setState(() => hovered = false),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _focus.requestFocus,
            onDoubleTap: widget.onReset,
            onHorizontalDragUpdate: horizontal
                ? (e) => widget.onDelta(e.delta.dx)
                : null,
            onVerticalDragUpdate: horizontal
                ? null
                : (e) => widget.onDelta(e.delta.dy),
            child: SizedBox(
              width: horizontal ? 6 : double.infinity,
              height: horizontal ? double.infinity : 8,
              child: Center(
                child: ColoredBox(
                  color: focused || hovered ? c.primary : c.outlineVariant,
                  child: SizedBox(
                    width: horizontal
                        ? (focused || hovered ? 2 : 1)
                        : double.infinity,
                    height: horizontal ? double.infinity : 1,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class MacSidebarItem extends StatefulWidget {
  const MacSidebarItem({
    super.key,
    required this.label,
    required this.selected,
    required this.running,
    required this.onSelect,
    required this.onClose,
    required this.onRename,
    required this.onContextMenu,
  });
  final String label;
  final bool selected, running;
  final VoidCallback onSelect, onClose, onRename;
  final ValueChanged<Offset> onContextMenu;
  @override
  State<MacSidebarItem> createState() => _MacSidebarItemState();
}

class _MacSidebarItemState extends State<MacSidebarItem> {
  bool hovered = false, focused = false;
  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    final showClose = hovered || focused || widget.selected;
    return Semantics(
      selected: widget.selected,
      child: MouseRegion(
        onEnter: (_) => setState(() => hovered = true),
        onExit: (_) => setState(() => hovered = false),
        child: Focus(
          canRequestFocus: false,
          onFocusChange: (v) => setState(() => focused = v),
          child: Material(
            color: widget.selected
                ? c.secondaryContainer
                : hovered
                ? c.onSurface.withValues(alpha: .05)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(5),
            child: Container(
              constraints: const BoxConstraints(minHeight: 30),
              padding: const EdgeInsets.only(right: 2),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(5),
                border: Border.all(
                  color: focused ? c.primary : Colors.transparent,
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Listener(
                      // Source lists select immediately, before double-click detection.
                      onPointerDown: (e) {
                        if (e.buttons == 1) widget.onSelect();
                      },
                      child: CallbackShortcuts(
                        bindings: {
                          const SingleActivator(LogicalKeyboardKey.f2):
                              widget.onRename,
                        },
                        child: InkWell(
                          borderRadius: BorderRadius.circular(5),
                          onTap: widget.onSelect,
                          onDoubleTap: widget.onRename,
                          onSecondaryTapDown: (e) =>
                              widget.onContextMenu(e.globalPosition),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 6,
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  CupertinoIcons
                                      .chevron_left_slash_chevron_right,
                                  size: 14,
                                  color: widget.selected
                                      ? c.primary
                                      : c.onSurfaceVariant,
                                ),
                                const SizedBox(width: 7),
                                Expanded(
                                  child: Text(
                                    widget.label,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                ),
                                if (!widget.running)
                                  const Padding(
                                    padding: EdgeInsets.only(left: 4),
                                    child: Text(
                                      '已退出',
                                      style: TextStyle(fontSize: 10),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  // Close is a sibling of the double-click target, so it never waits
                  // for the double-click gesture arena or selects an inactive tab.
                  ExcludeFocus(
                    excluding: !showClose,
                    child: IgnorePointer(
                      ignoring: !showClose,
                      child: Opacity(
                        opacity: showClose ? 1 : 0,
                        child: MacButton(
                          onPressed: widget.onClose,
                          icon: CupertinoIcons.xmark,
                          toolbar: true,
                          tooltip: '关闭 ${widget.label}',
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

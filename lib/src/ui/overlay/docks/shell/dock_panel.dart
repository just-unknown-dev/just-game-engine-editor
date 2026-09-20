import 'package:flutter/material.dart';

import '../../../../core/constants/editor_constants.dart';
import '../../../../core/scope/editor_scope.dart';
import '../../../../extension/editor_contributions.dart';
import '../../settings/overlay_ui_settings.dart';
import '../dock_controller.dart';
import '../logs_dock.dart' show PanelResizeHandle;

/// Colour for a badge of [severity]; the accent for the quiet ones.
Color dockSeverityColor(DockSeverity severity, Color accent) =>
    switch (severity) {
      DockSeverity.error => EditorTheme.error,
      DockSeverity.warning => EditorTheme.warning,
      DockSeverity.info || DockSeverity.none => accent,
    };

/// The bottom panel: a row of tabs, the active dock's own buttons, and the
/// dock itself. Every dock — the editor's and a module's — shows here.
class DockPanel extends StatelessWidget {
  const DockPanel({
    super.key,
    required this.scope,
    required this.docks,
    required this.controller,
    required this.settings,
    required this.height,
    required this.maxHeight,
  });

  final EditorScope scope;

  /// Every dock there is, pinned or not.
  final List<DockDefinition> docks;
  final DockController controller;
  final OverlayUiSettings settings;
  final double height;
  final double maxHeight;

  static const double tabBarHeight = 30;

  DockDefinition? _byId(String? id) {
    for (final d in docks) {
      if (d.id == id) return d;
    }
    return null;
  }

  DockContext contextFor(DockDefinition dock, {VoidCallback? onClose}) =>
      DockContext(
        scope: scope,
        height: height - tabBarHeight,
        onResize: (dy) => controller.resize(
          dock.id,
          dy,
          fallback: dock.defaultHeight,
          max: maxHeight,
        ),
        onClose: onClose ?? controller.close,
        memory: controller.memoryOf(dock.id),
        args: controller.isOpen(dock.id) ? controller.openArgs : const {},
      );

  @override
  Widget build(BuildContext context) {
    final active = _byId(controller.activeDock);
    if (active == null) return const SizedBox.shrink();
    final maximised = controller.maximised.value;
    final accent = settings.themeColor;
    final dockContext = contextFor(active);

    return SizedBox(
      height: height,
      child: Material(
        color: Colors.transparent,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: EditorTheme.dialogBg,
            border: Border(
              top: BorderSide(color: accent.withValues(alpha: 0.35)),
            ),
            boxShadow: const [
              BoxShadow(
                color: Color(0x55000000),
                blurRadius: 12,
                offset: Offset(0, -4),
              ),
            ],
          ),
          child: Column(
            children: [
              if (!maximised)
                GestureDetector(
                  onDoubleTap: () => controller.resetHeight(active.id),
                  child: PanelResizeHandle(onDrag: dockContext.onResize),
                ),
              SizedBox(
                height: tabBarHeight,
                child: Row(
                  children: [
                    Expanded(
                      child: _TabBar(
                        scope: scope,
                        docks: docks,
                        controller: controller,
                        accent: accent,
                        textScale: settings.effectiveTextScale,
                      ),
                    ),
                    ...?active.headerActions?.call(context, dockContext),
                    const SizedBox(width: 4),
                    DockHeaderButton(
                      icon: maximised
                          ? Icons.close_fullscreen_rounded
                          : Icons.open_in_full_rounded,
                      tooltip: maximised ? 'Restore' : 'Maximise',
                      isActive: maximised,
                      accent: accent,
                      onTap: () => controller.maximised.value = !maximised,
                    ),
                    DockHeaderButton(
                      icon: Icons.open_in_new_rounded,
                      tooltip: 'Pop out into its own window',
                      accent: accent,
                      onTap: () => controller.popOut(active.id),
                    ),
                    DockHeaderButton(
                      icon: Icons.keyboard_arrow_down_rounded,
                      tooltip: 'Collapse  (Esc)',
                      accent: accent,
                      onTap: controller.close,
                    ),
                    const SizedBox(width: 4),
                  ],
                ),
              ),
              const Divider(height: 1, color: EditorTheme.border),
              Expanded(
                child: Stack(
                  children: [
                    // Docks that asked to be kept alive stay built while
                    // another shows, so they lose nothing on a tab switch.
                    for (final dock in docks)
                      if (dock.id == active.id ||
                          (dock.keepAlive &&
                              controller.order.value.contains(dock.id) &&
                              !controller.poppedOut.value.contains(dock.id)))
                        Positioned.fill(
                          child: Offstage(
                            offstage: dock.id != active.id,
                            child: TickerMode(
                              enabled: dock.id == active.id,
                              child: KeyedSubtree(
                                key: ValueKey('dock:${dock.id}'),
                                child: dock.build(context, contextFor(dock)),
                              ),
                            ),
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
  }
}

/// A small square button in the panel's header.
class DockHeaderButton extends StatelessWidget {
  const DockHeaderButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.accent = EditorTheme.primaryBright,
    this.isActive = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;
  final Color accent;
  final bool isActive;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: tooltip,
    waitDuration: const Duration(milliseconds: 400),
    child: Material(
      color: isActive ? accent.withValues(alpha: 0.18) : Colors.transparent,
      borderRadius: BorderRadius.circular(5),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        hoverColor: accent.withValues(alpha: 0.12),
        child: SizedBox.square(
          dimension: 24,
          child: Icon(
            icon,
            size: 14,
            color: onTap == null
                ? EditorTheme.textMuted.withValues(alpha: 0.4)
                : isActive
                ? accent
                : EditorTheme.textSecondary,
          ),
        ),
      ),
    ),
  );
}

class _TabBar extends StatelessWidget {
  const _TabBar({
    required this.scope,
    required this.docks,
    required this.controller,
    required this.accent,
    required this.textScale,
  });

  final EditorScope scope;
  final List<DockDefinition> docks;
  final DockController controller;
  final Color accent;
  final double textScale;

  @override
  Widget build(BuildContext context) {
    final byId = {for (final d in docks) d.id: d};
    final popped = controller.poppedOut.value;
    final tabs = [
      for (final id in controller.order.value)
        if (byId[id] != null && !popped.contains(id)) byId[id]!,
    ];
    final others = [
      for (final d in docks)
        if (!controller.order.value.contains(d.id) && !popped.contains(d.id)) d,
    ];
    return Row(
      children: [
        Flexible(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (var i = 0; i < tabs.length; i++)
                  _Tab(
                    dock: tabs[i],
                    index: i,
                    badge: tabs[i].tabBadge?.call(scope),
                    isActive: controller.activeDock == tabs[i].id,
                    accent: accent,
                    textScale: textScale,
                    controller: controller,
                  ),
              ],
            ),
          ),
        ),
        if (others.isNotEmpty)
          PopupMenuButton<String>(
            tooltip: 'More docks',
            padding: EdgeInsets.zero,
            color: EditorTheme.dialogBg,
            icon: const Icon(
              Icons.add_rounded,
              size: 15,
              color: EditorTheme.textSecondary,
            ),
            onSelected: controller.open,
            itemBuilder: (context) => [
              for (final d in others)
                PopupMenuItem(
                  value: d.id,
                  height: 30,
                  child: Row(
                    children: [
                      Icon(d.icon, size: 13, color: EditorTheme.textSecondary),
                      const SizedBox(width: 8),
                      Text(
                        d.label,
                        style: const TextStyle(
                          color: EditorTheme.textPrimary,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
      ],
    );
  }
}

/// One tab: click to show, drag onto another to reorder, middle-click or the
/// small ✕ to take it off the bar.
class _Tab extends StatefulWidget {
  const _Tab({
    required this.dock,
    required this.index,
    required this.badge,
    required this.isActive,
    required this.accent,
    required this.textScale,
    required this.controller,
  });

  final DockDefinition dock;
  final int index;
  final DockBadge? badge;
  final bool isActive;
  final Color accent;
  final double textScale;
  final DockController controller;

  @override
  State<_Tab> createState() => _TabState();
}

class _TabState extends State<_Tab> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final dock = widget.dock;
    final badge = widget.badge;
    final color = widget.isActive
        ? EditorTheme.textPrimary
        : EditorTheme.textSecondary;

    final body = MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Listener(
        onPointerDown: (e) {
          // Middle click closes a tab, as it does everywhere else.
          if (e.buttons & 0x04 != 0) widget.controller.unpin(dock.id);
        },
        child: InkWell(
          onTap: () => widget.controller.open(dock.id),
          child: Container(
            height: DockPanel.tabBarHeight,
            padding: const EdgeInsets.only(left: 10, right: 6),
            decoration: BoxDecoration(
              color: widget.isActive
                  ? widget.accent.withValues(alpha: 0.10)
                  : null,
              border: Border(
                bottom: BorderSide(
                  width: 2,
                  color: widget.isActive ? widget.accent : Colors.transparent,
                ),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  dock.icon,
                  size: 13,
                  color: widget.isActive ? widget.accent : color,
                ),
                const SizedBox(width: 6),
                Text(
                  dock.label,
                  style: TextStyle(
                    color: color,
                    fontSize: 11 * widget.textScale,
                    fontWeight: widget.isActive
                        ? FontWeight.w600
                        : FontWeight.w500,
                  ),
                ),
                if (badge != null && badge.text.isNotEmpty) ...[
                  const SizedBox(width: 6),
                  _BadgePill(badge: badge, accent: widget.accent),
                ],
                SizedBox(
                  width: 18,
                  child: _hovered
                      ? InkWell(
                          onTap: () => widget.controller.unpin(dock.id),
                          child: const Icon(
                            Icons.close_rounded,
                            size: 11,
                            color: EditorTheme.textMuted,
                          ),
                        )
                      : null,
                ),
              ],
            ),
          ),
        ),
      ),
    );

    return DragTarget<String>(
      onWillAcceptWithDetails: (d) =>
          d.data != dock.id && widget.controller.order.value.contains(d.data),
      onAcceptWithDetails: (d) => widget.controller.move(d.data, widget.index),
      builder: (context, incoming, _) => Draggable<String>(
        data: dock.id,
        axis: Axis.horizontal,
        feedback: Material(
          color: Colors.transparent,
          child: Opacity(opacity: 0.85, child: body),
        ),
        childWhenDragging: Opacity(opacity: 0.35, child: body),
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: Border(
              left: BorderSide(
                width: 2,
                color: incoming.isEmpty ? Colors.transparent : widget.accent,
              ),
            ),
          ),
          child: body,
        ),
      ),
    );
  }
}

class _BadgePill extends StatelessWidget {
  const _BadgePill({required this.badge, required this.accent});

  final DockBadge badge;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final color = dockSeverityColor(badge.severity, accent);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        badge.text,
        style: TextStyle(
          color: color,
          fontSize: 9,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

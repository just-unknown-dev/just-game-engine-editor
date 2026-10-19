import 'package:flutter/material.dart';

import 'package:just_editor_core/host.dart';
import '../dock_controller.dart';
import '../panel_parts.dart' show PanelResizeHandle;

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
    this.pulse,
    this.collapseKey,
  });

  final EditorScope scope;

  /// Every dock there is, pinned or not.
  final List<DockDefinition> docks;
  final DockController controller;
  final OverlayUiSettings settings;
  final double height;
  final double maxHeight;

  /// Ticks while the strip refreshes its numbers: the tabs' badges and the
  /// active dock's own buttons follow it; the docks themselves do not — each
  /// listens to whatever it shows.
  final Listenable? pulse;

  /// The key that collapses the panel, for the button's tooltip.
  final String? collapseKey;

  static double get tabBarHeight => EditorMetrics.minTarget + 6;

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
    final accent = EditorTheme.accent;
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
                child: ListenableBuilder(
                  listenable: pulse ?? const _Never(),
                  builder: (context, _) => Row(
                    children: [
                      Expanded(
                        child: _TabBar(
                          scope: scope,
                          docks: docks,
                          controller: controller,
                          accent: accent,
                        ),
                      ),
                      ...?active.headerActions?.call(context, dockContext),
                      const SizedBox(width: 4),
                      EditorIconButton(
                        icon: maximised
                            ? Icons.close_fullscreen_rounded
                            : Icons.open_in_full_rounded,
                        tooltip: maximised ? 'Restore' : 'Maximise',
                        isActive: maximised,
                        activeColor: accent,
                        onTap: () => controller.maximised.value = !maximised,
                      ),
                      EditorIconButton(
                        icon: Icons.open_in_new_rounded,
                        tooltip: 'Pop out into its own window',
                        activeColor: accent,
                        onTap: () => controller.popOut(active.id),
                      ),
                      EditorIconButton(
                        icon: Icons.keyboard_arrow_down_rounded,
                        tooltip: tooltipWithShortcut('Collapse', collapseKey),
                        activeColor: accent,
                        onTap: controller.close,
                      ),
                      const SizedBox(width: 4),
                    ],
                  ),
                ),
              ),
              Divider(height: 1, color: EditorTheme.border),
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

/// A listenable that never fires: a panel with no pulse.
class _Never implements Listenable {
  const _Never();

  @override
  void addListener(VoidCallback listener) {}

  @override
  void removeListener(VoidCallback listener) {}
}

class _TabBar extends StatelessWidget {
  const _TabBar({
    required this.scope,
    required this.docks,
    required this.controller,
    required this.accent,
  });

  final EditorScope scope;
  final List<DockDefinition> docks;
  final DockController controller;
  final Color accent;

  String? _keyOf(String dockId) => _key('dock.open.$dockId');

  String? _key(String commandId) {
    final bound = scope.commands.bindingsFor(commandId);
    return bound.isEmpty ? null : bound.first.shortcut;
  }

  Future<void> _showMore(
    BuildContext context,
    List<DockDefinition> others,
    Map<String, DockDefinition> byId,
    Set<String> popped,
  ) async {
    final box = context.findRenderObject() as RenderBox?;
    final at = box == null
        ? Offset.zero
        : box.localToGlobal(box.size.topLeft(Offset.zero));
    final windows = [
      for (final id in popped)
        if (byId[id] != null) byId[id]!,
    ];
    final chosen = await showEditorMenu<String>(context, at, [
      if (others.isNotEmpty) ...[
        editorMenuHeading('Add a tab'),
        for (final d in others)
          editorMenuItem('open:${d.id}', d.label, icon: d.icon),
      ],
      if (windows.isNotEmpty) ...[
        if (others.isNotEmpty) editorMenuDivider(),
        editorMenuHeading('In a window'),
        for (final d in windows)
          editorMenuItem(
            'back:${d.id}',
            'Put ${d.label} back',
            icon: Icons.move_down_rounded,
          ),
      ],
      if (others.isEmpty && windows.isEmpty)
        editorMenuItem('', 'Every dock is on the bar', enabled: false),
    ]);
    if (chosen == null || chosen.isEmpty) return;
    final id = chosen.substring(chosen.indexOf(':') + 1);
    chosen.startsWith('back:') ? controller.popIn(id) : controller.open(id);
  }

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
                    controller: controller,
                    shortcut: _keyOf(tabs[i].id),
                    maximiseKey: _key('dock.maximise'),
                  ),
              ],
            ),
          ),
        ),
        // Always there: every dock is reachable from it — the ones kept off
        // the bar, and the ones popped out into a window of their own.
        Builder(
          builder: (context) => EditorIconButton(
            icon: Icons.add_rounded,
            tooltip: 'More docks',
            onTap: () => _showMore(context, others, byId, popped),
          ),
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
    required this.controller,
    this.shortcut,
    this.maximiseKey,
  });

  final DockDefinition dock;
  final int index;
  final DockBadge? badge;
  final bool isActive;
  final Color accent;
  final DockController controller;

  /// The keys that open it, for its tooltip.
  final String? shortcut;

  /// The keys that maximise the panel, for the tab's menu.
  final String? maximiseKey;

  @override
  State<_Tab> createState() => _TabState();
}

class _TabState extends State<_Tab> {
  bool _hovered = false;

  Future<void> _showMenu(Offset at) async {
    final c = widget.controller;
    final id = widget.dock.id;
    final isOpen = c.activeDock == id;
    final chosen = await showEditorMenu<String>(context, at, [
      editorMenuItem(
        'popout',
        'Pop out into a window',
        icon: Icons.open_in_new_rounded,
      ),
      editorMenuItem(
        'maximise',
        isOpen && c.maximised.value ? 'Restore its height' : 'Maximise',
        icon: Icons.open_in_full_rounded,
        shortcut: widget.maximiseKey,
      ),
      editorMenuDivider(),
      editorMenuItem(
        'unpin',
        'Take off the bar',
        icon: Icons.close_rounded,
        shortcut: 'Middle-click',
      ),
    ]);
    switch (chosen) {
      case 'popout':
        c.popOut(id);
      case 'maximise':
        if (!isOpen) c.open(id);
        c.maximised.value = !(isOpen && c.maximised.value);
      case 'unpin':
        c.unpin(id);
    }
  }

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
          // A right click: what can be done with the tab.
          onSecondaryTapUp: (details) => _showMenu(details.globalPosition),
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
                    fontSize: 11,
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
                      ? Tooltip(
                          message: 'Take off the bar  (middle-click)',
                          child: InkWell(
                            onTap: () => widget.controller.unpin(dock.id),
                            child: Icon(
                              Icons.close_rounded,
                              size: 11,
                              color: EditorTheme.textMuted,
                            ),
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
          child: Tooltip(
            message: tooltipWithShortcut(dock.label, widget.shortcut),
            child: body,
          ),
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

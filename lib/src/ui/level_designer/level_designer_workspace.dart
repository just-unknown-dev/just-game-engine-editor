import 'package:flutter/material.dart';
import 'package:just_signals/just_signals.dart';

import 'package:just_editor_core/host.dart';
import 'level_designer_session.dart';
import 'panels/align_bar.dart';
import 'panels/designer_switch.dart';
import 'panels/level_layers_panel.dart';
import 'panels/prefab_palette_panel.dart';
import 'panels/tileset_palette_panel.dart';

/// The Level Designer's panel: the designer in use, its sections — prefabs,
/// layers, the tileset, whatever modules add — and the align bar for what is
/// selected. The right panel shows it as its **Level** tab while the designer
/// is open, beside the Inspector, so the level keeps the width of one panel.
///
/// Its tool strip floats over the viewport, top right, and its status bar
/// runs along the foot of the level; neither is here. Deliberately *not* a
/// container for the viewport: the designer's overlays go on the game's own
/// canvas through the plugin's render hook, so there is one source of truth
/// for what the viewport shows.
class LevelDesignerWorkspace extends StatelessWidget {
  const LevelDesignerWorkspace({
    super.key,
    required this.session,
    required this.gridSize,
    required this.onGridSizeChanged,
    required this.onClose,
  });

  /// The session this chrome drives.
  final LevelDesignerSession session;

  /// Current grid size, owned by the plugin's overlay settings.
  final double gridSize;

  /// Propagates a grid-size change back to the plugin.
  final ValueChanged<double> onGridSizeChanged;

  /// Closes the designer.
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) => _DesignerSidePanel(
    session: session,
    gridSize: gridSize,
    onClose: onClose,
  );
}

class _DesignerSidePanel extends StatelessWidget {
  const _DesignerSidePanel({
    required this.session,
    required this.gridSize,
    required this.onClose,
  });

  final LevelDesignerSession session;
  final double gridSize;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) =>
      SignalBuilder3<String?, String, Map<String, Map<String, bool>>>(
        // Everything below follows the designer in use, and which sections are
        // open follows the tools in hand.
        signal1: session.scope.activeDesigner,
        signal2: session.controller.toolId,
        signal3: session.controller.sectionsOpen,
        builder: (context, _, _, _, _) => _buildPanel(context),
      );

  /// The tools that place and move entities.
  static const Set<String> _entityTools = {
    ToolGroups.select,
    ToolGroups.shapes,
  };

  static const Set<String> _tileTools = {ToolGroups.tiles};

  Widget _buildPanel(BuildContext context) {
    final controller = session.controller;
    final sections = <_SectionSpec>[
      _SectionSpec(
        id: 'prefabs',
        title: 'PREFABS',
        groups: _entityTools,
        flex: 3,
        build: (_) => PrefabPalettePanel(session: session),
      ),
      // Open whatever the tool: every tool works on a layer.
      _SectionSpec(
        id: 'layers',
        title: 'LAYERS',
        flex: 2,
        build: (_) => LevelLayersPanel(session: session),
      ),
      _SectionSpec(
        id: 'tileset',
        title: 'TILESET',
        groups: _tileTools,
        flex: 3,
        build: (_) => TilesetPalettePanel(session: session),
      ),
      // What the modules add, under the built-ins: open whatever the tool.
      for (final section in session.scope.designerPanels)
        _SectionSpec(
          id: 'module:${section.title}',
          title: section.title.toUpperCase(),
          flex: section.expand ? 1 : null,
          build: (context) => section.build(context, session),
        ),
    ];
    final anyExpanded = sections.any(
      (s) => s.flex != null && controller.isSectionOpen(s.id, groups: s.groups),
    );

    return Material(
      color: EditorTheme.panelBg,
      child: DecoratedBox(
        decoration: const BoxDecoration(),
        child: Column(
          children: [
            _Header(session: session, onClose: onClose),
            for (final spec in sections)
              _place(
                spec,
                controller.isSectionOpen(spec.id, groups: spec.groups),
              ),
            // Everything that fills is closed: keep the align bar at the
            // bottom.
            if (!anyExpanded) const Spacer(),
            AlignBar(session: session, gridSize: gridSize),
          ],
        ),
      ),
    );
  }

  Widget _place(_SectionSpec spec, bool open) {
    final section = _Section(
      key: ValueKey(spec.id),
      title: spec.title,
      open: open,
      expand: open && spec.flex != null,
      onToggle: () => session.controller.setSectionOpen(spec.id, open: !open),
      child: Builder(builder: spec.build),
    );
    return open && spec.flex != null
        ? Expanded(flex: spec.flex!, child: section)
        : section;
  }
}

/// One section of the side panel, before it is built.
class _SectionSpec {
  const _SectionSpec({
    required this.id,
    required this.title,
    required this.build,
    this.groups,
    this.flex,
  });

  final String id;
  final String title;
  final WidgetBuilder build;

  /// The tool groups it opens for; null for all of them.
  final Set<String>? groups;

  /// Its share of the height when open; null to take only what it needs.
  final int? flex;
}

class _Header extends StatelessWidget {
  const _Header({required this.session, required this.onClose});

  final LevelDesignerSession session;
  final VoidCallback onClose;

  static TextStyle get _title => TextStyle(
    color: EditorTheme.textBright,
    fontSize: 12,
    fontWeight: FontWeight.w700,
  );

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 36,
      padding: const EdgeInsets.only(left: 10, right: 4),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: EditorTheme.border)),
      ),
      child: Row(
        children: [
          Icon(Icons.map_outlined, size: 15, color: EditorTheme.primary),
          const SizedBox(width: 8),
          // With only the built-in designer there is nothing to switch to,
          // so the header is a plain title.
          if (session.scope.designers.isEmpty)
            Expanded(child: Text('Level Designer', style: _title))
          else
            Expanded(child: DesignerSwitch(scope: session.scope)),
          EditorIconButton(
            icon: Icons.close,
            tooltip: 'Close Level Designer',
            shortcut: 'F3',
            onTap: onClose,
          ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({
    super.key,
    required this.title,
    required this.child,
    required this.open,
    required this.onToggle,
    this.expand = true,
  });

  final String title;
  final Widget child;

  /// Whether the body shows, or only the title.
  final bool open;

  /// The title was clicked.
  final VoidCallback onToggle;

  /// Whether the body takes the remaining height, or only what it needs.
  final bool expand;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          onTap: onToggle,
          child: Container(
            padding: const EdgeInsets.fromLTRB(4, 5, 10, 4),
            decoration: open
                ? null
                : BoxDecoration(
                    border: Border(
                      bottom: BorderSide(color: EditorTheme.border),
                    ),
                  ),
            child: Row(
              children: [
                Icon(
                  open ? Icons.expand_more : Icons.chevron_right,
                  size: 14,
                  color: EditorTheme.textMuted,
                ),
                const SizedBox(width: 2),
                Text(
                  title,
                  style: TextStyle(
                    color: EditorTheme.textMuted,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8,
                  ),
                ),
              ],
            ),
          ),
        ),
        if (open)
          if (expand) Expanded(child: child) else child,
      ],
    );
  }
}

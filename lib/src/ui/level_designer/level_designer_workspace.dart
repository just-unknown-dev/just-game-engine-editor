import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:just_game_engine/just_game_engine.dart' as jge;
import 'package:just_signals/just_signals.dart';

import 'package:just_editor_core/host.dart';
import 'level_designer_session.dart';
import 'panels/align_bar.dart';
import 'panels/designer_switch.dart';
import 'panels/level_layers_panel.dart';
import 'panels/prefab_palette_panel.dart';
import 'panels/tileset_palette_panel.dart';
import '../level_designer_3d/panels/array_3d_panel.dart';
import '../level_designer_3d/panels/groups_3d_panel.dart';
import '../level_designer_3d/panels/materials_3d_panel.dart';
import '../level_designer_3d/panels/view_3d_panel.dart';

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
    required this.onClose,
  });

  /// The session this chrome drives.
  final LevelDesignerSession session;

  /// Current grid size, owned by the plugin's overlay settings.
  final double gridSize;

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
    // A 2-D level is built on its Level Map, in layers and from tilesets; a
    // 3-D scene has none of those.
    final flat = session.scope.sceneState.editingMode == jge.SceneMode.twoD;
    final sections = <_SectionSpec>[
      _SectionSpec(
        id: 'prefabs',
        title: 'PREFABS',
        groups: _entityTools,
        flex: 3,
        build: (_) => PrefabPalettePanel(session: session),
      ),
      // Open whatever the tool: every tool works on a layer.
      if (flat)
        _SectionSpec(
          id: 'layers',
          title: 'LAYERS',
          flex: 2,
          build: (_) => LevelLayersPanel(session: session),
        ),
      if (flat)
        _SectionSpec(
          id: 'tileset',
          title: 'TILESET',
          groups: _tileTools,
          flex: 3,
          build: (_) => TilesetPalettePanel(session: session),
        ),
      // How a 3-D scene is drawn: open whatever the tool.
      if (!flat)
        _SectionSpec(
          id: 'view3d',
          title: 'VIEW',
          build: (_) => View3DPanel(
            scope: session.scope,
            split: session.splitViews?.call(),
          ),
        ),
      // The project's materials, to paint with: with the shape tools, paint
      // among them.
      if (!flat)
        _SectionSpec(
          id: 'materials3d',
          title: 'MATERIALS',
          groups: const {ToolGroups.shapes},
          build: (_) =>
              Materials3DPanel(scope: session.scope, setTool: session.setTool),
        ),
      // The groups, with their eyes and locks.
      if (!flat)
        _SectionSpec(
          id: 'groups3d',
          title: 'GROUPS',
          groups: _entityTools,
          build: (_) => Groups3DPanel(scope: session.scope),
        ),
      // Copies of the selection in a row, a grid or round a circle.
      if (!flat)
        _SectionSpec(
          id: 'array3d',
          title: 'ARRAY',
          groups: _entityTools,
          build: (_) => Array3DPanel(
            scope: session.scope,
            make: session.onArray3D ?? (_) {},
          ),
        ),
      // What the modules add, under the built-ins: open with their tools,
      // or whatever the tool when they name none.
      for (final section in session.scope.designerPanels)
        _SectionSpec(
          id: 'module:${section.title}',
          title: section.title.toUpperCase(),
          groups: section.groups,
          flex: section.expand ? 1 : null,
          build: (context) => section.build(context, session),
        ),
    ];
    final open = [
      for (final s in sections)
        controller.isSectionOpen(s.id, groups: s.groups),
    ];

    return Material(
      color: EditorTheme.panelBg,
      child: DecoratedBox(
        decoration: const BoxDecoration(),
        child: Column(
          children: [
            _Header(session: session, onClose: onClose),
            // What does not fit scrolls. A section that fills (a palette, a
            // list) gets a share of what the others are likely to leave it,
            // never less than [_minFill]; the rest take what they need.
            Expanded(
              child: LayoutBuilder(
                builder: (context, box) {
                  var flex = 0, others = 0;
                  for (final (i, spec) in sections.indexed) {
                    if (!open[i]) continue;
                    if (spec.flex != null) {
                      flex += spec.flex!;
                    } else {
                      others++;
                    }
                  }
                  final room =
                      box.maxHeight -
                      sections.length * _Section.titleHeight -
                      others * _otherGuess;
                  return EditorScrollbar(
                    builder: (_, scroll) => SingleChildScrollView(
                      controller: scroll,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (final (i, spec) in sections.indexed)
                            _place(
                              spec,
                              open[i],
                              fill: open[i] && spec.flex != null
                                  ? math.max(_minFill, room * spec.flex! / flex)
                                  : null,
                            ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            if (flat) AlignBar(session: session, gridSize: gridSize),
          ],
        ),
      ),
    );
  }

  /// The least a section that fills is given, its title aside.
  static const double _minFill = 220;

  /// About how tall a section that does not fill is, open.
  static const double _otherGuess = 160;

  Widget _place(_SectionSpec spec, bool open, {double? fill}) {
    final section = _Section(
      key: ValueKey(spec.id),
      title: spec.title,
      open: open,
      expand: fill != null,
      onToggle: () => session.controller.setSectionOpen(spec.id, open: !open),
      child: Builder(builder: spec.build),
    );
    return fill == null
        ? section
        : SizedBox(height: fill + _Section.titleHeight, child: section);
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
          Icon(
            session.scope.sceneState.editingMode == jge.SceneMode.twoD
                ? Icons.map_outlined
                : Icons.view_in_ar,
            size: 15,
            color: EditorTheme.primary,
          ),
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

  /// How tall the title row is.
  static const double titleHeight = 24;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          onTap: onToggle,
          child: Container(
            height: titleHeight,
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

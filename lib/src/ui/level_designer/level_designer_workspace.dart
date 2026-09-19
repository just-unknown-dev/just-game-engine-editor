import 'package:flutter/material.dart';
import 'package:just_signals/just_signals.dart';

import '../../core/constants/editor_constants.dart';
import 'level_designer_session.dart';
import 'panels/align_bar.dart';
import 'panels/designer_status_bar.dart';
import 'panels/designer_switch.dart';
import 'panels/layers_panel.dart';
import 'panels/prefab_palette_panel.dart';
import 'panels/tool_palette.dart';
import 'panels/transform_panel.dart';

/// The Level Designer's chrome: tool strip on the left, prefab and layer
/// panels on the right, status strip along the bottom.
///
/// Deliberately *not* a container for the viewport. The game canvas is painted
/// by the engine underneath the whole overlay, and the designer's own overlays
/// go on that same canvas through the plugin's render hook. This widget only
/// adds chrome around the edges, so there is one source of truth for what the
/// viewport shows and no chance of the two drifting apart.
class LevelDesignerWorkspace extends StatelessWidget {
  const LevelDesignerWorkspace({
    super.key,
    required this.session,
    required this.gridSize,
    required this.onGridSizeChanged,
    required this.onClose,
    this.rightPanelWidth = 260,
  });

  /// The session this chrome drives.
  final LevelDesignerSession session;

  /// Current grid size, owned by the plugin's overlay settings.
  final double gridSize;

  /// Propagates a grid-size change back to the plugin.
  final ValueChanged<double> onGridSizeChanged;

  /// Closes the designer.
  final VoidCallback onClose;

  /// Width of the prefab and layers column.
  final double rightPanelWidth;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        ToolPalette(session: session),
        // The viewport shows through here: the designer adds chrome at the
        // edges and never covers the canvas.
        const Expanded(child: IgnorePointer(child: SizedBox.expand())),
        SizedBox(
          width: rightPanelWidth,
          child: _DesignerSidePanel(
            session: session,
            gridSize: gridSize,
            onClose: onClose,
          ),
        ),
      ],
    );
  }

  /// The bottom status strip, positioned by the caller so it can span the full
  /// width beneath both the viewport and the side panel.
  Widget buildStatusBar() => DesignerStatusBar(
    session: session,
    gridSize: gridSize,
    onGridSizeChanged: onGridSizeChanged,
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
  Widget build(BuildContext context) => SignalBuilder<String?>(
    // Everything below follows the designer in use.
    signal: session.scope.activeDesigner,
    builder: (context, _, _) => _buildPanel(context),
  );

  Widget _buildPanel(BuildContext context) {
    return Material(
      color: EditorTheme.panelBg,
      child: DecoratedBox(
        decoration: const BoxDecoration(
          border: Border(left: BorderSide(color: EditorTheme.border)),
        ),
        child: Column(
          children: [
            _Header(session: session, onClose: onClose),
            Expanded(
              flex: 3,
              child: _Section(
                title: 'PREFABS',
                child: PrefabPalettePanel(session: session),
              ),
            ),
            _Section(
              title: 'TRANSFORM',
              expand: false,
              child: TransformPanel(session: session),
            ),
            Expanded(
              flex: 2,
              child: _Section(
                title: 'LAYERS',
                child: LayersPanel(session: session),
              ),
            ),
            // What the modules add, under the built-ins.
            for (final section in session.scope.designerPanels)
              if (section.expand)
                Expanded(
                  child: _Section(
                    title: section.title.toUpperCase(),
                    child: Builder(
                      builder: (context) => section.build(context, session),
                    ),
                  ),
                )
              else
                _Section(
                  title: section.title.toUpperCase(),
                  expand: false,
                  child: Builder(
                    builder: (context) => section.build(context, session),
                  ),
                ),
            AlignBar(session: session, gridSize: gridSize),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.session, required this.onClose});

  final LevelDesignerSession session;
  final VoidCallback onClose;

  static const TextStyle _title = TextStyle(
    color: EditorTheme.textBright,
    fontSize: 12,
    fontWeight: FontWeight.w700,
  );

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: EditorTheme.border)),
      ),
      child: Row(
        children: [
          const Icon(Icons.map_outlined, size: 15, color: EditorTheme.primary),
          const SizedBox(width: 8),
          // With only the built-in designer there is nothing to switch to,
          // so the header is a plain title.
          if (session.scope.designers.isEmpty)
            const Expanded(child: Text('Level Designer', style: _title))
          else
            Expanded(child: DesignerSwitch(scope: session.scope)),
          Tooltip(
            message: 'Close Level Designer',
            child: InkWell(
              onTap: onClose,
              borderRadius: BorderRadius.circular(4),
              child: const Padding(
                padding: EdgeInsets.all(4),
                child: Icon(
                  Icons.close,
                  size: 14,
                  color: EditorTheme.textMuted,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({
    required this.title,
    required this.child,
    this.expand = true,
  });

  final String title;
  final Widget child;

  /// Whether the body takes the remaining height, or only what it needs.
  final bool expand;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(10, 6, 10, 4),
          alignment: Alignment.centerLeft,
          child: Text(
            title,
            style: const TextStyle(
              color: EditorTheme.textMuted,
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
            ),
          ),
        ),
        if (expand) Expanded(child: child) else child,
      ],
    );
  }
}

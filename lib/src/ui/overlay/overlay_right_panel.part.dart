part of 'editor_overlay.dart';

class _EditorRightPanel extends StatelessWidget {
  const _EditorRightPanel({required this.plugin, required this.settings});

  static const double defaultPanelWidth = 360;
  static const double minPanelWidth = 280;
  static const double maxPanelWidth = 640;

  final JustGameEditorPlugin plugin;
  final _OverlayUiSettings settings;

  void _onWidthResize(double dx) {
    // Anchored to the screen's right edge, so dragging left (negative dx)
    // grows the panel — mirrors _onWidthResize's counterparts for the
    // bottom-anchored dock panels, which grow on drag-up (negative dy).
    _rightPanelWidthSignal.value = (_rightPanelWidthSignal.value - dx).clamp(
      minPanelWidth,
      maxPanelWidth,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: <Widget>[
        Material(
          color: EditorTheme.panelBg,
          child: SafeArea(
            child: DecoratedBox(
              decoration: const BoxDecoration(
                border: Border(
                  left: BorderSide(color: EditorTheme.border, width: 1),
                ),
              ),
              child: ListenableBuilder(
                listenable: plugin.sceneState,
                builder: (context, _) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      _HeaderBar(plugin: plugin, settings: settings),
                      const Divider(height: 1, color: EditorTheme.border),
                      if (!plugin.sceneState.hasScene)
                        Expanded(
                          child: ScenePickerPanel(
                            onSceneSelected: (name) => plugin.openScene(name),
                            sceneManager: plugin.sceneManager,
                          ),
                        )
                      else ...<Widget>[
                        _ResizableSceneTreeSection(plugin: plugin),
                        const Divider(height: 1, color: EditorTheme.border),
                        Expanded(
                          child: EntityInspectorPanel(
                            sceneState: plugin.sceneState,
                            world: plugin.engine.world,
                            onDetachFromParent: plugin.detachFromParent,
                            onGroupSelection: plugin.createGroup,
                          ),
                        ),
                        _SaveFooter(plugin: plugin, settings: settings),
                      ],
                    ],
                  );
                },
              ),
            ),
          ),
        ),
        Positioned(
          left: 0,
          top: 0,
          bottom: 0,
          child: _VerticalPanelResizeHandle(onDrag: _onWidthResize),
        ),
      ],
    );
  }
}

/// Drag handle for [_EditorRightPanel]'s width — mirrors [_PanelResizeHandle]
/// (defined in overlay_dock_logs_panel.part.dart for the bottom dock panels)
/// but drags horizontally instead of vertically.
class _VerticalPanelResizeHandle extends StatelessWidget {
  const _VerticalPanelResizeHandle({required this.onDrag});

  final ValueChanged<double> onDrag;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.resizeColumn,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragUpdate: (details) => onDrag(details.delta.dx),
        child: Container(
          width: 6,
          alignment: Alignment.center,
          color: Colors.transparent,
          child: Container(
            width: 1,
            color: Colors.white.withValues(alpha: 0.08),
          ),
        ),
      ),
    );
  }
}

/// The scene-tree section at the top of [_EditorRightPanel], resizable via a
/// drag handle below it (grows/shrinks the tree; [EntityInspectorPanel]
/// below takes whatever's left via [Expanded]).
class _ResizableSceneTreeSection extends StatefulWidget {
  const _ResizableSceneTreeSection({required this.plugin});

  final JustGameEditorPlugin plugin;

  @override
  State<_ResizableSceneTreeSection> createState() =>
      _ResizableSceneTreeSectionState();
}

class _ResizableSceneTreeSectionState
    extends State<_ResizableSceneTreeSection> {
  double _height = 220;

  void _onResize(double dy, double maxHeight) {
    setState(() {
      // Anchored at the top with the handle below it, so dragging down
      // (positive dy) grows the section directly (no sign flip needed).
      final maxAllowed = math.max(120.0, maxHeight - 160.0);
      _height = (_height + dy).clamp(120.0, maxAllowed);
    });
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // The surrounding Column gives this (non-Expanded) child loose/
        // unbounded height constraints, so fall back to the screen height
        // for the resize clamp when that happens.
        final maxHeight = constraints.hasBoundedHeight
            ? constraints.maxHeight
            : MediaQuery.sizeOf(context).height;
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            SizedBox(
              height: _height,
              child: SceneTreePanel(
                sceneState: widget.plugin.sceneState,
                world: widget.plugin.engine.world,
                onCreateEntity: widget.plugin.createEntity,
                onCreateGroup: widget.plugin.createGroup,
                onCreateGroupFrom: (entity) =>
                    widget.plugin.createGroup(children: [entity]),
                onDeleteEntity: widget.plugin.deleteEntity,
                onCopyEntity: widget.plugin.copyEntity,
                onPasteEntity: widget.plugin.pasteEntity,
                onReparentEntity: widget.plugin.reparentEntity,
              ),
            ),
            _PanelResizeHandle(
              onDrag: (dy) => _onResize(dy, maxHeight),
            ),
          ],
        );
      },
    );
  }
}

class _HeaderBar extends StatelessWidget {
  const _HeaderBar({required this.plugin, required this.settings});

  final JustGameEditorPlugin plugin;
  final _OverlayUiSettings settings;

  @override
  Widget build(BuildContext context) {
    final sceneName = plugin.sceneState.activeScene?.name;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        children: <Widget>[
          if (sceneName != null) ...<Widget>[
            Tooltip(
              message: 'Back to scene list',
              child: IconButton(
                onPressed: plugin.sceneState.closeScene,
                icon: const Icon(Icons.arrow_back_ios_new_rounded),
                iconSize: 14,
                color: settings.themeColor,
                splashRadius: 16,
                padding: const EdgeInsets.all(4),
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
              ),
            ),
            const SizedBox(width: 4),
          ] else ...<Widget>[
            const Icon(
              Icons.tune_rounded,
              color: EditorTheme.primary,
              size: 20,
            ),
            const SizedBox(width: 8),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'Just Runtime Editor',
                  style: TextStyle(
                    fontSize: 13 * settings.effectiveTextScale,
                    fontWeight: FontWeight.w700,
                    color: EditorTheme.textPrimary,
                  ),
                ),
                if (sceneName != null)
                  Text(
                    sceneName,
                    style: TextStyle(
                      fontSize: 10 * settings.effectiveTextScale,
                      color: settings.themeColor.withValues(alpha: 0.8),
                    ),
                  ),
              ],
            ),
          ),
          _Badge(label: 'JIT', accent: settings.themeColor, settings: settings),
        ],
      ),
    );
  }
}

class _SaveFooter extends StatelessWidget {
  const _SaveFooter({required this.plugin, required this.settings});

  final JustGameEditorPlugin plugin;
  final _OverlayUiSettings settings;

  @override
  Widget build(BuildContext context) {
    final isDirty = plugin.sceneState.isDirty;

    return DecoratedBox(
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: EditorTheme.border)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: <Widget>[
            if (isDirty)
              Padding(
                padding: EdgeInsets.only(right: 8),
                child: _Badge(
                  label: 'UNSAVED',
                  accent: EditorTheme.warning,
                  settings: settings,
                ),
              ),
            const Spacer(),
            SizedBox(
              height: 32,
              child: ElevatedButton.icon(
                onPressed: isDirty ? () => plugin.saveScene() : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: EditorTheme.buttonBg,
                  disabledBackgroundColor: EditorTheme.surfaceBg,
                  foregroundColor: settings.themeColor,
                  disabledForegroundColor: EditorTheme.border,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(settings.cornerRadius),
                  ),
                ),
                icon: const Icon(Icons.save_rounded, size: 14),
                label: Text(
                  'Save',
                  style: TextStyle(
                    fontSize: 12 * settings.effectiveTextScale,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

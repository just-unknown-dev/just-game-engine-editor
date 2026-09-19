import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:just_game_engine/just_game_engine.dart' show EntityId;
import 'package:just_signals/just_signals.dart';

import '../../panels/entity_inspector_panel.dart';
import '../../panels/scene_picker_panel.dart';
import '../../panels/scene_tree_panel.dart';
import '../../../core/constants/editor_constants.dart';
import '../../../core/plugin/editor_plugin.dart';
import '../docks/logs_dock.dart';
import '../settings/overlay_ui_settings.dart';
import '../shared/shared_widgets.dart';

class EditorRightPanel extends StatelessWidget {
  const EditorRightPanel({
    super.key,
    required this.plugin,
    required this.settings,
  });

  final JustGameEditorPlugin plugin;
  final OverlayUiSettings settings;

  void _onWidthResize(double dx) {
    // Anchored to the screen's right edge, so dragging left (negative dx)
    // grows the panel — mirrors _onWidthResize's counterparts for the
    // bottom-anchored dock panels, which grow on drag-up (negative dy).
    plugin.scope.chrome.rightPanelWidth.value =
        (plugin.scope.chrome.rightPanelWidth.value - dx).clamp(
          OverlayLayout.rightPanelMinWidth,
          OverlayLayout.rightPanelMaxWidth,
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
              child: SignalConsumer(
                signals: [
                  plugin.sceneState.activeScene,
                  plugin.sceneState.isDirty,
                  plugin.designer,
                ],
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
                            scope: plugin.scope,
                            sceneState: plugin.sceneState,
                            world: plugin.engine.world,
                            onDetachFromParent:
                                plugin.entities.detachFromParent,
                            onGroupSelection: plugin.entities.createGroup,
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

/// Drag handle for [EditorRightPanel]'s width — mirrors [PanelResizeHandle]
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

/// The scene-tree section at the top of [EditorRightPanel], resizable via a
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
            SizedBox(height: _height, child: _sceneTree(widget.plugin)),
            PanelResizeHandle(onDrag: (dy) => _onResize(dy, maxHeight)),
          ],
        );
      },
    );
  }
}

class _HeaderBar extends StatelessWidget {
  const _HeaderBar({required this.plugin, required this.settings});

  final JustGameEditorPlugin plugin;
  final OverlayUiSettings settings;

  @override
  Widget build(BuildContext context) {
    final sceneName = plugin.sceneState.activeScene.value?.name;

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
          OverlayBadge(
            label: 'JIT',
            accent: settings.themeColor,
            settings: settings,
          ),
        ],
      ),
    );
  }
}

class _SaveFooter extends StatelessWidget {
  const _SaveFooter({required this.plugin, required this.settings});

  final JustGameEditorPlugin plugin;
  final OverlayUiSettings settings;

  @override
  Widget build(BuildContext context) {
    final isDirty = plugin.sceneState.isDirty.value;

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
                child: OverlayBadge(
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

/// The scene tree, with per-entity hide and lock while the Level Designer is
/// open — rebuilt whenever either changes, so the row icons stay current.
Widget _sceneTree(JustGameEditorPlugin plugin) {
  Widget tree(EntityViewToggles? toggles) => SceneTreePanel(
    scope: plugin.scope,
    sceneState: plugin.sceneState,
    world: plugin.engine.world,
    viewToggles: toggles,
    onCreateEntity: plugin.entities.createEntity,
    onCreateGroup: plugin.entities.createGroup,
    onCreateGroupFrom: (entity) =>
        plugin.entities.createGroup(children: [entity]),
    onDeleteEntity: plugin.entities.deleteEntity,
    onCopyEntity: plugin.entities.copyEntity,
    onPasteEntity: plugin.entities.pasteEntity,
    onReparentEntity: plugin.entities.reparentEntity,
  );

  final designer = plugin.designer.value;
  if (designer == null) return tree(null);
  final c = designer.controller;
  return SignalBuilder2<Set<EntityId>, Set<EntityId>>(
    signal1: c.hiddenEntities,
    signal2: c.lockedEntities,
    builder: (context, hidden, locked, _) => tree(
      EntityViewToggles(
        isHidden: (e) => hidden.contains(e.id),
        isLocked: (e) => locked.contains(e.id),
        onToggleHidden: (e) =>
            c.setEntitiesHidden([e.id], hidden: !hidden.contains(e.id)),
        onToggleLocked: (e) =>
            c.setEntitiesLocked([e.id], locked: !locked.contains(e.id)),
      ),
    ),
  );
}

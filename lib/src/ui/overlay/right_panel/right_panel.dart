import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:just_game_engine/just_game_engine.dart' show EntityId;
import 'package:just_signals/just_signals.dart';

import '../../panels/entity_inspector_panel.dart';
import '../../panels/scene_picker_panel.dart';
import '../../scene_tree/scene_tree_panel.dart';
import '../../level_designer/level_designer_workspace.dart';
import 'package:just_editor_core/host.dart';
import '../../../core/plugin/editor_plugin.dart';
import '../docks/panel_parts.dart';

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
              decoration: BoxDecoration(
                border: Border(
                  left: BorderSide(color: EditorTheme.border, width: 1),
                ),
              ),
              child: SignalConsumer(
                signals: [
                  plugin.sceneState.activeScene,
                  plugin.sceneState.isDirty,
                  plugin.designer,
                  plugin.gridSize,
                  plugin.scope.chrome.rightPanelTab,
                ],
                builder: (context, _) {
                  final designer = plugin.designer.value;
                  final tab = plugin.scope.chrome.rightPanelTab.value;
                  final showLevel =
                      designer != null && tab == EditorChromeState.levelTab;
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      _HeaderBar(plugin: plugin, settings: settings),
                      Divider(height: 1, color: EditorTheme.border),
                      if (!plugin.sceneState.hasScene)
                        Expanded(
                          child: ScenePickerPanel(
                            onSceneSelected: (name) => plugin.openScene(name),
                            sceneManager: plugin.sceneManager,
                            prefs: plugin.scope.prefs,
                          ),
                        )
                      else ...<Widget>[
                        // While designing: the level's panel is a tab here,
                        // beside the tree and inspector, not a second panel
                        // taking the level's width.
                        if (designer != null)
                          _PanelTabs(
                            selected: tab,
                            onSelect: (t) =>
                                plugin.scope.chrome.rightPanelTab.value = t,
                          ),
                        if (showLevel)
                          Expanded(
                            child: LevelDesignerWorkspace(
                              session: designer,
                              gridSize: plugin.gridSize.value,
                              onGridSizeChanged: plugin.setGridSize,
                              onClose: plugin.closeLevelDesigner,
                            ),
                          )
                        else
                          // The tree and the inspector share what is left:
                          // a short window takes it from the tree.
                          Expanded(
                            child: LayoutBuilder(
                              builder: (context, box) => Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  _ResizableSceneTreeSection(
                                    plugin: plugin,
                                    room: box.maxHeight,
                                  ),
                                  Divider(height: 1, color: EditorTheme.border),
                                  Expanded(
                                    child: EntityInspectorPanel(
                                      scope: plugin.scope,
                                      sceneState: plugin.sceneState,
                                      world: plugin.engine.world,
                                      onDetachFromParent:
                                          plugin.entities.detachFromParent,
                                      onGroupSelection:
                                          plugin.entities.createGroup,
                                      isLevelDesignerOpen: designer != null,
                                    ),
                                  ),
                                ],
                              ),
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
          child: _VerticalPanelResizeHandle(
            onDrag: _onWidthResize,
            onDragEnd: () => plugin.scope.prefs.set(
              EditorChromeState.rightPanelWidthPref,
              plugin.scope.chrome.rightPanelWidth.value,
            ),
          ),
        ),
      ],
    );
  }
}

/// Inspector | Level: which half of the editor the right panel shows while
/// the Level Designer is open.
class _PanelTabs extends StatelessWidget {
  const _PanelTabs({required this.selected, required this.onSelect});

  final String selected;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) => Container(
    height: EditorMetrics.minTarget + 8,
    decoration: BoxDecoration(
      color: EditorTheme.surfaceDarker,
      border: Border(bottom: BorderSide(color: EditorTheme.border)),
    ),
    child: Row(
      children: [
        for (final (id, label, icon, tip) in const [
          (
            EditorChromeState.inspectorTab,
            'Inspector',
            Icons.account_tree_outlined,
            'The scene tree and what the selection is made of',
          ),
          (
            EditorChromeState.levelTab,
            'Level',
            Icons.map_outlined,
            'Prefabs, layers and tiles to build the level with',
          ),
        ])
          Expanded(
            child: Tooltip(
              message: tip,
              child: Semantics(
                selected: id == selected,
                button: true,
                child: InkWell(
                  onTap: () => onSelect(id),
                  child: Container(
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: id == selected
                          ? EditorTheme.accent.withValues(alpha: 0.10)
                          : null,
                      border: Border(
                        bottom: BorderSide(
                          width: 2,
                          color: id == selected
                              ? EditorTheme.accent
                              : Colors.transparent,
                        ),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          icon,
                          size: 14,
                          color: id == selected
                              ? EditorTheme.accent
                              : EditorTheme.textMuted,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          label,
                          style: TextStyle(
                            color: id == selected
                                ? EditorTheme.textPrimary
                                : EditorTheme.textSecondary,
                            fontSize: 11,
                            fontWeight: id == selected
                                ? FontWeight.w600
                                : FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    ),
  );
}

/// Drag handle for [EditorRightPanel]'s width — [PanelResizeHandle], the
/// docks' and the scene tree's, turned on its side.
class _VerticalPanelResizeHandle extends StatelessWidget {
  const _VerticalPanelResizeHandle({required this.onDrag, this.onDragEnd});

  final ValueChanged<double> onDrag;
  final VoidCallback? onDragEnd;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.resizeColumn,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragUpdate: (details) => onDrag(details.delta.dx),
        onHorizontalDragEnd: (_) => onDragEnd?.call(),
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
  const _ResizableSceneTreeSection({required this.plugin, required this.room});

  final JustGameEditorPlugin plugin;

  /// What the tree shares with the inspector under it.
  final double room;

  @override
  State<_ResizableSceneTreeSection> createState() =>
      _ResizableSceneTreeSectionState();
}

class _ResizableSceneTreeSectionState
    extends State<_ResizableSceneTreeSection> {
  // The least a drag leaves the tree, and the inspector under it.
  static const double _leastTree = 120;
  static const double _leastInspector = 120;

  // Where it was left last time: the tree's height whenever the window has
  // room for it.
  late double _height = widget.plugin.scope.prefs.get(
    EditorChromeState.sceneTreeHeightPref,
  );

  // The tallest the tree can be with the inspector still there: on a short
  // window less than it was left, and back to that as the window grows.
  double get _most => math.max(
    0.0,
    widget.room - _leastInspector - PanelResizeHandle.height - 1,
  );

  void _onResize(double dy) {
    final most = _most;
    setState(() {
      // Anchored at the top with the handle below it, so dragging down
      // (positive dy) grows the section directly (no sign flip needed).
      _height = (math.min(_height, most) + dy).clamp(
        math.min(_leastTree, most),
        most,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        SizedBox(
          height: math.min(_height, _most),
          child: _sceneTree(widget.plugin),
        ),
        PanelResizeHandle(
          onDrag: _onResize,
          onDragEnd: () => widget.plugin.scope.prefs.set(
            EditorChromeState.sceneTreeHeightPref,
            _height,
          ),
        ),
      ],
    );
  }
}

/// Closes the open scene, asking first when it has unsaved changes — Save,
/// Don't save or Cancel — or, when the settings say so, every time; and
/// ends a play-test running in it.
Future<void> closeSceneAsking(
  BuildContext context,
  JustGameEditorPlugin plugin,
) async {
  final state = plugin.sceneState;
  final scene = state.activeScene.value;
  if (scene == null) return;
  if (state.isDirty.value) {
    final messenger = EditorMessenger.of(context);
    final choice = await askToSaveChanges(
      context,
      title: 'Save changes to ${scene.name}?',
      message: 'Closing the scene loses what has not been saved.',
    );
    if (choice == null) return;
    if (choice == UnsavedChoice.save) {
      try {
        await plugin.saveScene();
      } catch (error) {
        messenger.showSnackBar(
          EditorSnackBarEntry(
            type: EditorSnackBarType.error,
            title: 'Could not save ${scene.name}',
            message: '$error — the scene stays open.',
          ),
        );
        return;
      }
    }
  } else if (plugin.scope.prefs.settings.value.closePrompt ==
      ClosePrompt.always) {
    final close = await showEditorConfirm(
      context,
      title: 'Close ${scene.name}?',
      message: 'Everything in it is saved.',
      confirmLabel: 'Close',
      danger: false,
    );
    if (!close) return;
  }
  if (plugin.playController.isRunning) plugin.playController.stop();
  state.closeScene();
}

/// The top of the right panel: the scene open — its name, whether it has
/// unsaved changes, the way back to the scene list — or, with none open,
/// the scene list's title.
class _HeaderBar extends StatelessWidget {
  const _HeaderBar({required this.plugin, required this.settings});

  final JustGameEditorPlugin plugin;
  final OverlayUiSettings settings;

  @override
  Widget build(BuildContext context) {
    final sceneName = plugin.sceneState.activeScene.value?.name;
    final dirty = sceneName != null && plugin.sceneState.isDirty.value;

    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 12, 8),
      child: Row(
        children: <Widget>[
          if (sceneName != null)
            EditorIconButton(
              icon: Icons.arrow_back_rounded,
              tooltip: dirty
                  ? 'Close the scene (asks about the unsaved changes)'
                  : 'Close the scene: back to the scene list',
              activeColor: EditorTheme.accent,
              onTap: () => closeSceneAsking(context, plugin),
            )
          else
            SizedBox.square(
              dimension: EditorMetrics.controlSm,
              child: Icon(
                Icons.map_outlined,
                color: EditorTheme.accent,
                size: 16,
              ),
            ),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        sceneName ?? 'Scenes',
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: EditorMetrics.fontTitle,
                          fontWeight: FontWeight.w700,
                          color: EditorTheme.textPrimary,
                        ),
                      ),
                    ),
                    if (dirty) ...[
                      const SizedBox(width: 6),
                      Tooltip(
                        message: 'Unsaved changes',
                        child: Container(
                          width: 7,
                          height: 7,
                          decoration: BoxDecoration(
                            color: EditorTheme.warning,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                Text(
                  'Just Runtime Editor',
                  style: TextStyle(
                    fontSize: EditorMetrics.fontLabel,
                    color: EditorTheme.textMuted,
                  ),
                ),
              ],
            ),
          ),
          Tooltip(
            message:
                'The editor runs in debug builds only: a release build of '
                'the game leaves it out.',
            child: EditorBadge(label: 'DEBUG', accent: EditorTheme.textMuted),
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
    final keys = plugin.scope.commands.bindingsFor('editor.save');
    final shortcut = keys.isEmpty ? null : keys.first.shortcut;

    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(
          color: isDirty ? EditorTheme.warning : EditorTheme.border,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: <Widget>[
            // Always says where the scene stands, not only when it is dirty.
            if (isDirty)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.file_copy, size: 12, color: EditorTheme.warning),
                  const SizedBox(width: 4),
                  Text(
                    'UNSAVED',
                    style: TextStyle(color: EditorTheme.warning, fontSize: 10),
                  ),
                ],
              )
            else
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.check_rounded,
                    size: 12,
                    color: EditorTheme.textMuted,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'Saved',
                    style: TextStyle(
                      color: EditorTheme.textMuted,
                      fontSize: 10,
                    ),
                  ),
                ],
              ),
            const Spacer(),
            _SaveButton(
              enabled: isDirty,
              shortcut: shortcut,
              settings: settings,
              onPressed: plugin.saveScene,
            ),
          ],
        ),
      ),
    );
  }
}

/// Save, at the height of the editor's other controls: tinted with the theme
/// colour while there is something to save, and still legible when there is
/// not.
class _SaveButton extends StatelessWidget {
  const _SaveButton({
    required this.enabled,
    required this.shortcut,
    required this.settings,
    required this.onPressed,
  });

  final bool enabled;
  final String? shortcut;
  final OverlayUiSettings settings;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final accent = EditorTheme.accent;
    final foreground = enabled
        ? EditorTheme.textBright
        : EditorTheme.textMuted.withValues(alpha: 0.6);
    final radius = BorderRadius.circular(EditorMetrics.radiusSm);
    return Tooltip(
      message: enabled
          ? 'Save scene${shortcut == null ? '' : '  ($shortcut)'}'
          : 'Nothing to save',
      child: Material(
        color: enabled ? accent.withValues(alpha: 0.18) : Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: radius,
          side: BorderSide(
            color: enabled ? accent.withValues(alpha: 0.7) : EditorTheme.border,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: enabled ? onPressed : null,
          hoverColor: accent.withValues(alpha: 0.14),
          child: SizedBox(
            height: 28,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.save_rounded,
                    size: 13,
                    color: enabled ? accent : foreground,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'Save',
                    style: TextStyle(
                      color: foreground,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (shortcut != null) ...[
                    const SizedBox(width: 8),
                    Text(
                      shortcut!,
                      style: TextStyle(
                        color: foreground.withValues(alpha: 0.55),
                        fontSize: 9,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The scene tree. Hide and lock are the scope's, so the eye and the
/// padlock work whether or not the Level Designer is open.
Widget _sceneTree(JustGameEditorPlugin plugin) {
  final view = plugin.scope.view;
  return SignalBuilder3<Set<EntityId>, Set<EntityId>, EditorPlayState>(
    signal1: view.hidden,
    signal2: view.locked,
    // While the game runs, what it spawned is listed apart from what the
    // scene says — and the divider has to appear the moment play starts.
    signal3: plugin.playController.state,
    builder: (context, hidden, locked, play, _) => SceneTreePanel(
      scope: plugin.scope,
      entities: plugin.entities,
      onFocusEntity: plugin.focusOn,
      authored: plugin.playController.snapshot?.existing,
      isHidden: (e) => hidden.contains(e.id),
      isLocked: (e) => locked.contains(e.id),
      onToggleHidden: (e) => view.toggleHidden(e.id),
      onToggleLocked: (e) => view.toggleLocked(e.id),
    ),
  );
}

import '../../timeline/timeline_session.dart';
import 'dart:math' as math;

import 'package:flutter/widgets.dart' show Offset;
import 'package:just_game_engine/just_game_engine.dart' as jge;

import 'package:just_editor_core/host.dart';

import 'editor_command_context.dart';
import '../../../core/scope/editor_scope_services.dart';
import '../../../core/prefabs/prefab_instances.dart';

/// What the designer and the editor can do from the keyboard out of the box.
///
/// Each is a command a module may rebind, disable by binding its chord to
/// something else, or call by id from its own UI. The default chords are in
/// `BuiltInBindings`.
abstract final class BuiltInCommands {
  static List<DesignerCommand> get all => [
    for (final (id, label, delta) in [
      ('designer.nudgeLeft', 'Nudge left', const Offset(-1, 0)),
      ('designer.nudgeRight', 'Nudge right', const Offset(1, 0)),
      ('designer.nudgeUp', 'Nudge up', const Offset(0, -1)),
      ('designer.nudgeDown', 'Nudge down', const Offset(0, 1)),
    ])
      DesignerCommand(
        id: id,
        label: label,
        repeats: true,
        dimensions: jge.Dimensions.twoD,
        // Shift nudges one unit; otherwise the settings' distance, or the
        // step moving snaps in.
        run: (c) {
          final settings = c.scope.prefs.settings.value;
          final set = settings.nudgeDistance;
          final snap = settings.moveStepFor(c.gridSize);
          final step = c.modifiers.shift
              ? 1.0
              : set > 0
              ? set
              : (snap > 0 ? snap : 1.0);
          c.designer!.ops.nudge(c.designer!.selectionEntities(), delta * step);
        },
      ),
    _d2(
      'designer.rotateClockwise',
      'Rotate a quarter turn',
      (c) => c.designer!.ops.rotateQuarter(c.designer!.selectionEntities(), 1),
    ),
    _d2(
      'designer.rotateCounter',
      'Rotate a quarter turn back',
      (c) => c.designer!.ops.rotateQuarter(c.designer!.selectionEntities(), -1),
    ),
    _d2(
      'designer.flipHorizontal',
      'Flip horizontally',
      (c) => c.designer!.ops.flip(
        c.designer!.selectionEntities(),
        horizontal: true,
      ),
    ),
    _d2(
      'designer.flipVertical',
      'Flip vertically',
      (c) => c.designer!.ops.flip(
        c.designer!.selectionEntities(),
        horizontal: false,
      ),
    ),
    _d2(
      'designer.frameSelection',
      'Frame the selection',
      (c) => c.designer!.frameSelection(),
    ),
    _d2(
      'designer.frameAll',
      'Frame everything',
      (c) => c.designer!.frameAll(),
    ),
    _d(
      'designer.hide',
      'Hide the selection',
      (c) => c.designer!.hideSelection(),
    ),
    _d(
      'designer.isolate',
      'Isolate the selection',
      (c) => c.designer!.isolateSelection(),
    ),
    _d('designer.unhideAll', 'Show everything', (c) => c.designer!.unhideAll()),
    _d(
      'designer.lock',
      'Lock the selection',
      (c) => c.designer!.lockSelection(),
    ),
    _d(
      'designer.unlockAll',
      'Unlock everything',
      (c) => c.designer!.unlockAll(),
    ),
    _d2(
      'designer.replace',
      'Replace with the active prefab',
      (c) => c.designer!.replaceSelection(),
    ),
    _d('designer.selectAll', 'Select all', (c) => c.designer!.selectAll()),
    _d2('designer.brushSmaller', 'Smaller brush', (c) {
      final brush = c.designer!.controller.brushSize;
      brush.value = c.scope.config.smallerBrush(brush.value);
    }),
    _d2('designer.brushLarger', 'Larger brush', (c) {
      final brush = c.designer!.controller.brushSize;
      brush.value = c.scope.config.largerBrush(brush.value);
    }),
    _d('designer.cancel', 'Cancel the gesture, or clear the selection', (c) {
      final s = c.designer!;
      s.hasActiveGesture ? s.onPointerCancel() : s.sceneState.clearSelection();
    }),
    // The 3-D designer's working plane: up and down a move step (ten with
    // Shift), the next way round, to the selection.
    for (final (id, label, sign) in const [
      ('designer.plane.raise', 'Working plane up a step', 1.0),
      ('designer.plane.lower', 'Working plane down a step', -1.0),
    ])
      DesignerCommand(
        id: id,
        label: label,
        repeats: true,
        dimensions: jge.Dimensions.threeD,
        run: (c) {
          final step = c.scope.sceneState.moveStep3D;
          final by = (step > 0 ? step : 1.0) * (c.modifiers.shift ? 10 : 1);
          final state = c.scope.designer3D..followSelection.value = false;
          state.raise(sign * by);
          c.designer?.controller.setStatus(_planeStatus(state.plane));
        },
      ),
    DesignerCommand(
      id: 'designer.dropToGround',
      label: 'Drop to the ground',
      dimensions: jge.Dimensions.threeD,
      scope: CommandScope.editor,
      isEnabled: (c) => c.plugin != null,
      run: (c) {
        final moved = c.plugin!.dropSelectionToGround();
        c.designer?.controller.setStatus(
          moved == 0 ? 'Nothing to drop' : 'Dropped $moved to the ground',
        );
      },
    ),
    DesignerCommand(
      id: 'designer.array3D',
      label: 'Array the selection (as set in ARRAY)',
      dimensions: jge.Dimensions.threeD,
      scope: CommandScope.editor,
      isEnabled: (c) => c.plugin != null,
      run: (c) => c.plugin!.arraySelection3D(c.scope.designer3D.array.value),
    ),
    DesignerCommand(
      id: 'designer.selectSimilar',
      label: 'Select everything like the selection',
      dimensions: jge.Dimensions.threeD,
      run: (c) => c.designer!.selectSimilar(),
    ),
    DesignerCommand(
      id: 'designer.plane.cycle',
      label: 'Working plane: ground, front, side',
      dimensions: jge.Dimensions.threeD,
      run: (c) {
        final state = c.scope.designer3D..cycleAxis();
        final selection = c.designer?.selectionEntities() ?? const [];
        // Turned, it goes through what is selected, else the view's focus.
        state.planeOffset.value = selection.isEmpty
            ? state.plane.through(c.scope.editorView.focus).offset
            : state.planeAt(selection).offset;
        c.designer?.controller.setStatus(_planeStatus(state.plane));
      },
    ),
    DesignerCommand(
      id: 'designer.plane.toSelection',
      label: 'Working plane to the selection',
      dimensions: jge.Dimensions.threeD,
      run: (c) {
        final selection = c.designer?.selectionEntities() ?? const [];
        if (selection.isEmpty) return;
        final state = c.scope.designer3D..moveTo(selection);
        c.designer?.controller.setStatus(_planeStatus(state.plane));
      },
    ),
    for (var slot = 1; slot <= 9; slot++) ...[
      _d(
        'designer.bookmark.store.$slot',
        'Store camera bookmark $slot',
        (c) => c.designer!.storeBookmark(slot),
      ),
      _d(
        'designer.bookmark.recall.$slot',
        'Recall camera bookmark $slot',
        (c) => c.designer!.recallBookmark(slot),
      ),
    ],
    // Editor-wide: dispatched by the plugin after the designer has passed.
    // Play-test controls. Always in scope, and on function keys: during a
    // play-test the letters and Space belong to the game. There is nothing
    // to play-test with no scene open — the start card is showing — but a
    // play-test under way can always be paused and stopped.
    DesignerCommand(
      id: 'editor.playToggle',
      label: 'Play / Stop',
      scope: CommandScope.always,
      isEnabled: _canPlay,
      run: (c) => c.plugin!.playController.togglePlay(),
    ),
    DesignerCommand(
      id: 'editor.pauseToggle',
      label: 'Pause / Resume',
      scope: CommandScope.always,
      isEnabled: _canPlay,
      run: (c) => c.plugin!.playController.togglePause(),
    ),
    DesignerCommand(
      id: 'editor.playRestart',
      label: 'Restart play-test',
      scope: CommandScope.always,
      isEnabled: _canPlay,
      run: (c) => c.plugin!.playController.restart(),
    ),
    DesignerCommand(
      id: 'editor.playStep',
      label: 'Step one frame',
      scope: CommandScope.always,
      isEnabled: _canPlay,
      run: (c) => c.plugin!.playController.step(),
    ),
    DesignerCommand(
      id: 'editor.toggleDesigner',
      label: 'Level Designer',
      scope: CommandScope.always,
      run: (c) => c.plugin!.toggleLevelDesigner(),
    ),
    DesignerCommand(
      id: 'editor.togglePreview',
      label: 'Game camera preview',
      scope: CommandScope.always,
      run: (c) =>
          c.plugin!.showGamePreview.value = !c.plugin!.showGamePreview.value,
    ),
    // The quick snapping bar's: no keys until one is given them.
    DesignerCommand(
      id: 'editor.snap.toggle',
      label: 'Snapping on or off',
      scope: CommandScope.editor,
      run: (c) => c.scope.prefs.change(
        (s) => s.copyWith(gridSnappingEnabled: !s.gridSnappingEnabled),
      ),
    ),
    DesignerCommand(
      id: 'editor.grid.toggle',
      label: 'Show or hide the grid',
      scope: CommandScope.editor,
      run: (c) =>
          c.scope.prefs.change((s) => s.copyWith(showGrid: !s.showGrid)),
    ),
    // `EditorSettingsDialog.commandId`: the gear at the viewport's foot.
    DesignerCommand(
      id: 'editor.settings',
      label: 'Editor settings',
      scope: CommandScope.always,
      run: (c) => c.scope.chrome.toggleSettings(),
    ),
    // ── The bottom docks ───────────────────────────────────────────────────
    DesignerCommand(
      id: 'dock.toggle',
      label: 'Show or hide the dock panel',
      scope: CommandScope.always,
      run: (c) => c.scope.dockController.togglePanel(fallback: 'logs'),
    ),
    DesignerCommand(
      id: 'dock.next',
      label: 'Next dock',
      scope: CommandScope.always,
      run: (c) => c.scope.dockController.cycle(1),
    ),
    DesignerCommand(
      id: 'dock.previous',
      label: 'Previous dock',
      scope: CommandScope.always,
      run: (c) => c.scope.dockController.cycle(-1),
    ),
    // The Timeline dock's own keys work while it has the keyboard; as
    // commands they can also be run from the console or bound to a key.
    for (final (id, label, run)
        in <(String, String, void Function(TimelineSession))>[
          (
            'play',
            'Timeline: play or pause',
            (t) {
              t.isPlaying.value ? t.pause() : t.play();
            },
          ),
          ('stop', 'Timeline: stop and show the scene', (t) => t.stop()),
          (
            'key',
            'Timeline: key the selected track',
            (t) {
              final track = t.selectedTrack.value;
              if (track != null) t.setKey(track, t.playhead.value);
            },
          ),
          ('next_frame', 'Timeline: next frame', (t) => t.stepFrames(1)),
          (
            'previous_frame',
            'Timeline: previous frame',
            (t) {
              t.stepFrames(-1);
            },
          ),
          ('copy', 'Timeline: copy', (t) => t.copy()),
          ('paste', 'Timeline: paste at the playhead', (t) => t.paste()),
          ('duplicate', 'Timeline: duplicate', (t) => t.duplicate()),
          (
            'delete',
            'Timeline: delete',
            (t) {
              t.removeItems(t.selection.value);
            },
          ),
          (
            'ripple_delete',
            'Timeline: ripple delete',
            (t) {
              t.rippleDelete(t.selection.value);
            },
          ),
          ('undo', 'Timeline: undo', (t) => t.undo()),
          ('redo', 'Timeline: redo', (t) => t.redo()),
          ('save', 'Timeline: save', (t) => t.save()),
        ])
      DesignerCommand(
        id: 'timeline.$id',
        label: label,
        scope: CommandScope.always,
        isEnabled: (c) => TimelineSession.of(c.scope).asset.value != null,
        run: (c) => run(TimelineSession.of(c.scope)),
      ),
    DesignerCommand(
      id: 'dock.maximise',
      label: 'Maximise the dock panel',
      scope: CommandScope.always,
      isEnabled: (c) => c.scope.dockController.activeDock != null,
      run: (c) {
        final maximised = c.scope.dockController.maximised;
        maximised.value = !maximised.value;
      },
    ),
    for (final (id, label) in const [
      ('logs', 'Console'),
      ('assets', 'Assets'),
      ('timeline', 'Timeline'),
      ('fps', 'Profiler'),
      ('entities', 'World'),
      ('problems', 'Problems'),
      ('history', 'History'),
      ('animator', 'Animator'),
      ('search', 'Search the scene'),
    ])
      DesignerCommand(
        id: 'dock.open.$id',
        label: 'Dock: $label',
        scope: CommandScope.always,
        run: (c) => c.scope.dockController.toggle(id),
      ),
    DesignerCommand(
      id: 'editor.save',
      label: 'Save scene',
      scope: CommandScope.always,
      run: (c) => c.plugin!.saveScene(),
    ),
    DesignerCommand(
      id: 'editor.copy',
      label: 'Copy',
      scope: CommandScope.editor,
      run: (c) {
        final plugin = c.plugin!;
        final selected = plugin.sceneState.selectedEntity.value;
        if (selected != null) plugin.entities.copyEntity(selected);
      },
    ),
    DesignerCommand(
      id: 'editor.paste',
      label: 'Paste',
      scope: CommandScope.editor,
      run: (c) => c.plugin!.entities.pasteEntity(),
    ),
    // Undo belongs to the editor, not to whichever panel is open: the
    // scope owns one stack and these reach it whether or not a designer
    // session exists.
    DesignerCommand(
      id: 'editor.undo',
      label: 'Undo',
      scope: CommandScope.editor,
      isEnabled: (c) => c.scope.history.canUndo.value,
      run: (c) => c.scope.history.undo(),
    ),
    DesignerCommand(
      id: 'editor.redo',
      label: 'Redo',
      scope: CommandScope.editor,
      isEnabled: (c) => c.scope.history.canRedo.value,
      run: (c) => c.scope.history.redo(),
    ),
    DesignerCommand(
      id: 'editor.duplicate',
      label: 'Duplicate the selection',
      scope: CommandScope.editor,
      isEnabled: (c) => c.plugin != null,
      run: (c) => c.plugin!.duplicateSelection(),
    ),
    DesignerCommand(
      id: 'editor.prefab.make',
      label: 'Make a prefab of the selection',
      scope: CommandScope.editor,
      isEnabled: (c) {
        final selected = c.scope.sceneState.selectedEntity.value;
        return selected != null && PrefabInstances.topOf(selected) == null;
      },
      run: (c) async {
        final selected = c.scope.sceneState.selectedEntity.value;
        if (selected == null) return;
        final path = await c.scope.prefabInstances.makePrefab(selected);
        c.designer?.controller.setStatus(
          path == null ? 'That is part of a prefab already' : 'Made $path',
        );
      },
    ),
    DesignerCommand(
      id: 'editor.prefab.edit',
      label: 'Edit the prefab of the selected instance',
      scope: CommandScope.editor,
      isEnabled: (c) => _selectedTop(c) != null,
      run: (c) {
        final top = _selectedTop(c);
        if (top != null) c.scope.prefabInstances.edit(top);
      },
    ),
    DesignerCommand(
      id: 'editor.prefab.apply',
      label: 'Apply the selected instance\'s changes to its prefab',
      scope: CommandScope.editor,
      isEnabled: (c) => _selectedTop(c) != null,
      run: (c) {
        final top = _selectedTop(c);
        if (top != null) c.scope.prefabInstances.apply(top);
      },
    ),
    DesignerCommand(
      id: 'editor.prefab.revert',
      label: 'Revert the selected instance to its prefab',
      scope: CommandScope.editor,
      isEnabled: (c) => _selectedTop(c) != null,
      run: (c) {
        final top = _selectedTop(c);
        if (top != null) c.scope.prefabInstances.revertAll(top);
      },
    ),
    DesignerCommand(
      id: 'editor.prefab.unpack',
      label: 'Unpack the selected instance into plain entities',
      scope: CommandScope.editor,
      isEnabled: (c) => _selectedTop(c) != null,
      run: (c) {
        final top = _selectedTop(c);
        if (top != null) c.scope.prefabInstances.unpack(top);
      },
    ),
    DesignerCommand(
      id: 'editor.group',
      label: 'Group the selection',
      scope: CommandScope.editor,
      isEnabled: (c) => c.scope.sceneState.hasAnySelection,
      run: (c) => c.scope.entities.groupSelection(),
    ),
    DesignerCommand(
      id: 'editor.ungroup',
      label: 'Take the selected group apart',
      scope: CommandScope.editor,
      isEnabled: (c) {
        final selected = c.scope.sceneState.selectedEntity.value;
        return selected != null && c.scope.entities.isGroup(selected);
      },
      run: (c) {
        final selected = c.scope.sceneState.selectedEntity.value;
        if (selected != null) c.scope.entities.ungroup(selected);
      },
    ),
    DesignerCommand(
      id: 'editor.delete',
      label: 'Delete the selection',
      scope: CommandScope.editor,
      isEnabled: (c) => c.plugin != null && c.plugin!.isAuthoring.value,
      run: (c) => c.plugin!.deleteSelection(),
    ),
    // All, Move, Scale, Rotate: which gizmo the selection shows, in the
    // editor and the designer alike — and in the designer, the select
    // tool. Only while authoring: during a play-test the letters are the
    // game's.
    for (final mode in TransformMode.values)
      DesignerCommand(
        id: mode.commandId,
        label: mode.label,
        scope: CommandScope.editor,
        isEnabled: (c) => c.plugin?.isAuthoring.value ?? true,
        run: (c) {
          c.scope.view.transformMode.value = mode;
          c.designer?.adoptTransformMode();
        },
      ),
    // Looking around a 3-D scene.
    DesignerCommand(
      id: 'editor.view.frame',
      label: 'Frame the selection',
      scope: CommandScope.editor,
      dimensions: jge.Dimensions.threeD,
      isEnabled: (c) => c.plugin != null,
      run: (c) => c.plugin!.frameInSpace(),
    ),
    DesignerCommand(
      id: 'editor.view.frameAll',
      label: 'Frame everything',
      scope: CommandScope.editor,
      dimensions: jge.Dimensions.threeD,
      isEnabled: (c) => c.plugin != null,
      run: (c) => c.plugin!.frameInSpace(all: true),
    ),
    for (final (id, label, yaw, pitch) in axisViews)
      DesignerCommand(
        id: id,
        label: label,
        scope: CommandScope.editor,
        dimensions: jge.Dimensions.threeD,
        isEnabled: (c) => c.plugin != null,
        run: (c) => c.plugin!.viewAlong(yaw: yaw, pitch: pitch),
      ),
    DesignerCommand(
      id: 'editor.view.split',
      label: 'Four views: top, front, side, perspective',
      scope: CommandScope.editor,
      dimensions: jge.Dimensions.threeD,
      isEnabled: (c) => c.plugin?.isAuthoring.value ?? false,
      run: (c) => c.plugin!.toggleSplitViews(),
    ),
    DesignerCommand(
      id: 'editor.view.orthographic',
      label: 'Orthographic or perspective',
      scope: CommandScope.editor,
      dimensions: jge.Dimensions.threeD,
      isEnabled: (c) => c.plugin != null,
      run: (c) => c.plugin!.toggleOrthographic(),
    ),
    DesignerCommand(
      id: 'editor.gizmo.local',
      label: 'Gizmo: own axes or the world\'s',
      scope: CommandScope.editor,
      dimensions: jge.Dimensions.threeD,
      isEnabled: (c) => c.plugin?.isAuthoring.value ?? false,
      run: (c) {
        final state = c.scope.sceneState;
        state.localGizmo = !state.localGizmo;
      },
    ),
  ];

  /// The views along an axis: id, label, yaw and pitch (radians).
  static const List<(String, String, double, double)> axisViews = [
    ('editor.view.front', 'View from the front', 0, 0),
    ('editor.view.back', 'View from the back', math.pi, 0),
    ('editor.view.right', 'View from the right', -math.pi / 2, 0),
    ('editor.view.left', 'View from the left', math.pi / 2, 0),
    ('editor.view.top', 'View from above', 0, -math.pi / 2),
    ('editor.view.bottom', 'View from below', 0, math.pi / 2),
  ];

  /// What the status bar says of [plane]: its way and, as a height or a
  /// depth, where it is.
  static String _planeStatus(WorkingPlane plane) {
    final at = plane.axis == WorkingPlaneAxis.ground
        ? -plane.offset
        : plane.offset;
    final where = plane.axis == WorkingPlaneAxis.ground ? 'height' : 'at';
    return 'Working plane: ${plane.axis.label}, $where '
        '${(at.abs() < 0.005 ? 0.0 : at).toStringAsFixed(2)} m';
  }

  /// A scene is open to play-test, or a play-test is under way.
  /// The prefab instance the selection is part of: its top.
  static jge.Entity? _selectedTop(CommandContext c) {
    final selected = c.scope.sceneState.selectedEntity.value;
    return selected == null ? null : PrefabInstances.topOf(selected);
  }

  static bool _canPlay(CommandContext c) {
    final plugin = c.plugin;
    return plugin == null ||
        plugin.sceneState.hasScene ||
        plugin.playController.isRunning;
  }

  static DesignerCommand _d(
    String id,
    String label,
    void Function(CommandContext) run,
  ) => DesignerCommand(id: id, label: label, run: run);

  /// A command that only means something in a 2-D scene.
  static DesignerCommand _d2(
    String id,
    String label,
    void Function(CommandContext) run,
  ) => DesignerCommand(
    id: id,
    label: label,
    run: run,
    dimensions: jge.Dimensions.twoD,
  );
}

import 'package:flutter/widgets.dart' show Offset;

import 'designer_command.dart';

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
        // Shift nudges one unit; otherwise one grid cell.
        run: (c) => c.session!.ops.nudge(
          c.session!.selectionEntities(),
          delta *
              (c.modifiers.shift ? 1.0 : (c.gridSize > 0 ? c.gridSize : 1.0)),
        ),
      ),
    _d(
      'designer.rotateClockwise',
      'Rotate a quarter turn',
      (c) => c.session!.ops.rotateQuarter(c.session!.selectionEntities(), 1),
    ),
    _d(
      'designer.rotateCounter',
      'Rotate a quarter turn back',
      (c) => c.session!.ops.rotateQuarter(c.session!.selectionEntities(), -1),
    ),
    _d(
      'designer.flipHorizontal',
      'Flip horizontally',
      (c) =>
          c.session!.ops.flip(c.session!.selectionEntities(), horizontal: true),
    ),
    _d(
      'designer.flipVertical',
      'Flip vertically',
      (c) => c.session!.ops.flip(
        c.session!.selectionEntities(),
        horizontal: false,
      ),
    ),
    _d(
      'designer.frameSelection',
      'Frame the selection',
      (c) => c.session!.frameSelection(),
    ),
    _d('designer.frameAll', 'Frame everything', (c) => c.session!.frameAll()),
    _d(
      'designer.hide',
      'Hide the selection',
      (c) => c.session!.hideSelection(),
    ),
    _d(
      'designer.isolate',
      'Isolate the selection',
      (c) => c.session!.isolateSelection(),
    ),
    _d('designer.unhideAll', 'Show everything', (c) => c.session!.unhideAll()),
    _d(
      'designer.lock',
      'Lock the selection',
      (c) => c.session!.lockSelection(),
    ),
    _d(
      'designer.unlockAll',
      'Unlock everything',
      (c) => c.session!.unlockAll(),
    ),
    _d(
      'designer.replace',
      'Replace with the active prefab',
      (c) => c.session!.replaceSelection(),
    ),
    _d('designer.selectAll', 'Select all', (c) => c.session!.selectAll()),
    _d('designer.brushSmaller', 'Smaller brush', (c) {
      final brush = c.session!.controller.brushSize;
      brush.value = c.scope.config.smallerBrush(brush.value);
    }),
    _d('designer.brushLarger', 'Larger brush', (c) {
      final brush = c.session!.controller.brushSize;
      brush.value = c.scope.config.largerBrush(brush.value);
    }),
    _d('designer.cancel', 'Cancel the gesture, or clear the selection', (c) {
      final s = c.session!;
      s.hasActiveGesture ? s.onPointerCancel() : s.sceneState.clearSelection();
    }),
    for (var slot = 1; slot <= 9; slot++) ...[
      _d(
        'designer.bookmark.store.$slot',
        'Store camera bookmark $slot',
        (c) => c.session!.storeBookmark(slot),
      ),
      _d(
        'designer.bookmark.recall.$slot',
        'Recall camera bookmark $slot',
        (c) => c.session!.recallBookmark(slot),
      ),
    ],
    // Editor-wide: dispatched by the plugin after the designer has passed.
    // Play-test controls. Always in scope, and on function keys: during a
    // play-test the letters and Space belong to the game.
    DesignerCommand(
      id: 'editor.playToggle',
      label: 'Play / Stop',
      scope: CommandScope.always,
      run: (c) => c.plugin!.playController.togglePlay(),
    ),
    DesignerCommand(
      id: 'editor.pauseToggle',
      label: 'Pause / Resume',
      scope: CommandScope.always,
      run: (c) => c.plugin!.playController.togglePause(),
    ),
    DesignerCommand(
      id: 'editor.playRestart',
      label: 'Restart play-test',
      scope: CommandScope.always,
      run: (c) => c.plugin!.playController.restart(),
    ),
    DesignerCommand(
      id: 'editor.playStep',
      label: 'Step one frame',
      scope: CommandScope.always,
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
    DesignerCommand(
      id: 'editor.save',
      label: 'Save scene',
      scope: CommandScope.always,
      run: (c) => c.plugin!.saveScene(),
    ),
    DesignerCommand(
      id: 'editor.copy',
      label: 'Copy entity',
      scope: CommandScope.editor,
      run: (c) {
        final selected = c.plugin!.sceneState.selectedEntity.value;
        if (selected != null) c.plugin!.entities.copyEntity(selected);
      },
    ),
    DesignerCommand(
      id: 'editor.paste',
      label: 'Paste entity',
      scope: CommandScope.editor,
      run: (c) => c.plugin!.entities.pasteEntity(),
    ),
    DesignerCommand(
      id: 'editor.undo',
      label: 'Undo',
      scope: CommandScope.editor,
      isEnabled: (c) => c.session != null,
      run: (c) => c.session!.history.undo(),
    ),
    DesignerCommand(
      id: 'editor.redo',
      label: 'Redo',
      scope: CommandScope.editor,
      isEnabled: (c) => c.session != null,
      run: (c) => c.session!.history.redo(),
    ),
    DesignerCommand(
      id: 'editor.duplicate',
      label: 'Duplicate the selection',
      scope: CommandScope.editor,
      isEnabled: (c) => c.session != null,
      run: (c) => c.plugin!.duplicateSelection(),
    ),
    DesignerCommand(
      id: 'editor.delete',
      label: 'Delete the selection',
      scope: CommandScope.editor,
      isEnabled: (c) =>
          c.session != null && (c.plugin?.isAuthoring.value ?? true),
      run: (c) => c.plugin!.deleteSelection(),
    ),
  ];

  static DesignerCommand _d(
    String id,
    String label,
    void Function(CommandContext) run,
  ) => DesignerCommand(id: id, label: label, run: run);
}

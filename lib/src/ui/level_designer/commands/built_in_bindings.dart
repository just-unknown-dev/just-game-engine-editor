import 'package:flutter/services.dart';

import 'package:just_editor_core/host.dart';

/// The default chords for `BuiltInCommands`.
abstract final class BuiltInBindings {
  /// Bookmarks bind as many digits as [config] allows.
  static List<KeyBinding> of(DesignerConfig config) => [
    const KeyBinding(LogicalKeyboardKey.arrowLeft, 'designer.nudgeLeft'),
    const KeyBinding(
      LogicalKeyboardKey.arrowLeft,
      'designer.nudgeLeft',
      shift: true,
    ),
    const KeyBinding(LogicalKeyboardKey.arrowRight, 'designer.nudgeRight'),
    const KeyBinding(
      LogicalKeyboardKey.arrowRight,
      'designer.nudgeRight',
      shift: true,
    ),
    const KeyBinding(LogicalKeyboardKey.arrowUp, 'designer.nudgeUp'),
    const KeyBinding(
      LogicalKeyboardKey.arrowUp,
      'designer.nudgeUp',
      shift: true,
    ),
    const KeyBinding(LogicalKeyboardKey.arrowDown, 'designer.nudgeDown'),
    const KeyBinding(
      LogicalKeyboardKey.arrowDown,
      'designer.nudgeDown',
      shift: true,
    ),
    const KeyBinding(LogicalKeyboardKey.keyZ, 'designer.rotateClockwise'),
    const KeyBinding(
      LogicalKeyboardKey.keyZ,
      'designer.rotateCounter',
      shift: true,
    ),
    const KeyBinding(LogicalKeyboardKey.keyX, 'designer.flipHorizontal'),
    const KeyBinding(LogicalKeyboardKey.keyY, 'designer.flipVertical'),
    const KeyBinding(LogicalKeyboardKey.keyF, 'designer.frameSelection'),
    const KeyBinding(LogicalKeyboardKey.keyF, 'designer.frameAll', shift: true),
    const KeyBinding(LogicalKeyboardKey.keyH, 'designer.hide'),
    const KeyBinding(LogicalKeyboardKey.keyH, 'designer.isolate', shift: true),
    const KeyBinding(LogicalKeyboardKey.keyH, 'designer.unhideAll', alt: true),
    const KeyBinding(LogicalKeyboardKey.keyL, 'designer.lock'),
    const KeyBinding(LogicalKeyboardKey.keyL, 'designer.unlockAll', alt: true),
    // R is Rotate; replacing is the rarer act.
    const KeyBinding(LogicalKeyboardKey.keyR, 'designer.replace', shift: true),
    // The 3-D designer's working plane: Page Up up, Page Down down (Shift:
    // ten steps),
    // \ the next way round, Shift+\ to the selection.
    const KeyBinding(LogicalKeyboardKey.pageUp, 'designer.plane.raise'),
    const KeyBinding(
      LogicalKeyboardKey.pageUp,
      'designer.plane.raise',
      shift: true,
    ),
    const KeyBinding(LogicalKeyboardKey.pageDown, 'designer.plane.lower'),
    const KeyBinding(
      LogicalKeyboardKey.pageDown,
      'designer.plane.lower',
      shift: true,
    ),
    const KeyBinding(LogicalKeyboardKey.backslash, 'designer.plane.cycle'),
    const KeyBinding(
      LogicalKeyboardKey.keyG,
      'designer.selectSimilar',
      shift: true,
    ),
    const KeyBinding(LogicalKeyboardKey.numpad5, 'editor.view.orthographic'),
    const KeyBinding(LogicalKeyboardKey.end, 'designer.dropToGround'),
    // Four views, as Blender splits its own.
    const KeyBinding(
      LogicalKeyboardKey.keyQ,
      'editor.view.split',
      control: true,
      alt: true,
    ),
    const KeyBinding(
      LogicalKeyboardKey.backslash,
      'designer.plane.toSelection',
      shift: true,
    ),
    const KeyBinding(LogicalKeyboardKey.keyQ, 'editor.transform.all'),
    const KeyBinding(LogicalKeyboardKey.keyW, 'editor.transform.move'),
    const KeyBinding(LogicalKeyboardKey.keyE, 'editor.transform.scale'),
    const KeyBinding(LogicalKeyboardKey.keyR, 'editor.transform.rotate'),
    // In 3-D: F and Shift+F frame, the pad's 1, 3 and 7 look along an axis
    // (Ctrl for the other side), X puts the gizmo in the entity's own axes.
    const KeyBinding(LogicalKeyboardKey.keyF, 'editor.view.frame'),
    const KeyBinding(
      LogicalKeyboardKey.keyF,
      'editor.view.frameAll',
      shift: true,
    ),
    const KeyBinding(LogicalKeyboardKey.numpad1, 'editor.view.front'),
    const KeyBinding(
      LogicalKeyboardKey.numpad1,
      'editor.view.back',
      control: true,
    ),
    const KeyBinding(LogicalKeyboardKey.numpad3, 'editor.view.right'),
    const KeyBinding(
      LogicalKeyboardKey.numpad3,
      'editor.view.left',
      control: true,
    ),
    const KeyBinding(LogicalKeyboardKey.numpad7, 'editor.view.top'),
    const KeyBinding(
      LogicalKeyboardKey.numpad7,
      'editor.view.bottom',
      control: true,
    ),
    const KeyBinding(LogicalKeyboardKey.keyX, 'editor.gizmo.local'),
    const KeyBinding(
      LogicalKeyboardKey.keyA,
      'designer.selectAll',
      control: true,
    ),
    const KeyBinding(LogicalKeyboardKey.bracketLeft, 'designer.brushSmaller'),
    const KeyBinding(LogicalKeyboardKey.bracketRight, 'designer.brushLarger'),
    const KeyBinding(LogicalKeyboardKey.escape, 'designer.cancel'),
    for (var slot = 1; slot <= config.bookmarkSlots; slot++) ...[
      KeyBinding(
        _digits[slot - 1],
        'designer.bookmark.store.$slot',
        control: true,
      ),
      KeyBinding(_digits[slot - 1], 'designer.bookmark.recall.$slot'),
    ],
    const KeyBinding(LogicalKeyboardKey.f5, 'editor.playToggle'),
    const KeyBinding(LogicalKeyboardKey.f5, 'editor.playRestart', shift: true),
    const KeyBinding(LogicalKeyboardKey.f6, 'editor.pauseToggle'),
    const KeyBinding(LogicalKeyboardKey.f10, 'editor.playStep'),
    const KeyBinding(LogicalKeyboardKey.f3, 'editor.toggleDesigner'),
    const KeyBinding(LogicalKeyboardKey.f4, 'editor.togglePreview'),
    // Ctrl+, for settings, as in most editors.
    const KeyBinding(
      LogicalKeyboardKey.comma,
      'editor.settings',
      control: true,
    ),
    // The docks: Ctrl+` for the panel, as in every editor with a terminal,
    // and Ctrl+Shift+letter for a dock by name.
    const KeyBinding(
      LogicalKeyboardKey.backquote,
      'dock.toggle',
      control: true,
    ),
    const KeyBinding(
      LogicalKeyboardKey.pageDown,
      'dock.next',
      control: true,
      alt: true,
    ),
    const KeyBinding(
      LogicalKeyboardKey.pageUp,
      'dock.previous',
      control: true,
      alt: true,
    ),
    const KeyBinding(
      LogicalKeyboardKey.keyM,
      'dock.maximise',
      control: true,
      shift: true,
    ),
    for (final (key, id) in [
      (LogicalKeyboardKey.keyC, 'logs'),
      (LogicalKeyboardKey.keyA, 'assets'),
      (LogicalKeyboardKey.keyT, 'timeline'),
      (LogicalKeyboardKey.keyP, 'fps'),
      (LogicalKeyboardKey.keyW, 'entities'),
      (LogicalKeyboardKey.keyF, 'search'),
      (LogicalKeyboardKey.keyH, 'history'),
      (LogicalKeyboardKey.keyE, 'problems'),
    ])
      KeyBinding(key, 'dock.open.$id', control: true, shift: true),
    const KeyBinding(LogicalKeyboardKey.keyS, 'editor.save', control: true),
    const KeyBinding(LogicalKeyboardKey.keyC, 'editor.copy', control: true),
    const KeyBinding(LogicalKeyboardKey.keyV, 'editor.paste', control: true),
    const KeyBinding(LogicalKeyboardKey.keyZ, 'editor.undo', control: true),
    const KeyBinding(
      LogicalKeyboardKey.keyZ,
      'editor.redo',
      control: true,
      shift: true,
    ),
    const KeyBinding(LogicalKeyboardKey.keyY, 'editor.redo', control: true),
    const KeyBinding(
      LogicalKeyboardKey.keyD,
      'editor.duplicate',
      control: true,
    ),
    const KeyBinding(LogicalKeyboardKey.delete, 'editor.delete'),
    const KeyBinding(LogicalKeyboardKey.keyG, 'editor.group', control: true),
    const KeyBinding(
      LogicalKeyboardKey.keyG,
      'editor.ungroup',
      control: true,
      shift: true,
    ),
  ];

  static const List<LogicalKeyboardKey> _digits = [
    LogicalKeyboardKey.digit1,
    LogicalKeyboardKey.digit2,
    LogicalKeyboardKey.digit3,
    LogicalKeyboardKey.digit4,
    LogicalKeyboardKey.digit5,
    LogicalKeyboardKey.digit6,
    LogicalKeyboardKey.digit7,
    LogicalKeyboardKey.digit8,
    LogicalKeyboardKey.digit9,
  ];
}

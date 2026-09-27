import 'package:flutter/services.dart';

import '../state/designer_config.dart';
import 'designer_command.dart';

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
    const KeyBinding(LogicalKeyboardKey.keyV, 'editor.transform.all'),
    const KeyBinding(LogicalKeyboardKey.keyW, 'editor.transform.move'),
    const KeyBinding(LogicalKeyboardKey.keyE, 'editor.transform.scale'),
    const KeyBinding(LogicalKeyboardKey.keyR, 'editor.transform.rotate'),
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

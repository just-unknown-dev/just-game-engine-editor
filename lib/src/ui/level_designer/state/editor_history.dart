import 'dart:math' as math;

import 'package:just_signals/just_signals.dart';

/// One reversible editor action.
///
/// Commands are the only sanctioned way to change a level once the Level
/// Designer is open. Anything that mutates the world outside one is invisible
/// to undo, which is worse than having no undo at all — the user stops
/// trusting Ctrl+Z and stops using it.
abstract class EditorCommand {
  /// Short, human-readable description, shown in the undo tooltip.
  /// Phrase it as the action performed: "Move 3 entities", "Delete Platform_4".
  String get label;

  /// Perform the action. Called once when the command is first executed and
  /// again on every redo, so it must be idempotent with respect to [undo].
  void redo();

  /// Reverse [redo], restoring the exact prior state.
  void undo();

  /// Fold [next] into this command if the two are part of one user gesture.
  ///
  /// Returns true when absorbed, in which case [next] is discarded. This is
  /// what stops a drag from pushing one command per pointer-move event and
  /// burying every earlier action under a hundred one-pixel nudges.
  bool mergeWith(EditorCommand next) => false;
}

/// A command built from two closures, for actions simple enough that a named
/// class would be noise.
class CallbackCommand extends EditorCommand {
  CallbackCommand({
    required this.label,
    required void Function() onRedo,
    required void Function() onUndo,
  }) : _redo = onRedo,
       _undo = onUndo;

  @override
  final String label;

  final void Function() _redo;
  final void Function() _undo;

  @override
  void redo() => _redo();

  @override
  void undo() => _undo();
}

/// Undo/redo stack for the Level Designer.
///
/// Exposes its state as signals so toolbar buttons bind directly instead of
/// polling or being told to rebuild.
class EditorHistory {
  EditorHistory({int capacity = 200}) : _capacity = math.max(1, capacity);

  /// How many commands are retained. Older ones are dropped from the bottom.
  ///
  /// Bounded because a command can hold a full component snapshot of a deleted
  /// entity, so an unbounded stack is an unbounded memory leak across a long
  /// editing session. Made smaller, the oldest steps go at once.
  int get capacity => _capacity;
  int _capacity;
  set capacity(int value) {
    final next = math.max(1, value);
    if (next == _capacity) return;
    _capacity = next;
    if (_undoStack.length > next) {
      batch(() {
        _undoStack.removeRange(0, _undoStack.length - next);
        _publish();
      });
    }
  }

  final List<EditorCommand> _undoStack = [];
  final List<EditorCommand> _redoStack = [];

  /// Whether there is anything to undo.
  final Signal<bool> canUndo = Signal(false, debugLabel: 'canUndo');

  /// Whether there is anything to redo.
  final Signal<bool> canRedo = Signal(false, debugLabel: 'canRedo');

  /// Label of the action Ctrl+Z would reverse, for the button tooltip.
  final Signal<String?> nextUndoLabel = Signal(null, debugLabel: 'nextUndo');

  /// Label of the action Ctrl+Y would replay.
  final Signal<String?> nextRedoLabel = Signal(null, debugLabel: 'nextRedo');

  /// Raised whenever the stack changes, so the viewport can repaint.
  final Signal<int> revision = Signal(0, debugLabel: 'undoRevision');

  /// True while [undo] or [redo] is running.
  ///
  /// Mutation funnels check this and skip recording, so replaying a command
  /// does not push a new command describing the replay.
  bool get isApplying => _isApplying;
  bool _isApplying = false;

  /// Runs [command] and records it.
  ///
  /// Does nothing while a command is already being applied, which is what
  /// keeps undo from recording its own side effects.
  void push(EditorCommand command) {
    if (_isApplying) {
      command.redo();
      return;
    }

    batch(() {
      command.redo();

      // A new action makes the redo branch unreachable — standard linear undo.
      _redoStack.clear();

      if (_undoStack.isNotEmpty && _undoStack.last.mergeWith(command)) {
        // Absorbed into the previous command; nothing new to stack.
      } else {
        _undoStack.add(command);
        if (_undoStack.length > _capacity) _undoStack.removeAt(0);
      }

      _publish();
    });
  }

  /// Records [command] as already performed, without running it.
  ///
  /// For state a widget has already changed by the time it can build the
  /// command — an inspector field whose controller has committed, say.
  void pushApplied(EditorCommand command) {
    if (_isApplying) return;
    batch(() {
      _redoStack.clear();
      if (_undoStack.isEmpty || !_undoStack.last.mergeWith(command)) {
        _undoStack.add(command);
        if (_undoStack.length > _capacity) _undoStack.removeAt(0);
      }
      _publish();
    });
  }

  /// Reverses the most recent command.
  /// What has been done, oldest first.
  List<EditorCommand> get undoEntries => List.unmodifiable(_undoStack);

  /// What has been undone, the next to redo last.
  List<EditorCommand> get redoEntries => List.unmodifiable(_redoStack);

  /// Undoes or redoes until exactly [done] steps are applied: 0 is the scene
  /// as opened, [undoEntries].length plus [redoEntries].length is everything.
  void jumpTo(int done) {
    final target = done.clamp(0, _undoStack.length + _redoStack.length);
    while (_undoStack.length > target) {
      final before = _undoStack.length;
      undo();
      if (_undoStack.length == before) return; // a step refused to move
    }
    while (_undoStack.length < target) {
      final before = _undoStack.length;
      redo();
      if (_undoStack.length == before) return;
    }
  }

  void undo() {
    if (_undoStack.isEmpty) return;
    final command = _undoStack.removeLast();
    _isApplying = true;
    try {
      batch(() {
        command.undo();
        _redoStack.add(command);
        _publish();
      });
    } finally {
      _isApplying = false;
    }
  }

  /// Replays the most recently undone command.
  void redo() {
    if (_redoStack.isEmpty) return;
    final command = _redoStack.removeLast();
    _isApplying = true;
    try {
      batch(() {
        command.redo();
        _undoStack.add(command);
        _publish();
      });
    } finally {
      _isApplying = false;
    }
  }

  /// Drops all history, e.g. when a different scene is opened.
  ///
  /// Essential rather than tidy: a command holds entity references from the
  /// scene it was recorded in, so undoing across a scene load would write into
  /// destroyed entities.
  void clear() {
    batch(() {
      _undoStack.clear();
      _redoStack.clear();
      _publish();
    });
  }

  void _publish() {
    canUndo.value = _undoStack.isNotEmpty;
    canRedo.value = _redoStack.isNotEmpty;
    nextUndoLabel.value = _undoStack.isEmpty ? null : _undoStack.last.label;
    nextRedoLabel.value = _redoStack.isEmpty ? null : _redoStack.last.label;
    revision.value = revision.value + 1;
  }

  /// Number of commands available to undo. Exposed for tests and diagnostics.
  int get undoDepth => _undoStack.length;

  /// Number of commands available to redo.
  int get redoDepth => _redoStack.length;

  /// Releases the signals.
  void dispose() {
    canUndo.dispose();
    canRedo.dispose();
    nextUndoLabel.dispose();
    nextRedoLabel.dispose();
    revision.dispose();
  }
}

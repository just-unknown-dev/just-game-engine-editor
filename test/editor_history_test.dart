// The undo stack is the foundation the whole Level Designer sits on — every
// editing gesture routes through it, so these cover the contract the rest of
// the designer assumes.

import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine_editor/just_game_engine_editor.dart';

/// A command that appends to [log] so ordering is observable.
class _Recording extends EditorCommand {
  _Recording(this.label, this.log, {this.mergeable = false});

  @override
  final String label;

  final List<String> log;
  final bool mergeable;

  @override
  void redo() => log.add('redo:$label');

  @override
  void undo() => log.add('undo:$label');

  @override
  bool mergeWith(EditorCommand next) => mergeable && next is _Recording;
}

void main() {
  late EditorHistory history;
  late List<String> log;

  setUp(() {
    history = EditorHistory();
    log = <String>[];
  });

  tearDown(() => history.dispose());

  test('push runs the command immediately', () {
    history.push(_Recording('a', log));
    expect(log, ['redo:a']);
  });

  test('undo and redo walk the stack in order', () {
    history
      ..push(_Recording('a', log))
      ..push(_Recording('b', log));
    log.clear();

    history
      ..undo()
      ..undo();
    expect(log, ['undo:b', 'undo:a']);

    log.clear();
    history
      ..redo()
      ..redo();
    expect(log, ['redo:a', 'redo:b']);
  });

  test('signals track availability', () {
    expect(history.canUndo.value, isFalse);
    expect(history.canRedo.value, isFalse);

    history.push(_Recording('a', log));
    expect(history.canUndo.value, isTrue);
    expect(history.canRedo.value, isFalse);
    expect(history.nextUndoLabel.value, 'a');

    history.undo();
    expect(history.canUndo.value, isFalse);
    expect(history.canRedo.value, isTrue);
    expect(history.nextRedoLabel.value, 'a');
  });

  test('a new action discards the redo branch', () {
    history
      ..push(_Recording('a', log))
      ..push(_Recording('b', log))
      ..undo();
    expect(history.canRedo.value, isTrue);

    history.push(_Recording('c', log));

    expect(history.canRedo.value, isFalse);
    expect(history.redoDepth, 0);
  });

  test('undo on an empty stack is a no-op', () {
    history
      ..undo()
      ..redo();
    expect(log, isEmpty);
  });

  test('a command pushed while applying is not recorded again', () {
    // Guards against a command whose undo triggers a listener that pushes:
    // without the isApplying gate that recurses and corrupts the stack.
    late EditorHistory inner;
    inner = EditorHistory();
    addTearDown(inner.dispose);

    final reentrant = CallbackCommand(
      label: 'outer',
      onRedo: () {
        if (inner.isApplying) return;
        inner.push(
          CallbackCommand(label: 'inner', onRedo: () {}, onUndo: () {}),
        );
      },
      onUndo: () {},
    );

    inner.push(reentrant);
    expect(inner.undoDepth, 2, reason: 'nested push recorded once, normally');

    inner.undo();
    expect(inner.isApplying, isFalse);
  });

  test('mergeable commands collapse into one history entry', () {
    history
      ..push(_Recording('drag', log, mergeable: true))
      ..push(_Recording('drag', log, mergeable: true))
      ..push(_Recording('drag', log, mergeable: true));

    expect(
      history.undoDepth,
      1,
      reason: 'a drag must not push one entry per pointer move',
    );
  });

  test('capacity drops the oldest entries', () {
    final bounded = EditorHistory(capacity: 3);
    addTearDown(bounded.dispose);

    for (var i = 0; i < 10; i++) {
      bounded.push(_Recording('$i', log));
    }

    expect(bounded.undoDepth, 3);
    expect(bounded.nextUndoLabel.value, '9');
  });

  test('clear drops both stacks', () {
    history
      ..push(_Recording('a', log))
      ..push(_Recording('b', log))
      ..undo()
      ..clear();

    expect(history.canUndo.value, isFalse);
    expect(history.canRedo.value, isFalse);
    expect(history.undoDepth, 0);
    expect(history.redoDepth, 0);
  });

  test('revision advances on every change, so the canvas can repaint', () {
    final start = history.revision.value;
    history.push(_Recording('a', log));
    expect(history.revision.value, greaterThan(start));

    final afterPush = history.revision.value;
    history.undo();
    expect(history.revision.value, greaterThan(afterPush));
  });
}

// A document edited in a workspace of its own — a screen, a sprite — needs
// its history to say whether what is on screen is what was saved, and a drag
// to be one step without two drags being one.

import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine_editor/just_game_engine_editor.dart';

/// Sets a value; merges with another of the same [key], as a drag does.
class _Set extends EditorCommand {
  _Set(this.box, this.to, {this.key = 'x'}) : from = box.value;

  final _Box box;
  final int from;
  int to;
  final String key;

  @override
  String get label => 'Set $key';

  @override
  void redo() => box.value = to;

  @override
  void undo() => box.value = from;

  @override
  bool mergeWith(EditorCommand next) {
    if (next is! _Set || next.key != key) return false;
    to = next.to;
    return true;
  }
}

class _Box {
  int value = 0;
}

void main() {
  late EditorHistory history;
  late _Box box;
  setUp(() {
    history = EditorHistory();
    box = _Box();
  });
  tearDown(() => history.dispose());

  group('the saved point', () {
    test('a fresh history is clean, and an edit makes it dirty', () {
      expect(history.dirty.value, isFalse);
      history.push(_Set(box, 1));
      expect(history.dirty.value, isTrue);
    });

    test('undoing back to the save reads clean again', () {
      history.push(_Set(box, 1, key: 'a'));
      history.markSaved();
      history.push(_Set(box, 2, key: 'b'));
      expect(history.dirty.value, isTrue);

      history.undo();
      expect(history.dirty.value, isFalse);

      history.undo();
      expect(history.dirty.value, isTrue, reason: 'past the save');
      history.redo();
      expect(history.dirty.value, isFalse);
    });

    test('nothing is folded into the saved step', () {
      history.push(_Set(box, 1));
      history.markSaved();

      history.push(_Set(box, 5)); // would merge, but that is the save

      expect(history.undoDepth, 2);
      expect(history.dirty.value, isTrue);
      history.undo();
      expect(box.value, 1);
      expect(history.dirty.value, isFalse);
    });
  });

  group('gestures', () {
    test('one drag is one step', () {
      for (var i = 1; i <= 10; i++) {
        history.push(_Set(box, i));
      }
      expect(history.undoDepth, 1);
    });

    test('two drags of the same thing are two steps', () {
      history.breakMerge();
      history.push(_Set(box, 1));
      history.push(_Set(box, 2));
      history.breakMerge();
      history.push(_Set(box, 3));
      history.push(_Set(box, 4));

      expect(history.undoDepth, 2);
      history.undo();
      expect(box.value, 2);
    });

    test('a break holds for one push only', () {
      history.push(_Set(box, 1));
      history.breakMerge();
      history.push(_Set(box, 2));
      history.push(_Set(box, 3));

      expect(history.undoDepth, 2);
    });
  });
}

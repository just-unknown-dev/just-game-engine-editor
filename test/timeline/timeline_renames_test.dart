// Renaming an entity takes the inline timelines' tracks bound to its name
// with it, as one undo step; undone and redone, the rename is applied to
// the timeline as it is then, so keys added since are kept.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_game_engine_editor/just_game_engine_editor.dart';
import 'package:just_game_engine_editor/src/entities/scope_entities.dart';
import 'package:just_game_engine_editor/src/timeline/timeline_renames.dart';
import 'package:just_game_engine_editor/src/timeline/timeline_session.dart';

import '../support/test_scope.dart';

TimelineKey _k(double t, double v) =>
    TimelineKey(time: t, value: v, interpolation: KeyInterpolation.linear);

PropertyTrack _x(List<TimelineKey> keys, TrackBinding binding) => PropertyTrack(
  component: 'TransformComponent',
  field: 'position',
  channel: 'x',
  binding: binding,
  curve: KeyCurve(keys),
);

void main() {
  late Directory root;
  late EditorScope scope;
  late TimelineSession s;
  late Entity door;
  late TimelinePlayerComponent player;

  setUp(() {
    root = Directory.systemTemp.createTempSync('timeline_renames');
    addTearDown(() {
      try {
        root.deleteSync(recursive: true);
      } on FileSystemException {
        // Windows may still hold a file for a moment; it is a temp one.
      }
    });
    scope = testScope();
    s = TimelineSession(scope, root: root.path);
    addTearDown(s.dispose);
    player = TimelinePlayerComponent(
      inline: TimelineAsset(
        duration: 2,
        fps: 10,
        tracks: [
          _x([_k(0, 0), _k(2, 200)], const TrackBinding.name('Door')),
        ],
      ),
    );
    door = scope.world.createEntityWithComponents([
      TransformComponent(),
      player,
    ], name: 'Door');
  });

  // The rename as every panel makes it, through the entity operations: the
  // name and the timelines (the editor's module registered them as its
  // follower), one undo step.
  void rename(String to) {
    expect(scope.entities.renameEntity(door, to), isTrue);
    expect(scope.history.undoDepth, 1, reason: 'one step');
  }

  List<double> times() => (player.inline!.tracks.single as PropertyTrack)
      .curve
      .keys
      .map((k) => k.time)
      .toList();

  TrackBinding binding() => player.inline!.tracks.single.binding;

  test('tracks bound to the old name follow the new one, and back', () {
    final command = TimelineRenames.commandFor(scope, 'Door', 'Gate')!;
    command.redo();
    expect(binding(), const TrackBinding.name('Gate'));
    command.undo();
    expect(binding(), const TrackBinding.name('Door'));
    expect(TimelineRenames.commandFor(scope, 'Nobody', 'X'), isNull);
  });

  test('keys added after the rename survive its undo and redo', () async {
    rename('Gate');
    expect(binding(), const TrackBinding.name('Gate'));
    await s.follow(door);
    s.setKey(0, 1, value: 50.0);
    expect(times(), [0, 1, 2]);

    scope.history.undo();
    expect(door.name, 'Door');
    expect(binding(), const TrackBinding.name('Door'));
    expect(times(), [0, 1, 2], reason: 'the key added since is kept');

    scope.history.redo();
    expect(door.name, 'Gate');
    expect(binding(), const TrackBinding.name('Gate'));
    expect(times(), [0, 1, 2]);
  });

  test('a track bound to the new name since the rename follows it back', () {
    rename('Gate');
    player.inline = player.inline!.copyWith(
      tracks: [
        ...player.inline!.tracks,
        _x([_k(0, 5)], const TrackBinding.name('Gate')),
      ],
    );
    scope.history.undo();
    expect(
      player.inline!.tracks.map((t) => t.binding),
      everyElement(const TrackBinding.name('Door')),
    );
  });
}

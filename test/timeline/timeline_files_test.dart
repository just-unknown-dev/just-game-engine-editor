// The timeline's files: extracting never writes over one, a save that
// fails keeps the timeline and its changes, a save is whole and never
// in pub's cache, a file outside the project opens read-only, and the
// last of two opens wins.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_game_engine_editor/just_game_engine_editor.dart';
import 'package:just_game_engine_editor/src/timeline/timeline_session.dart';

import '../support/test_scope.dart';

TimelineKey _k(double t, double v) =>
    TimelineKey(time: t, value: v, interpolation: KeyInterpolation.linear);

PropertyTrack _x(
  List<TimelineKey> keys, {
  PropertyTrackMode mode = PropertyTrackMode.absolute,
  TrackBinding binding = TrackBinding.owner,
}) => PropertyTrack(
  component: 'TransformComponent',
  field: 'position',
  channel: 'x',
  mode: mode,
  binding: binding,
  curve: KeyCurve(keys),
);

void main() {
  late Directory root;
  late EditorScope scope;
  late TimelineSession s;
  late Entity door;
  late TransformComponent transform;
  late TimelinePlayerComponent player;

  setUp(() {
    root = Directory.systemTemp.createTempSync('timeline_fixes');
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
    transform = TransformComponent(position: Vector3(40, 0, 0));
    player = TimelinePlayerComponent(
      inline: TimelineAsset(
        duration: 2,
        fps: 10,
        // At t = 1 the door is shown at 100; the scene has it at 40.
        tracks: [
          _x([_k(0, 0), _k(2, 200)]),
        ],
      ),
    );
    door = scope.world.createEntityWithComponents([
      transform,
      player,
    ], name: 'Door');
  });

  group('extract never writes over a file', () {
    test('a name that is taken is refused, and the file is left as it '
        'was', () async {
      await s.follow(door);
      final file = File('${root.path}/assets/timelines/door.timeline.json')
        ..createSync(recursive: true)
        ..writeAsStringSync('{"other": true}');
      expect(s.isTimelineNameTaken('door'), isTrue);
      expect(s.freeTimelineName('door'), 'door_2');

      expect(await s.extractToAsset('door'), isFalse);
      expect(file.readAsStringSync(), '{"other": true}');
      expect(s.message.value, contains('is there already'));
      expect(s.isInline, isTrue, reason: 'still the inline timeline');
      expect(player.timelinePath, isEmpty);
      expect(player.inline, isNotNull);

      expect(await s.extractToAsset(s.freeTimelineName('door')), isTrue);
      expect(player.timelinePath, 'assets/timelines/door_2.timeline.json');
      expect(file.readAsStringSync(), '{"other": true}');
    });

    test('the player\'s change is one step of the editor\'s undo; undone, '
        'the inline timeline shows again', () async {
      await s.follow(door);
      expect(await s.extractToAsset('door'), isTrue);
      scope.history.undo();
      expect(player.timelinePath, isEmpty);
      expect(player.inline, isNotNull);
      await s.resync();
      expect(s.isInline, isTrue);
      expect(identical(s.asset.value, player.inline), isTrue);
    });
  });

  group('a save that fails keeps the timeline and its changes', () {
    test('switching away from a file that cannot be written stays on it, '
        'saying why', () async {
      // A file in the project whose save cannot land: a folder stands
      // where the save writes first.
      const path = 'assets/timelines/ti_stuck.timeline.json';
      File('${root.path}/$path')
        ..createSync(recursive: true)
        ..writeAsStringSync(player.inline!.encode());
      Directory('${root.path}/$path.saving').createSync(recursive: true);
      player.timelinePath = path;
      await s.follow(door);
      expect(s.path, path);
      s.setKey(0, 1, value: 77.0);
      expect(s.isDirty.value, isTrue);

      final other = scope.world.createEntityWithComponents([
        TransformComponent(),
        TimelinePlayerComponent(inline: TimelineAsset(duration: 1)),
      ], name: 'Other');
      await s.follow(other);
      expect(s.owner, door, reason: 'not switched: the changes would go');
      expect(s.isDirty.value, isTrue);
      expect(s.message.value, contains('Could not save'));
      expect(await s.close(), isFalse);
      expect(s.asset.value, isNotNull);
    });

    test('a file outside the project opens read-only, saying so', () async {
      // A name of its own: the folder above is the system's temp folder,
      // which other runs of these tests, side by side, write into too.
      final name =
          'ti_outside_${DateTime.now().microsecondsSinceEpoch}.timeline.json';
      final outside = File('${root.path}/../$name')
        ..createSync(recursive: true)
        ..writeAsStringSync(player.inline!.encode());
      addTearDown(() {
        if (outside.existsSync()) outside.deleteSync();
      });
      player.timelinePath = '../$name';
      await s.follow(door);
      s.setKey(0, 1, value: 77.0);
      expect(s.isDirty.value, isFalse, reason: 'not changed');
      expect(s.message.value, contains('outside the project'));
    });

    test('a message is cleared when another timeline shows', () async {
      await s.follow(door);
      s.message.value = 'old news';
      await s.close();
      expect(s.message.value, isNull);
    });
  });

  test('the last of two opens wins', () async {
    final other = scope.world.createEntityWithComponents([
      TransformComponent(),
      TimelinePlayerComponent(inline: TimelineAsset(duration: 5)),
    ], name: 'Other');
    final first = s.follow(door);
    await s.follow(other);
    await first;
    expect(s.owner, other);
    expect(s.duration, 5);
  });

  test('a file previewed on its own keeps one scratch owner', () async {
    File('${root.path}/a.timeline.json')
      ..createSync(recursive: true)
      ..writeAsStringSync(player.inline!.encode());
    await s.openFile('a.timeline.json');
    s.scrubTo(1);
    final ids = {for (final e in scope.world.entities) e.id};
    s.setKey(0, 1.5, value: 3.0);
    s.setKey(0, 0.5, value: 4.0);
    expect({for (final e in scope.world.entities) e.id}, ids);
    await s.close();
    expect(scope.world.entities.length, ids.length - 1);
  });

  test('a save is whole, and never in pub\'s cache', () async {
    final cache = Directory('${root.path}/Pub/Cache/hosted/shared-1.0.0')
      ..createSync(recursive: true);
    File(
      '${cache.path}/pubspec.yaml',
    ).writeAsStringSync('name: shared\nflutter:\n  assets:\n    - assets/\n');
    File('${cache.path}/assets/a.timeline.json')
      ..createSync(recursive: true)
      ..writeAsStringSync(player.inline!.encode());
    File('${root.path}/.dart_tool/package_config.json')
      ..createSync(recursive: true)
      ..writeAsStringSync(
        jsonEncode({
          'configVersion': 2,
          'packages': [
            {
              'name': 'shared',
              'rootUri': '../Pub/Cache/hosted/shared-1.0.0/',
              'packageUri': 'lib/',
            },
          ],
        }),
      );
    PackageAssetPaths.of(root.path).invalidate();
    expect(await s.openFile('packages/shared/assets/a.timeline.json'), isTrue);
    expect(s.canEdit, isFalse);
    s.setKey(0, 1, value: 9.0);
    expect(s.isDirty.value, isFalse);
    expect(s.message.value, contains('read-only'));

    // A project file: written whole, nothing left beside it.
    File(
      '${root.path}/b.timeline.json',
    ).writeAsStringSync(player.inline!.encode());
    await s.openFile('b.timeline.json');
    s.setKey(0, 1, value: 9.0);
    expect(await s.save(), isTrue);
    expect(File('${root.path}/b.timeline.json.saving').existsSync(), isFalse);
    expect(
      TimelineAsset.parse(
        File('${root.path}/b.timeline.json').readAsStringSync(),
      ).propertyTracks.first.curve.keys,
      hasLength(3),
    );
  });
}

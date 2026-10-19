// The timeline's release fixes: files never written over, saves that fail
// keep their changes, the preview never leaks into the editor's undo, the
// session stops when no dock shows it, and the editing edge cases.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_game_engine_editor/just_game_engine_editor.dart';
import 'package:just_game_engine_editor/src/ui/timeline/timeline_dock.dart';
import 'package:just_game_engine_editor/src/ui/timeline/timeline_item_bar.dart';
import 'package:just_game_engine_editor/src/ui/timeline/timeline_renames.dart';
import 'package:just_game_engine_editor/src/ui/timeline/timeline_session.dart';

import 'support/test_scope.dart';

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

  double x() => transform.position.x;

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

  // An inspector edit as the inspector makes it: what the field holds is
  // the step's "before", whatever a preview put there.
  void inspectorEdit(double to) {
    final before = x();
    scope.history.push(
      CallbackCommand(
        label: 'Change Position',
        onRedo: () => transform.setPositionXY(to, transform.position.y),
        onUndo: () => transform.setPositionXY(before, transform.position.y),
      ),
    );
  }

  group('TI-1 extract never writes over a file', () {
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

  group('TI-9 a save that fails keeps the timeline and its changes', () {
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

  group('TI-2 a session no dock shows', () {
    testWidgets('closing the dock stops recording and ends the preview', (
      tester,
    ) async {
      final session = TimelineSession.of(scope);
      addTearDown(session.dispose);
      scope.sceneState.selectedEntity.value = door;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: TimelineDock(scope: scope)),
        ),
      );
      await tester.pump();
      expect(session.isShown, isTrue);
      session.setRecording(true);
      expect(session.isPreviewing, isTrue);

      await tester.pumpWidget(const SizedBox());
      expect(session.isShown, isFalse);
      expect(session.record.value, isFalse);
      expect(session.isPreviewing, isFalse);
      expect(x(), 40);
    });

    testWidgets('the inspector shows no key button with no dock open', (
      tester,
    ) async {
      final session = TimelineSession.of(scope);
      addTearDown(session.dispose);
      await session.follow(door);
      Future<void> pump() => tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: Column(
                children: buildComponentSections(
                  entity: door,
                  sceneState: scope.sceneState,
                  scope: scope,
                ),
              ),
            ),
          ),
        ),
      );
      await pump();
      expect(
        find.byWidgetPredicate(
          (w) => w.runtimeType.toString() == 'FieldKeyButton',
        ),
        findsNothing,
      );
      session.attachView();
      scope.sceneState.refresh();
      await pump();
      expect(
        find.byWidgetPredicate(
          (w) => w.runtimeType.toString() == 'FieldKeyButton',
        ),
        findsWidgets,
      );
      await session.detachView();
    });
  });

  group('TI-3 the preview never leaks into the editor\'s undo', () {
    test('Record on: the edit is a key; undoing it after Stop leaves the '
        'scene as authored', () async {
      await s.follow(door);
      s.scrubTo(1);
      expect(x(), closeTo(100, 1e-9));
      s.setRecording(true);
      inspectorEdit(150);
      expect(s.captureEdits(), 1);
      expect(
        s.asset.value!.propertyTracks.first.curve.numberAt(1),
        closeTo(150, 1e-9),
      );
      s.stop();
      expect(x(), 40);

      scope.history.undo();
      expect(x(), 40, reason: 'not the 100 the preview showed');
      scope.history.redo();
      expect(x(), 40, reason: 'the edit went to the timeline');
    });

    test('Record off: the edit is the scene\'s, kept when the preview '
        'ends, and undone to what was authored', () async {
      await s.follow(door);
      s.scrubTo(1);
      inspectorEdit(150);
      s.stop();
      expect(x(), 150, reason: 'not thrown away');

      scope.history.undo();
      expect(x(), 40);
      scope.history.redo();
      expect(x(), 150);
    });

    test(
      'a relative track keeps the edit as a move of the scene\'s value',
      () async {
        player.inline = TimelineAsset(
          duration: 2,
          fps: 10,
          tracks: [
            _x([_k(0, 0), _k(2, 200)], mode: PropertyTrackMode.relative),
          ],
        );
        await s.follow(door);
        s.scrubTo(1);
        expect(x(), closeTo(140, 1e-9), reason: '40 + 100');
        inspectorEdit(150); // moved 10 further
        s.stop();
        expect(x(), closeTo(50, 1e-9));
      },
    );
  });

  group('TI-4 what Record does not key', () {
    test('a colour picker trying values out, and an editor undo', () async {
      await s.follow(door);
      s.scrubTo(1);
      s.setRecording(true);

      final preview = LivePreview(
        read: () => transform.position.x,
        write: (v) => transform.setPositionXY(v! as double, 0),
        scope: scope,
      )..show(120.0);
      expect(s.captureEdits(), 0, reason: 'only being tried out');
      preview.restore();
      expect(s.captureEdits(), 0);
      expect(s.asset.value!.propertyTracks.single.curve.keys, hasLength(2));

      // An edit made before, undone while the preview shows: the scene's
      // value now, not a key.
      s.stop();
      inspectorEdit(60);
      s.setRecording(true);
      scope.history.undo();
      expect(s.captureEdits(), 0);
      expect(s.asset.value!.propertyTracks.single.curve.keys, hasLength(2));
      s.stop();
      expect(x(), 40);
    });
  });

  test('TI-5 an entity a track moves can be selected without closing the '
      'timeline', () async {
    final panel = scope.world.createEntityWithComponents([
      TransformComponent(),
    ], name: 'Panel');
    player.inline = TimelineAsset(
      duration: 2,
      tracks: [
        _x([_k(0, 0)], binding: const TrackBinding.name('Panel')),
      ],
    );
    await s.follow(door);
    await s.follow(panel);
    expect(s.owner, door);
    expect(s.asset.value, isNotNull);
    await s.follow(scope.world.createEntity(name: 'Rock'));
    expect(s.asset.value, isNull);
  });

  group('TI-6 paste', () {
    test('only onto a track of the same kind of value, and found again by '
        'what the track is', () async {
      player.inline = TimelineAsset(
        duration: 2,
        fps: 10,
        tracks: [
          _x([_k(0, 5)]),
          PropertyTrack(
            component: 'SpriteComponent',
            field: 'tint',
            channel: '',
            isColor: true,
            curve: KeyCurve([const TimelineKey(time: 0, value: 0xFFFF0000)]),
          ),
        ],
      );
      await s.follow(door);
      s.selection.value = {const TimelineItemRef(0, 0)};
      s.copy();
      s
        ..selectedTrack.value = 1
        ..playhead.value = 1;
      s.paste();
      final tint = s.asset.value!.tracks[1] as PropertyTrack;
      expect(tint.curve.keys, hasLength(1), reason: 'a number is no colour');
      final xs = s.asset.value!.tracks[0] as PropertyTrack;
      expect(xs.curve.keys.map((k) => k.time), [0, 1]);

      // Another timeline: its first track is something else.
      final other = scope.world.createEntityWithComponents([
        TransformComponent(),
        TimelinePlayerComponent(
          inline: TimelineAsset(
            duration: 2,
            fps: 10,
            tracks: [EventTrack(), _x([])],
          ),
        ),
      ], name: 'Other');
      await s.follow(other);
      s.paste(time: 0.5);
      expect((s.asset.value!.tracks[0] as EventTrack).events, isEmpty);
      expect(
        (s.asset.value!.tracks[1] as PropertyTrack).curve.keys.single.time,
        0.5,
      );
    });
  });

  test('TI-7 dragging a marker is one undo step', () async {
    await s.follow(door);
    s.addMarker(0.5, 'M');
    final start = s.beginDrag(label: 'Marker')!;
    var index = 0;
    for (final t in [0.6, 0.8, 1.0, 1.2]) {
      index = s.dragMarker(start, 0, t);
    }
    s.endDrag(start);
    expect(index, 0);
    expect(s.asset.value!.markers.single.time, closeTo(1.2, 1e-9));
    s.undo();
    expect(s.asset.value!.markers.single.time, 0.5);
    s.undo();
    expect(s.asset.value!.markers, isEmpty);
  });

  group('TI-8 trimming a block where it cannot grow', () {
    test('a block past the end, and one shorter than a frame', () async {
      player.inline = TimelineAsset(
        duration: 4,
        fps: 10,
        tracks: [
          AudioTrack(blocks: const [TimelineBlock(start: 3, length: 0.5)]),
        ],
      );
      await s.follow(door);
      s.apply('Length', s.asset.value!.copyWith(duration: 2));
      final start = s.beginDrag()!;
      s.dragTrim(start, const TimelineItemRef(0, 0), 3.3, leadingEdge: false);
      s.dragTrim(start, const TimelineItemRef(0, 0), 1, leadingEdge: true);
      s.endDrag(start);

      s.apply(
        'Short',
        s.asset.value!.copyWith(
          fps: 60,
          tracks: [
            AudioTrack(blocks: const [TimelineBlock(start: 0, length: 1 / 60)]),
          ],
        ),
      );
      s.apply('FPS', s.asset.value!.copyWith(fps: 10));
      final again = s.beginDrag()!;
      s.dragTrim(again, const TimelineItemRef(0, 0), 0.5, leadingEdge: true);
      s.endDrag(again);
      final block = (s.asset.value!.tracks.single as AudioTrack).blocks.single;
      expect(block.start, 0);
      expect(block.end, closeTo(1 / 60, 1e-9), reason: 'its end stayed');
    });
  });

  test('TI-11 a Timeline Player added, and a play range set, are undone '
      'by the editor\'s undo; a grip drag is one step', () async {
    final rock = scope.world.createEntityWithComponents([
      TransformComponent(),
    ], name: 'Rock');
    s.createInlineFor(rock);
    expect(rock.hasComponent<TimelinePlayerComponent>(), isTrue);
    scope.history.undo();
    expect(rock.hasComponent<TimelinePlayerComponent>(), isFalse);
    await s.resync();
    expect(s.asset.value, isNull);

    await s.follow(door);
    s.setPlayRange(0.5, 1.5);
    expect(player.from, 0.5);
    scope.history.undo();
    expect(player.hasRange, isFalse);

    final depth = scope.history.undoDepth;
    final edit = s.beginPlayRangeDrag();
    for (final t in [1.2, 1.4, 0.2]) {
      s.dragPlayRange(t, 1.0);
    }
    s.endPlayRangeDrag(edit);
    expect(scope.history.undoDepth, depth + 1);
    // Dragged past the other end: that end stayed where it was.
    expect((player.from, player.to), (0.2, 1.0));
  });

  test('TI-12 playing tells the panels a dozen times a second, not every '
      'frame', () async {
    await s.follow(door);
    s.play();
    final before = scope.sceneState.revision.value;
    for (var i = 0; i < 10; i++) {
      s.tick(0.01);
    }
    expect(scope.sceneState.revision.value - before, lessThanOrEqualTo(2));
  });

  group('TI-13 numbers that are not numbers', () {
    test('a colour of six digits is opaque; NaN is no value', () {
      expect(TimelineItemBar.parseArgb('FF0000'), 0xFFFF0000);
      expect(TimelineItemBar.parseArgb('#80FF0000'), 0x80FF0000);
      expect(TimelineItemBar.parseArgb('nope'), isNull);
    });

    test('the session refuses a drag to a time that is not a number', () async {
      await s.follow(door);
      s.scrubTo(double.nan);
      expect(s.playhead.value, 0);
      final start = s.beginDrag()!;
      s.dragDuration(start, double.infinity);
      s.endDrag(start);
      expect(s.duration, 2);
      expect(() => s.asset.value!.encode(), returnsNormally);
    });
  });

  test('TI-21 nothing is keyed during a play-test', () async {
    await s.follow(door);
    s.isAuthoring = () => false;
    final definition = scope.definitions.definitionFor(transform)!;
    expect(
      s.keyField(
        door,
        transform,
        definition.fields.firstWhere((f) => f.name == 'position'),
      ),
      isFalse,
    );
    expect(s.canEdit, isFalse, reason: 'an inline timeline is the scene');
  });

  test('TI-22 a key given another key\'s time takes its place', () async {
    player.inline = TimelineAsset(
      duration: 2,
      fps: 10,
      tracks: [
        _x([_k(0, 0), _k(1, 10), _k(2, 20)]),
      ],
    );
    await s.follow(door);
    final track = s.asset.value!.tracks.first as PropertyTrack;
    s.updateKey(
      const TimelineItemRef(0, 2),
      track.curve.keys[2].copyWith(time: 1),
    );
    final keys = (s.asset.value!.tracks.first as PropertyTrack).curve.keys;
    expect(keys.map((k) => k.time), [0, 1]);
    expect(keys[1].value, 20);
  });

  test('TI-30 the last of two opens wins', () async {
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

  test('TI-31 a file previewed on its own keeps one scratch owner', () async {
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

  test('TI-32 renaming an entity takes inline timelines\' tracks with it', () {
    player.inline = TimelineAsset(
      duration: 2,
      tracks: [
        _x([_k(0, 0)], binding: const TrackBinding.name('Lift')),
      ],
    );
    final command = TimelineRenames.commandFor(scope, 'Lift', 'Elevator')!;
    command.redo();
    expect(
      player.inline!.tracks.single.binding,
      const TrackBinding.name('Elevator'),
    );
    command.undo();
    expect(
      player.inline!.tracks.single.binding,
      const TrackBinding.name('Lift'),
    );
    expect(TimelineRenames.commandFor(scope, 'Nobody', 'X'), isNull);
  });

  test('TI-10 a save is whole, and never in pub\'s cache', () async {
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

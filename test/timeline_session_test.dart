// The timeline session: editing with undo, a preview that leaves the scene
// as it was, files and inline timelines — and the dock over it.

import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_game_engine_editor/just_game_engine_editor.dart';
import 'package:just_game_engine_editor/src/ui/timeline/dope_sheet.dart';
import 'package:just_game_engine_editor/src/ui/timeline/timeline_dock.dart';
import 'package:just_game_engine_editor/src/ui/timeline/timeline_session.dart';

import 'support/test_scope.dart';

TimelineKey _k(double t, double v) =>
    TimelineKey(time: t, value: v, interpolation: KeyInterpolation.linear);

TimelineAsset _slide({PropertyTrackMode mode = PropertyTrackMode.relative}) =>
    TimelineAsset(
      duration: 2,
      fps: 10,
      tracks: [
        PropertyTrack(
          component: 'TransformComponent',
          field: 'position',
          channel: 'x',
          mode: mode,
          curve: KeyCurve([_k(0, 0), _k(2, 100)]),
        ),
        EventTrack(events: const [TimelineEvent(time: 1, name: 'half')]),
      ],
    );

void main() {
  setUpAll(registerCoreCodecs);

  late EditorScope scope;
  late TimelineSession session;
  late Directory root;
  late Entity door;
  late TimelinePlayerComponent player;

  double x() => door.getComponent<TransformComponent>()!.position.x;

  setUp(() {
    root = Directory.systemTemp.createTempSync('timeline_session');
    addTearDown(() => root.deleteSync(recursive: true));
    scope = testScope();
    session = TimelineSession(scope, root: root.path);
    addTearDown(session.dispose);
    player = TimelinePlayerComponent(inline: _slide());
    door = scope.world.createEntityWithComponents([
      TransformComponent(position: Vector3(40, 0, 0)),
      player,
    ], name: 'Door');
  });

  group('session', () {
    test('follows the selection: inline, a file, nothing', () async {
      await session.follow(door);
      expect(session.isInline, isTrue);
      expect(session.owner, door);
      expect(session.asset.value!.tracks, hasLength(2));

      File('${root.path}/a.timeline.json')
        ..createSync(recursive: true)
        ..writeAsStringSync(_slide().copyWith(duration: 7).encode());
      player.timelinePath = 'a.timeline.json';
      await session.follow(door);
      expect(session.path, 'a.timeline.json');
      expect(session.duration, 7);

      await session.follow(scope.world.createEntity(name: 'Rock'));
      expect(session.asset.value, isNull);

      player.timelinePath = 'gone.timeline.json';
      await session.follow(door);
      expect(session.asset.value, isNull);
      expect(session.message.value, contains('gone.timeline.json'));
    });

    test('an edit to an inline timeline lands in the player and dirties the '
        'scene; undo takes it back', () async {
      await session.follow(door);
      scope.sceneState.markClean();
      final ref = session.setKey(0, 1.04, value: 30.0)!;
      expect(session.timeOf(ref), 1.0, reason: 'snapped to a frame at 10 fps');
      expect(player.inline!.propertyTracks.first.curve.keys, hasLength(3));
      expect(scope.sceneState.isDirty.value, isTrue);
      expect(session.isDirty.value, isFalse, reason: 'there is no file');

      session.undo();
      expect(player.inline!.propertyTracks.first.curve.keys, hasLength(2));
      session.redo();
      expect(player.inline!.propertyTracks.first.curve.numberAt(1), 30);
    });

    test(
      'a preview shows the timeline and puts the scene back exactly',
      () async {
        await session.follow(door);
        scope.sceneState.markClean();
        session.scrubTo(1);
        expect(x(), closeTo(90, 1e-9), reason: '40 + half of 100');
        expect(session.isPreviewing, isTrue);
        expect(player.suspended, isTrue);
        session.scrubTo(2);
        expect(x(), closeTo(140, 1e-9), reason: 'still measured from 40');

        // An edit mid-preview rebuilds it from the truth, not from 140.
        session.setKey(0, 2, value: 10.0);
        expect(x(), closeTo(50, 1e-9));

        scope.restoreAuthoredState(); // what a save and Play call first
        expect(x(), 40);
        expect(session.isPreviewing, isFalse);
        expect(player.suspended, isFalse);
      },
    );

    test('nothing previews during a play-test', () async {
      await session.follow(door);
      session.isAuthoring = () => false;
      session.scrubTo(1);
      expect(session.playhead.value, 1);
      expect(x(), 40);
    });

    test('playing walks the playhead and stops at the end of a once', () async {
      await session.follow(door);
      session.play();
      session.tick(0.5);
      expect(session.playhead.value, 0.5);
      session.tick(5);
      expect(session.playhead.value, 2);
      expect(session.isPlaying.value, isFalse);
      session.stop();
      expect(x(), 40);
      expect(session.playhead.value, 0);

      session.apply(
        'Wrap',
        session.asset.value!.copyWith(wrap: TimelineWrap.loop),
      );
      session.play();
      session.tick(2.5);
      expect(session.playhead.value, closeTo(0.5, 1e-9));
      expect(session.isPlaying.value, isTrue);
    });

    test(
      'items move together, clamp at the ends, and a drag is one undo',
      () async {
        await session.follow(door);
        final moved = session.moveItems({
          const TimelineItemRef(0, 0),
          const TimelineItemRef(1, 0),
        }, 0.5);
        final asset = session.asset.value!;
        expect(asset.propertyTracks.first.curve.keys.first.time, 0.5);
        expect((asset.tracks[1] as EventTrack).events.single.time, 1.5);
        expect(moved, hasLength(2));

        // The pair spans 0.5–1.5, so it can go one second on and no further.
        session.moveItems(moved, 9);
        expect(
          (session.asset.value!.tracks[1] as EventTrack).events.single.time,
          2,
        );
        session
          ..undo()
          ..undo();

        final start = session.beginDrag()!;
        final refs = {const TimelineItemRef(0, 1)};
        session.dragItems(start, refs, -0.3);
        session.dragItems(start, refs, -0.6);
        session.dragItems(start, refs, -1.0);
        session.endDrag(start);
        expect(
          session.asset.value!.propertyTracks.first.curve.keys[1].time,
          1.0,
        );
        session.undo();
        expect(
          session.asset.value!.propertyTracks.first.curve.keys[1].time,
          2.0,
        );
        expect(session.canUndo, isFalse);

        final still = session.beginDrag()!;
        session.endDrag(still);
        expect(session.canUndo, isFalse, reason: 'a click is not an edit');
      },
    );

    test('removing items and tracks; a locked track is left alone', () async {
      await session.follow(door);
      session.removeItems({const TimelineItemRef(0, 0)});
      expect(
        session.asset.value!.propertyTracks.first.curve.keys,
        hasLength(1),
      );

      final track = session.asset.value!.tracks[1];
      session.replaceTrack(1, track.withBase(locked: true), 'Lock');
      session.removeItems({const TimelineItemRef(1, 0)});
      expect(
        (session.asset.value!.tracks[1] as EventTrack).events,
        hasLength(1),
      );
      expect(session.addEvent(1, 0.5, 'x'), isNull);

      session.removeTrack(0);
      expect(session.asset.value!.tracks.single, isA<EventTrack>());
    });

    test('adding a field makes a track per channel; self position is '
        'relative', () async {
      await session.follow(door);
      final definition = scope.definitions.definitionByType(
        'TransformComponent',
      )!;
      final position = definition.fields.firstWhere(
        (f) => f.name == 'position',
      );
      final rotation = definition.fields.firstWhere(
        (f) => f.name == 'rotation',
      );
      session.addPropertyTracks(TrackBinding.owner, definition.type, position);
      session.addPropertyTracks(
        const TrackBinding.name('Lift'),
        definition.type,
        rotation,
      );
      final tracks = session.asset.value!.propertyTracks.toList();
      // A 2-D scene: a position's x and y, a rotation's angle (its z).
      expect(tracks.map((t) => t.path), [
        'TransformComponent.position.x',
        'TransformComponent.position.y',
        'TransformComponent.rotation.z',
      ], reason: 'x was there already');
      expect(tracks[1].isRelative, isTrue);
      expect(tracks[2].isRelative, isFalse);
      expect(session.asset.value!.validate(), isEmpty);

      // A new key on an empty absolute track takes the field's value now.
      scope.world.createEntityWithComponents([
        TransformComponent(angle: 1.5),
      ], name: 'Lift');
      final index = session.asset.value!.tracks.indexOf(tracks[2]);
      expect(session.valueForNewKey(index, 0), 1.5);
    });

    test('a file is saved on request and on the way out; an inline one can '
        'be extracted', () async {
      await session.follow(door);
      final saved = <String>[];
      session.onSaved = saved.add;
      expect(await session.extractToAsset('Door Open'), isTrue);
      const file = 'assets/timelines/Door_Open.timeline.json';
      expect(player.timelinePath, file);
      expect(player.inline, isNull);
      expect(session.path, file);
      expect(File('${root.path}/$file').existsSync(), isTrue);

      session.setKey(0, 1, value: 5.0);
      expect(session.isDirty.value, isTrue);
      await session.follow(null);
      expect(saved, [file, file]);
      final onDisk = TimelineAsset.parse(
        File('${root.path}/$file').readAsStringSync(),
      );
      expect(onDisk.propertyTracks.first.curve.keys, hasLength(3));
      expect(onDisk.name, 'Door_Open');
    });

    test('an entity with no player gets one', () {
      final rock = scope.world.createEntityWithComponents([
        TransformComponent(),
      ], name: 'Rock');
      session.createInlineFor(rock);
      expect(rock.getComponent<TimelinePlayerComponent>()!.inline, isNotNull);
      expect(session.owner, rock);
      expect(session.asset.value!.tracks, isEmpty);
    });
  });

  group('dock', () {
    Future<void> pumpDock(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1400, 500);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: TimelineDock(scope: scope)),
        ),
      );
      await tester.pump();
      await tester.pump();
    }

    testWidgets('every menu reads against the editor\'s dark menu', (
      tester,
    ) async {
      scope.sceneState.selectedEntity.value = door;
      await pumpDock(tester);
      addTearDown(TimelineSession.of(scope).dispose);

      // A popup takes its text from the ambient Material theme, which here is
      // the light default: black on the near-black menu. Every item has to
      // say what colour it is.
      void expectReadable(String label) {
        final style = tester.widget<Text>(find.text(label).last).style;
        final color = style?.color;
        expect(color, isNotNull, reason: '"$label" has no colour of its own');
        expect(
          (color!.computeLuminance() - EditorTheme.menuBg.computeLuminance())
              .abs(),
          greaterThan(0.4),
          reason: '"$label" does not stand out from the menu',
        );
      }

      Future<void> dismiss() async {
        await tester.tapAt(const Offset(1340, 8));
        await tester.pumpAndSettle();
      }

      await tester.tap(find.text('Add track'));
      await tester.pumpAndSettle();
      for (final item in ['A field…', 'Events', 'Sprite clips', 'Audio']) {
        expectReadable(item);
      }
      await dismiss();

      await tester.tap(find.text('Once ▾'));
      await tester.pumpAndSettle();
      for (final item in ['Loop', 'Ping-pong']) {
        expectReadable(item);
      }
      await dismiss();

      await tester.tap(
        find.textContaining('Position · X'),
        buttons: kSecondaryButton,
      );
      await tester.pumpAndSettle();
      for (final item in ['Rename…', 'Bind to…', 'Delete track']) {
        expectReadable(item);
      }
      await dismiss();
    });

    testWidgets('shows the selected entity\'s tracks; the sheet fills the '
        'width; a click selects and the ruler scrubs', (tester) async {
      scope.sceneState.selectedEntity.value = door;
      await pumpDock(tester);
      final s = TimelineSession.of(scope);
      addTearDown(s.dispose);

      expect(find.textContaining('Inline · Door'), findsOneWidget);
      expect(find.textContaining('Self'), findsOneWidget);
      expect(find.textContaining('Position · X'), findsOneWidget);
      expect(find.text('Events'), findsOneWidget);

      // Fitted: two seconds across the sheet, not "duration + 2 s".
      final sheet = tester.getRect(find.byType(DopeSheet));
      expect(sheet.width, greaterThan(1100));
      expect(s.pixelsPerSecond.value, closeTo((sheet.width - 32) / 2, 1));

      // Rows: 0 is the group, 1 the position track, 2 the events.
      Offset at(double time, int row) => Offset(
        sheet.left + TimelineMetrics.leftInset + time * s.pixelsPerSecond.value,
        sheet.top + (row + 0.5) * TimelineMetrics.rowHeight,
      );
      await tester.tapAt(at(2, 1));
      await tester.pump();
      expect(s.selection.value, {const TimelineItemRef(0, 1)});
      expect(s.playhead.value, 2, reason: 'shown where the key is');
      expect(x(), closeTo(140, 1e-6));

      final ruler = tester.getRect(find.byType(TimelineRuler));
      await tester.tapAt(
        Offset(
          ruler.left + TimelineMetrics.leftInset + s.pixelsPerSecond.value,
          ruler.center.dy,
        ),
      );
      await tester.pump();
      expect(s.playhead.value, closeTo(1, 0.06));

      // Dragging the key is one undoable move.
      await tester.dragFrom(at(2, 1), Offset(-s.pixelsPerSecond.value, 0));
      await tester.pump();
      expect(s.asset.value!.propertyTracks.first.curve.keys[1].time, 1);
      s.undo();
      expect(s.asset.value!.propertyTracks.first.curve.keys[1].time, 2);

      // A box over both rows takes the key at 0 and the event at 1.
      final gesture = await tester.startGesture(
        at(-0.015, 1) + const Offset(0, -8),
      );
      await gesture.moveTo(at(1.1, 2) + const Offset(0, 8));
      await tester.pump();
      await gesture.up();
      await tester.pump();
      expect(s.selection.value, {
        const TimelineItemRef(0, 0),
        const TimelineItemRef(1, 0),
      });

      await tester.pumpWidget(const SizedBox());
      expect(x(), 40, reason: 'closing the dock ends the preview');
    });

    testWidgets('nothing selected, and an entity with no player', (
      tester,
    ) async {
      await pumpDock(tester);
      addTearDown(TimelineSession.of(scope).dispose);
      expect(find.text('No timeline'), findsOneWidget);

      final rock = scope.world.createEntityWithComponents([
        TransformComponent(),
      ], name: 'Rock');
      scope.sceneState.selectedEntity.value = rock;
      await tester.pump();
      await tester.pump();
      expect(find.text('Rock plays no timeline'), findsOneWidget);

      // The call to action states the editor's own colours: the ambient
      // Material theme is the light default, whose primary is not ours.
      final button = tester.widget<TextButton>(
        find.ancestor(
          of: find.text('Add a Timeline Player'),
          matching: find.byWidgetPredicate((w) => w is TextButton),
        ),
      );
      final style = button.style!;
      const dark = <WidgetState>{};
      expect(style.backgroundColor!.resolve(dark), EditorTheme.buttonBg);
      expect(style.foregroundColor!.resolve(dark), EditorTheme.primaryBright);

      await tester.tap(find.text('Add a Timeline Player'));
      await tester.pump();
      expect(rock.hasComponent<TimelinePlayerComponent>(), isTrue);
      expect(find.text('Add track'), findsOneWidget);
    });
  });
}

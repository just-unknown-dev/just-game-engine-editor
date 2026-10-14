// Editing many keys at once: nudge, stretch, copy and paste, duplicate,
// ripple delete — and markers, the work range, and the dock's keys.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_game_engine_editor/just_game_engine_editor.dart';
import 'package:just_game_engine_editor/src/ui/timeline/dope_sheet.dart';
import 'package:just_game_engine_editor/src/ui/timeline/timeline_dock.dart';
import 'package:just_game_engine_editor/src/ui/timeline/timeline_session.dart';

import 'support/test_scope.dart';

TimelineKey _k(double t, double v) =>
    TimelineKey(time: t, value: v, interpolation: KeyInterpolation.linear);

PropertyTrack _track(String channel, List<TimelineKey> keys) => PropertyTrack(
  component: 'TransformComponent',
  field: 'position',
  channel: channel,
  curve: KeyCurve(keys),
);

void main() {
  late EditorScope scope;
  late TimelineSession s;
  late Entity entity;

  List<double> times(int track) => [
    for (var i = 0; i < s.itemCount(track); i++)
      s.timeOf(TimelineItemRef(track, i))!,
  ];

  Future<void> open(TimelineSession session) async {
    s = session;
    entity = scope.world.createEntityWithComponents([
      TransformComponent(),
      TimelinePlayerComponent(
        inline: TimelineAsset(
          duration: 4,
          fps: 10,
          tracks: [
            _track('x', [_k(0, 0), _k(1, 10), _k(2, 20), _k(3, 30)]),
            _track('y', [_k(0.5, 5)]),
            EventTrack(
              events: const [
                TimelineEvent(time: 1, name: 'a'),
                TimelineEvent(time: 3, name: 'b'),
              ],
            ),
          ],
        ),
      ),
    ], name: 'Hero');
    await s.follow(entity);
  }

  group('session', () {
    setUp(() async {
      scope = testScope();
      final root = Directory.systemTemp.createTempSync('timeline_editing');
      addTearDown(() => root.deleteSync(recursive: true));
      final session = TimelineSession(scope, root: root.path);
      addTearDown(session.dispose);
      await open(session);
    });

    test('nudge moves by frames even with snapping off', () {
      s.snap.value = false;
      s.selection.value = {const TimelineItemRef(0, 1)};
      s.nudge(3);
      expect(times(0), [0, 1.3, 2, 3]);
      expect(s.snap.value, isFalse);
      s.nudge(-13);
      expect(times(0), [0, 2, 3], reason: 'dropped on the key at 0: replaced');
    });

    test('stretching keeps the first item still', () {
      final moved = s.scaleItems({
        const TimelineItemRef(0, 1),
        const TimelineItemRef(0, 2),
        const TimelineItemRef(2, 0),
      }, 1.5);
      expect(times(0), [0, 1, 2.5, 3]);
      expect(times(2), [1, 3]);
      expect(moved, hasLength(3));
      s.undo();
      expect(times(0), [0, 1, 2, 3]);
    });

    test('copy and paste: back where it came from, or onto the selected '
        'track', () {
      s.selection.value = {
        const TimelineItemRef(0, 1),
        const TimelineItemRef(0, 2),
        const TimelineItemRef(2, 0),
      };
      s.copy();
      s.scrubTo(2.5);
      final pasted = s.paste();
      expect(times(0), [0, 1, 2, 2.5, 3, 3.5]);
      expect(times(2), [1, 2.5, 3]);
      expect(pasted, hasLength(3));
      expect(s.selection.value, pasted);
      s.undo();

      // Keys from one track go to the selected one: x's motion onto y.
      s.selection.value = {
        const TimelineItemRef(0, 2),
        const TimelineItemRef(0, 3),
      };
      s.copy();
      s.selectedTrack.value = 1;
      s.paste(time: 1);
      expect(times(1), [0.5, 1, 2]);
      expect(s.asset.value!.propertyTracks.elementAt(1).curve.numberAt(2), 30);
      expect(times(0), [0, 1, 2, 3], reason: 'x is as it was');

      // Keys do not paste onto an event track.
      s.selectedTrack.value = 2;
      s.paste(time: 0);
      expect(times(2), [1, 3]);
    });

    test('duplicate lands just after the selection', () {
      s.selection.value = {
        const TimelineItemRef(0, 0),
        const TimelineItemRef(0, 1),
      };
      s.selectedTrack.value = 1;
      s.duplicate();
      expect(times(0), [0, 1, 1.1, 2, 2.1, 3]);
      expect(s.selectedTrack.value, 1);
    });

    test('ripple delete pulls the rest in, track by track', () {
      s.rippleDelete({
        const TimelineItemRef(0, 1),
        const TimelineItemRef(2, 0),
      });
      expect(times(0), [0, 1, 2], reason: 'what was at 2 and 3');
      expect(times(2), [1], reason: 'b slid back to where a was');
      expect(times(1), [0.5], reason: 'a track nothing was deleted on');
    });

    test('markers and the work range', () {
      s.addMarker(2.04, 'land');
      s.addMarker(1, 'jump');
      expect(s.asset.value!.markers.map((m) => '${m.name}@${m.time}'), [
        'jump@1.0',
        'land@2.0',
      ]);
      s.updateMarker(0, time: 3, name: 'late');
      expect(s.asset.value!.markers.last.name, 'late');
      s.removeMarker(0);
      expect(s.asset.value!.markers.single.name, 'late');

      s.setWorkRange(3, 1);
      expect(s.workRange.value, (1.0, 3.0));
      s.play();
      expect(s.playhead.value, 1, reason: 'play starts inside the range');
      s.tick(2.5);
      expect(s.playhead.value, closeTo(1.5, 1e-9), reason: 'and loops in it');
      s.setWorkRange(2, 2);
      expect(s.workRange.value, isNull);
    });
  });

  group('the play range', () {
    setUp(() async {
      scope = testScope();
      final root = Directory.systemTemp.createTempSync('timeline_range');
      addTearDown(() => root.deleteSync(recursive: true));
      final session = TimelineSession(scope, root: root.path);
      addTearDown(session.dispose);
      await open(session);
    });

    test('the work range becomes the player\'s, and the scene keeps it', () {
      final player = entity.getComponent<TimelinePlayerComponent>()!;
      expect(player.hasRange, isFalse);
      expect(s.applyWorkRangeToPlayer(), isFalse, reason: 'no work range yet');

      scope.sceneState.markClean();
      s.setWorkRange(1, 3);
      expect(
        scope.sceneState.isDirty.value,
        isFalse,
        reason: 'the work range alone is the editor\'s business',
      );

      expect(s.applyWorkRangeToPlayer(), isTrue);
      expect((player.from, player.to), (1.0, 3.0));
      expect(player.playRange, (1.0, 3.0));
      expect(
        scope.sceneState.isDirty.value,
        isTrue,
        reason: 'now the scene holds it',
      );

      // And back again, to see or adjust what the game will play.
      s.workRange.value = null;
      expect(s.workRangeFromPlayer(), isTrue);
      expect(s.workRange.value, (1.0, 3.0));

      expect(s.clearPlayRange(), isTrue);
      expect(player.hasRange, isFalse);
      expect(s.clearPlayRange(), isFalse, reason: 'nothing left to clear');
    });

    test('a timeline opened from a file has no player to give it to', () async {
      await s.close();
      expect(s.player, isNull);
      expect(s.applyWorkRangeToPlayer(), isFalse);
      expect(s.workRangeFromPlayer(), isFalse);
      expect(s.clearPlayRange(), isFalse);
    });
  });

  group('dock keys', () {
    testWidgets('the keys drive the session', (tester) async {
      scope = testScope();
      await open(TimelineSession.of(scope));
      addTearDown(s.dispose);
      scope.sceneState.selectedEntity.value = entity;
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

      final sheet = tester.getRect(find.byType(DopeSheet));
      // Scroll counts: the sheet stays where it was put, and pressing End
      // moves it.
      Offset at(double time, int row) => Offset(
        sheet.left +
            TimelineMetrics.leftInset +
            (time - s.scrollTime.value) * s.pixelsPerSecond.value,
        sheet.top + (row + 0.5) * TimelineMetrics.rowHeight,
      );
      Future<void> press(
        LogicalKeyboardKey key, {
        bool ctrl = false,
        bool shift = false,
      }) async {
        if (ctrl) await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
        if (shift) await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
        await tester.sendKeyEvent(key);
        if (shift) await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
        if (ctrl) await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
        await tester.pump();
      }

      await tester.tapAt(at(2, 1)); // x's key at 2 s; the dock takes focus
      await tester.pump();
      expect(s.selection.value, {const TimelineItemRef(0, 2)});

      // Its keys are its own: the editor, which hears every key first, does
      // not act on them as well (Delete would delete the selected entity).
      bool claimed(LogicalKeyboardKey key) => EditorKeyClaim.focusedClaims(
        KeyDownEvent(
          physicalKey: PhysicalKeyboardKey.keyA,
          logicalKey: key,
          timeStamp: Duration.zero,
        ),
      );
      for (final key in [
        LogicalKeyboardKey.delete,
        LogicalKeyboardKey.keyR,
        LogicalKeyboardKey.keyF,
        LogicalKeyboardKey.arrowLeft,
        LogicalKeyboardKey.space,
      ]) {
        expect(claimed(key), isTrue, reason: key.debugName);
      }
      expect(claimed(LogicalKeyboardKey.keyW), isFalse, reason: 'not its key');
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      expect(claimed(LogicalKeyboardKey.keyZ), isTrue, reason: 'its own undo');
      expect(claimed(LogicalKeyboardKey.keyS), isFalse, reason: 'saves both');
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);

      await press(LogicalKeyboardKey.arrowRight);
      expect(times(0), [0, 1, 2.1, 3]);
      await press(LogicalKeyboardKey.arrowLeft);
      expect(times(0), [0, 1, 2, 3]);

      await press(LogicalKeyboardKey.keyC, ctrl: true);
      await press(LogicalKeyboardKey.end);
      await press(LogicalKeyboardKey.keyV, ctrl: true);
      expect(times(0), [0, 1, 2, 3, 4]);

      await press(LogicalKeyboardKey.delete);
      expect(times(0), [0, 1, 2, 3]);
      await press(LogicalKeyboardKey.keyZ, ctrl: true);
      expect(times(0), [0, 1, 2, 3, 4]);

      await tester.tapAt(at(1, 1));
      await tester.pump();
      await press(LogicalKeyboardKey.delete, shift: true);
      expect(times(0), [0, 1, 2, 3], reason: 'rippled: 2,3,4 slid in by one');

      await press(LogicalKeyboardKey.home);
      await press(LogicalKeyboardKey.period);
      expect(s.playhead.value, closeTo(0.1, 1e-9));
      await press(LogicalKeyboardKey.keyM);
      expect(s.asset.value!.markers.single.time, closeTo(0.1, 1e-9));
      await press(LogicalKeyboardKey.bracketLeft);
      expect(s.workRange.value, (0.1, 4.0));
      await press(LogicalKeyboardKey.backslash);
      expect(s.workRange.value, isNull);

      await press(LogicalKeyboardKey.keyA, ctrl: true);
      expect(s.selection.value, hasLength(4 + 1 + 2));
      await press(LogicalKeyboardKey.escape);
      expect(s.selection.value, isEmpty);

      // K keys the selected track at the playhead.
      s.selectedTrack.value = 1;
      await press(LogicalKeyboardKey.keyK);
      expect(times(1), [0.1, 0.5]);

      // Alt-drag the last of a selection stretches it about the first.
      await tester.tapAt(at(1, 1));
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.tapAt(at(2, 1));
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pump();
      expect(s.selection.value, hasLength(2));
      await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
      await tester.dragFrom(at(2, 1), Offset(0.5 * s.pixelsPerSecond.value, 0));
      await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
      await tester.pump();
      expect(times(0), [0, 1, 2.5, 3]);

      await tester.pumpWidget(const SizedBox());
    });
  });

  test('the timeline commands are registered and run', () async {
    scope = testScope();
    await open(TimelineSession.of(scope));
    addTearDown(s.dispose);
    final ids = [for (final c in scope.commands.all) c.id];
    expect(
      ids,
      containsAll(['timeline.play', 'timeline.key', 'timeline.paste']),
    );
  });
}

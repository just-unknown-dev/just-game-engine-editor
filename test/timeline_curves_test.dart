// The curve editor: keys move in time and value, handles shape the curve.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_game_engine_editor/just_game_engine_editor.dart';
import 'package:just_game_engine_editor/src/ui/timeline/curve_view.dart';
import 'package:just_game_engine_editor/src/ui/timeline/dope_sheet.dart';
import 'package:just_game_engine_editor/src/ui/timeline/timeline_dock.dart';
import 'package:just_game_engine_editor/src/ui/timeline/timeline_session.dart';

import 'support/test_scope.dart';

void main() {
  late EditorScope scope;
  late TimelineSession s;

  TimelineAsset asset() => TimelineAsset(
    duration: 2,
    fps: 10,
    tracks: [
      PropertyTrack(
        component: 'TransformComponent',
        field: 'position',
        channel: 'y',
        curve: KeyCurve([
          const TimelineKey(time: 0, value: 0.0),
          const TimelineKey(time: 1, value: 100.0),
          const TimelineKey(time: 2, value: 0.0),
        ]).withAutoTangents(),
      ),
      EventTrack(),
    ],
  );

  PropertyTrack track() => s.asset.value!.propertyTracks.first;

  group('session', () {
    setUp(() async {
      scope = testScope();
      s = TimelineSession(scope, root: '.');
      addTearDown(s.dispose);
      final entity = scope.world.createEntityWithComponents([
        TransformComponent(),
        TimelinePlayerComponent(inline: asset()),
      ]);
      await s.follow(entity);
    });

    test('keys drag in time and value as one undo step', () {
      final start = s.beginDrag()!;
      final refs = {const TimelineItemRef(0, 1)};
      s.dragKeys(start, refs, 0.2, 10);
      s.dragKeys(start, refs, 0.5, -40);
      s.endDrag(start);
      expect(track().curve.keys[1].time, 1.5);
      expect(track().curve.keys[1].value, 60);
      s.undo();
      expect(track().curve.keys[1].value, 100);
      expect(s.canUndo, isFalse);
    });

    test('a handle drag aligns the other, is kept inside the segment, and '
        'changes the curve', () {
      final before = track().curve.numberAt(1.5);
      final start = s.beginDrag()!;
      const ref = TimelineItemRef(0, 1);
      s.dragTangent(start, ref, true, const KeyTangent(0.5, 50));
      s.endDrag(start);
      final key = track().curve.keys[1];
      expect(key.tangentMode, TangentMode.aligned);
      expect(key.outTangent, const KeyTangent(0.5, 50));
      expect(key.inTangent.dv / key.inTangent.dt, closeTo(100, 1e-9));
      expect(key.inTangent.dt, lessThan(0), reason: 'its own reach, kept');
      expect(track().curve.numberAt(1.5), greaterThan(before));
      expect(track().curve.numberAt(1), 100, reason: 'still through the key');

      // Past the next key, or backwards: held inside the segment.
      final again = s.beginDrag()!;
      s.dragTangent(again, ref, true, const KeyTangent(9, 0));
      expect(track().curve.keys[1].outTangent.dt, 1);
      s.dragTangent(again, ref, true, const KeyTangent(-3, 0));
      expect(track().curve.keys[1].outTangent.dt, greaterThan(0));
      s.endDrag(again);

      // Broken apart, the other stays where it is — and an automatic pass
      // over the curve leaves both alone.
      final inBefore = track().curve.keys[1].inTangent;
      final third = s.beginDrag()!;
      s.dragTangent(
        third,
        ref,
        true,
        const KeyTangent(0.3, -80),
        breakApart: true,
      );
      s.endDrag(third);
      expect(track().curve.keys[1].tangentMode, TangentMode.broken);
      expect(track().curve.keys[1].inTangent, inBefore);
      s.setKey(0, 0.5, value: 1.0);
      expect(track().curve.keys[2].outTangent, const KeyTangent(0.3, -80));
    });
  });

  testWidgets('Tab swaps the sheet for curves; keys and handles drag there', (
    tester,
  ) async {
    scope = testScope();
    s = TimelineSession.of(scope);
    addTearDown(s.dispose);
    final entity = scope.world.createEntityWithComponents([
      TransformComponent(),
      TimelinePlayerComponent(inline: asset()),
    ], name: 'Ball');
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

    await tester.tap(find.byTooltip('Edit curves  (Tab)'));
    await tester.pump();
    expect(find.byType(CurveView), findsOneWidget);
    expect(find.byType(DopeSheet), findsNothing);

    final view = tester.state<CurveViewState>(find.byType(CurveView));
    // The item bar comes and goes above the view: measured each time.
    Offset origin() => tester.getTopLeft(find.byType(CurveView));
    expect(view.shown, [0], reason: 'the event track has no curve');

    // The peak, dragged down by a quarter of the range and right by 0.3 s.
    final peak = origin() + view.keyPoint(track().curve.keys[1]);
    final down = (view.yOf(75) - view.yOf(100));
    await tester.dragFrom(peak, Offset(0.3 * s.pixelsPerSecond.value, down));
    await tester.pump();
    final moved = track().curve.keys[1];
    expect(moved.time, closeTo(1.3, 1e-9));
    expect(moved.number, closeTo(75, 1.5));
    expect(s.selection.value, {const TimelineItemRef(0, 1)});

    // Selected, it shows its handles; dragging one reshapes the curve.
    expect(view.handlesOf(track().curve, 1), [
      CurveHandle.incoming,
      CurveHandle.outgoing,
    ]);
    final out = origin() + view.handlePoint(moved, CurveHandle.outgoing);
    await tester.dragFrom(out, const Offset(0, -60));
    await tester.pump();
    final shaped = track().curve.keys[1];
    expect(shaped.tangentMode, TangentMode.aligned);
    expect(shaped.outTangent.dv, greaterThan(0));
    expect(shaped.time, moved.time, reason: 'the key did not move');

    // A double click on the curve adds a key there.
    final on =
        origin() + Offset(view.xOf(0.5), view.yOf(track().curve.numberAt(0.5)));
    await tester.tapAt(on);
    await tester.pump(const Duration(milliseconds: 60));
    await tester.tapAt(on);
    await tester.pump();
    expect(track().curve.keys.map((k) => k.time), [0, 0.5, 1.3, 2]);

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(find.byType(DopeSheet), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });
}

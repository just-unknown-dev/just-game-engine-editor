// Blocks and events in the Timeline dock: made with a double click, moved,
// trimmed by an edge, and edited in the item bar.

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_game_engine_editor/just_game_engine_editor.dart';
import 'package:just_game_engine_editor/src/ui/timeline/dope_sheet.dart';
import 'package:just_game_engine_editor/src/ui/timeline/timeline_dock.dart';
import 'package:just_game_engine_editor/src/ui/timeline/timeline_item_bar.dart';
import 'package:just_game_engine_editor/src/ui/timeline/timeline_session.dart';

import 'support/test_scope.dart';

void main() {
  late EditorScope scope;
  late TimelineSession s;
  late Entity hero;

  Future<void> pumpDock(WidgetTester tester) async {
    scope = testScope();
    s = TimelineSession.of(scope);
    addTearDown(s.dispose);
    hero = scope.world.createEntityWithComponents([
      TransformComponent(),
      SpriteAnimationComponent(atlasPath: 'hero.json', clip: 'idle'),
      TimelinePlayerComponent(
        inline: TimelineAsset(
          duration: 4,
          fps: 10,
          tracks: [
            SpriteClipTrack(
              blocks: const [TimelineBlock(start: 1, length: 1, value: 'run')],
            ),
            CameraShotTrack(),
            EventTrack(),
            PropertyTrack(
              component: 'TransformComponent',
              field: 'rotation',
              curve: KeyCurve([
                const TimelineKey(time: 0, value: 0.0),
                const TimelineKey(time: 2, value: 3.0),
              ]),
            ),
          ],
        ),
      ),
    ], name: 'Hero');
    scope.world.createEntityWithComponents([
      TransformComponent(),
      VirtualCameraComponent(),
    ], name: 'Close-up');
    scope.sceneState.selectedEntity.value = hero;
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

  BlockTrack blocks(int i) => s.asset.value!.tracks[i] as BlockTrack;

  testWidgets('a block is made, moved and trimmed in the sheet', (
    tester,
  ) async {
    await pumpDock(tester);
    // The item bar comes and goes, so the sheet is measured each time.
    Offset at(double time, int row) {
      final sheet = tester.getRect(find.byType(DopeSheet));
      return Offset(
        sheet.left + TimelineMetrics.leftInset + time * s.pixelsPerSecond.value,
        sheet.top + (row + 0.5) * TimelineMetrics.rowHeight,
      );
    }

    // Rows: 0 group, 1 sprite clips, 2 camera shots, 3 events, 4 rotation.
    await tester.tapAt(at(3, 2));
    await tester.pump(const Duration(milliseconds: 60));
    await tester.tapAt(at(3, 2));
    await tester.pump();
    final shot = blocks(1).blocks.single;
    expect(shot.start, 3);
    expect(shot.amount, CameraShotTrack.defaultBoost);
    expect(shot.end, lessThanOrEqualTo(5));
    expect(s.selection.value, {const TimelineItemRef(1, 0)});
    expect(find.byType(TimelineItemBar), findsOneWidget);

    // Dragging the middle moves it; an edge trims it.
    await tester.pump(const Duration(milliseconds: 400));
    final pps = s.pixelsPerSecond.value;
    await tester.dragFrom(at(1.5, 1), Offset(pps, 0));
    await tester.pump();
    expect(blocks(0).blocks.single.start, 2);
    expect(blocks(0).blocks.single.length, 1);

    await tester.dragFrom(at(3, 1) - const Offset(1, 0), Offset(0.5 * pps, 0));
    await tester.pump();
    expect(blocks(0).blocks.single.start, 2, reason: 'the start stayed');
    expect(blocks(0).blocks.single.length, closeTo(1.5, 1e-9));

    await tester.dragFrom(at(2, 1) + const Offset(1, 0), Offset(0.4 * pps, 0));
    await tester.pump();
    expect(blocks(0).blocks.single.start, closeTo(2.4, 1e-9));
    expect(
      blocks(0).blocks.single.end,
      closeTo(3.5, 1e-9),
      reason: 'the end stayed',
    );

    // An edge cannot cross the other: a frame is the least a block can be.
    await tester.dragFrom(at(2.4, 1) + const Offset(1, 0), Offset(3 * pps, 0));
    await tester.pump();
    expect(blocks(0).blocks.single.length, closeTo(0.1, 1e-9));
    s.undo();
    expect(
      blocks(0).blocks.single.start,
      closeTo(2.4, 1e-9),
      reason: 'one step',
    );

    // Over an edge the pointer says so. Read from the tree, not from the
    // global mouse tracker, which every test in the process shares.
    Iterable<MouseCursor> cursors() => tester
        .widgetList<MouseRegion>(
          find.descendant(
            of: find.byType(DopeSheet),
            matching: find.byType(MouseRegion),
          ),
        )
        .map((m) => m.cursor);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: at(3, 3));
    addTearDown(mouse.removePointer);
    await mouse.moveTo(at(3.5, 1));
    await tester.pump();
    expect(cursors(), contains(SystemMouseCursors.resizeLeftRight));
    await mouse.moveTo(at(3.5, 3));
    await tester.pump();
    expect(
      cursors(),
      isNot(contains(SystemMouseCursors.resizeLeftRight)),
      reason: 'away from an edge it is an ordinary pointer again',
    );

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('the timeline\'s end is a handle: it says so, and dragging it '
      'sets the length', (tester) async {
    await pumpDock(tester);
    expect(s.duration, 4);
    // A zoom of its own, so every time below has a place on screen even
    // after the timeline grows.
    s.pixelsPerSecond.value = 100;
    await tester.pump();

    double xOf(double time, Rect of) =>
        of.left +
        TimelineMetrics.leftInset +
        (time - s.scrollTime.value) * s.pixelsPerSecond.value;

    // Hovering the end asks for a resize, over the sheet and over the ruler.
    final sheet = tester.getRect(find.byType(DopeSheet));
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: sheet.center);
    addTearDown(mouse.removePointer);

    Iterable<MouseCursor> cursorsIn(Type widget) => tester
        .widgetList<MouseRegion>(
          find.descendant(
            of: find.byType(widget),
            matching: find.byType(MouseRegion),
          ),
        )
        .map((m) => m.cursor);

    await mouse.moveTo(Offset(xOf(2, sheet), sheet.top + 60));
    await tester.pump();
    expect(
      cursorsIn(DopeSheet),
      isNot(contains(SystemMouseCursors.resizeLeftRight)),
      reason: 'in the middle of the sheet it is an ordinary pointer',
    );
    await mouse.moveTo(Offset(xOf(4, sheet), sheet.top + 60));
    await tester.pump();
    expect(cursorsIn(DopeSheet), contains(SystemMouseCursors.resizeLeftRight));

    final ruler = tester.getRect(find.byType(TimelineRuler));
    await mouse.moveTo(Offset(xOf(4, ruler), ruler.center.dy));
    await tester.pump();
    expect(
      cursorsIn(TimelineRuler),
      contains(SystemMouseCursors.resizeLeftRight),
    );

    // Dragging it out makes the timeline longer, and back again shorter.
    await tester.dragFrom(
      Offset(xOf(4, ruler), ruler.center.dy),
      Offset(2 * s.pixelsPerSecond.value, 0),
    );
    await tester.pump();
    expect(s.duration, 6);

    await tester.dragFrom(
      Offset(xOf(6, sheet), sheet.top + 60),
      Offset(-3 * s.pixelsPerSecond.value, 0),
    );
    await tester.pump();
    expect(s.duration, 3);
    expect(
      s.asset.value!.propertyTracks.first.curve.keys.last.time,
      2,
      reason: 'keys past the new end are kept, not cut',
    );

    // However many frames it took, it is one step to undo.
    s.undo();
    expect(s.duration, 6);
    s.undo();
    expect(s.duration, 4);

    // It cannot be dragged away to nothing.
    await tester.dragFrom(
      Offset(xOf(4, ruler), ruler.center.dy),
      Offset(-9 * s.pixelsPerSecond.value, 0),
    );
    await tester.pump();
    expect(
      s.duration,
      closeTo(1 / s.fps, 1e-9),
      reason: 'a frame at the least',
    );

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('the play range is typed in the header and dragged on the '
      'ruler', (tester) async {
    await pumpDock(tester);
    final player = hero.getComponent<TimelinePlayerComponent>()!;
    expect(player.hasRange, isFalse);
    expect(find.text('Plays'), findsOneWidget, reason: 'it is on the bar');

    // The bar reads from the left. Its controls scroll when the dock is
    // narrow, and a scroll view set to start at its end would push them all
    // to the right when there is room to spare.
    expect(
      tester.getRect(find.textContaining('Inline ·')).left -
          tester.getRect(find.byType(EditorToolbar)).left,
      lessThan(20),
    );

    // Each box says what it is, so the test asks for them the way a person
    // would: by what the tooltip promises.
    Finder box(String tip) => find.descendant(
      of: find.byTooltip(tip),
      matching: find.byType(TextField),
    );

    // The header counts in frames while the ruler does: 10 fps, 4 s long.
    expect(s.showFrames.value, isTrue);
    final length = tester
        .widget<TextField>(box('How long the timeline is, in frames'))
        .controller!;
    expect(length.text, '40', reason: 'frames, not 4 seconds');

    // A timeline begins at zero and so does its play range, so the bar
    // shows how far it plays and no more.
    expect(find.text('to'), findsOneWidget);
    expect(
      box('From here, in frames'),
      findsNothing,
      reason: 'a start of zero is not worth a box',
    );

    // Typing sets what the entity plays, and the scene holds it.
    scope.sceneState.markClean();
    await tester.enterText(box('To here, in frames'), '30');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect((player.from, player.to), (0.0, 3.0), reason: '30 frames at 10 fps');
    expect(scope.sceneState.isDirty.value, isTrue);
    expect(s.playRange, (0.0, 3.0));

    // Give it a start — from the ruler, or the player itself — and the box
    // for it appears.
    s.setPlayRange(1, 3);
    await tester.pump();
    expect(box('From here, in frames'), findsOneWidget);
    await tester.enterText(box('From here, in frames'), '10');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect((player.from, player.to), (1.0, 3.0));

    // Its ends are grips on the ruler.
    final ruler = tester.getRect(find.byType(TimelineRuler));
    double xOf(double time) =>
        ruler.left +
        TimelineMetrics.leftInset +
        (time - s.scrollTime.value) * s.pixelsPerSecond.value;
    await tester.dragFrom(
      Offset(xOf(3), ruler.center.dy),
      Offset(-s.pixelsPerSecond.value, 0),
    );
    await tester.pump();
    expect((player.from, player.to), (1.0, 2.0), reason: 'the end came back');

    await tester.dragFrom(
      Offset(xOf(1), ruler.center.dy),
      Offset(-s.pixelsPerSecond.value, 0),
    );
    await tester.pump();
    expect(player.from, closeTo(0, 1e-9));

    // Dragging one end past the other swaps them rather than failing.
    await tester.dragFrom(
      Offset(xOf(0), ruler.center.dy),
      Offset(3 * s.pixelsPerSecond.value, 0),
    );
    await tester.pump();
    expect(player.from, closeTo(2, 1e-9));
    expect(player.to, closeTo(3, 1e-9));

    // The cross gives the whole timeline back.
    await tester.tap(find.byTooltip('Play the whole timeline again'));
    await tester.pump();
    expect(player.hasRange, isFalse);
    expect(s.playRange, isNull);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('the item bar edits a block, an event and a key', (tester) async {
    await pumpDock(tester);

    Future<void> type(String label, String text) async {
      final field = find.descendant(
        of: find.ancestor(
          of: find.text(label),
          matching: find.byType(TimelineField),
        ),
        matching: find.byType(TextField),
      );
      await tester.enterText(field, text);
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
    }

    // A block: its clip, speed and length.
    s.selection.value = {const TimelineItemRef(0, 0)};
    await tester.pump();
    expect(find.text('Clip'), findsOneWidget);
    expect(find.text('Priority boost'), findsNothing);
    await type('Clip', 'jump');
    await type('Speed', '2');
    await type('Length', '15');
    final block = blocks(0).blocks.single;
    expect([block.value, block.speed, block.length], ['jump', 2.0, 1.5]);
    await tester.tap(find.text('Loop'));
    await tester.pump();
    expect(blocks(0).blocks.single.loop, isTrue);

    // A camera shot offers the scene's virtual cameras.
    s.addBlock(1, 0);
    s.selection.value = {const TimelineItemRef(1, 0)};
    await tester.pump();
    expect(find.text('Priority boost'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.arrow_drop_down_circle_outlined));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Close-up').last);
    await tester.pumpAndSettle();
    expect(blocks(1).blocks.single.value, 'Close-up');

    // An event: name, payload, and whether it is a signal.
    final ref = s.addEvent(2, 1, 'step')!;
    s.selection.value = {ref};
    await tester.pump();
    await type('Event', 'land');
    await type('Payload', 'hard');
    await tester.tap(find.text('Signal'));
    await tester.pump();
    final event = (s.asset.value!.tracks[2] as EventTrack).events.single;
    expect([event.name, event.payload, event.signal], ['land', 'hard', true]);
    await type('Time', '25');
    expect((s.asset.value!.tracks[2] as EventTrack).events.single.time, 2.5);

    // A key: value, how it reaches the next, and its time.
    s.selection.value = {const TimelineItemRef(3, 0)};
    await tester.pump();
    await type('Value', '1.25');
    await tester.tap(find.text('Smooth ▾'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('easeOutBounce').last);
    await tester.pumpAndSettle();
    var key = s.asset.value!.propertyTracks.single.curve.keys.first;
    expect(key.value, 1.25);
    expect(key.interpolation, KeyInterpolation.eased);
    expect(key.easing, 'easeOutBounce');
    expect(find.text('Handles'), findsNothing, reason: 'an eased key has none');

    await type('Time', '30');
    final keys = s.asset.value!.propertyTracks.single.curve.keys;
    expect(keys.map((k) => k.time), [2, 3]);
    expect(s.selection.value, {
      const TimelineItemRef(3, 1),
    }, reason: 'followed');

    await tester.pumpWidget(const SizedBox());
  });
}

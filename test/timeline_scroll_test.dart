// Getting about a timeline wider than the dock: the wheel, the middle
// button, the scroll bar, and the playhead staying on screen.

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_game_engine_editor/just_game_engine_editor.dart';
import 'package:just_game_engine_editor/src/ui/timeline/dope_sheet.dart';
import 'package:just_game_engine_editor/src/ui/timeline/timeline_dock.dart';
import 'package:just_game_engine_editor/src/ui/timeline/timeline_scrollbar.dart';
import 'package:just_game_engine_editor/src/ui/timeline/timeline_session.dart';

import 'support/test_scope.dart';

void main() {
  setUpAll(registerCoreCodecs);

  late EditorScope scope;
  late TimelineSession s;

  /// A minute of timeline: far more than fits.
  Future<void> pumpDock(WidgetTester tester, {double duration = 60}) async {
    scope = testScope();
    s = TimelineSession.of(scope);
    addTearDown(s.dispose);
    final entity = scope.world.createEntityWithComponents([
      TransformComponent(),
      TimelinePlayerComponent(
        inline: TimelineAsset(
          duration: duration,
          fps: 10,
          tracks: [
            PropertyTrack(
              component: 'TransformComponent',
              field: 'position',
              channel: 'x',
              curve: KeyCurve([
                const TimelineKey(time: 0, value: 0.0),
                TimelineKey(time: duration, value: 100.0),
              ]),
            ),
            for (var i = 0; i < 12; i++) EventTrack(name: 'Events $i'),
          ],
        ),
      ),
    ], name: 'Long');
    scope.sceneState.selectedEntity.value = entity;
    tester.view.physicalSize = const Size(1000, 300);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: TimelineDock(scope: scope)),
      ),
    );
    await tester.pump();
    await tester.pump();
    // The sheet publishes its width after a frame; zoom in so there is
    // something to scroll.
    await tester.pump();
    s.pixelsPerSecond.value = 120;
    await tester.pump();
  }

  Future<void> wheel(WidgetTester tester, Offset at, Offset delta) async {
    final pointer = TestPointer(4, PointerDeviceKind.mouse);
    pointer.hover(at);
    await tester.sendEventToBinding(pointer.scroll(delta));
    await tester.pump();
  }

  testWidgets('the wheel scrolls sideways, and the sheet keeps its bounds', (
    tester,
  ) async {
    await pumpDock(tester);
    final sheet = tester.getRect(find.byType(DopeSheet));
    expect(s.viewWidth.value, greaterThan(500));
    expect(s.visibleSpan, closeTo((s.viewWidth.value - 12) / 120, 0.01));

    // A wheel tilt, or a trackpad swiped sideways.
    await wheel(tester, sheet.center, const Offset(240, 0));
    expect(s.scrollTime.value, closeTo(2, 1e-6));

    // Shift and the ordinary wheel does the same.
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await wheel(tester, sheet.center, const Offset(0, 120));
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    expect(s.scrollTime.value, closeTo(3, 1e-6));

    // It stops at the start rather than going negative.
    await wheel(tester, sheet.center, const Offset(-9000, 0));
    expect(s.scrollTime.value, 0);

    // And it stops a little past the end, not in empty space.
    await wheel(tester, sheet.center, const Offset(90000, 0));
    expect(s.scrollTime.value, s.maxScroll);
    expect(s.maxScroll, closeTo(60 - s.visibleSpan * 0.5, 1e-6));
    expect(s.scrollTime.value + s.visibleSpan, greaterThan(60));
  });

  testWidgets('a plain wheel still scrolls the rows, and Ctrl still zooms', (
    tester,
  ) async {
    await pumpDock(tester);
    final sheet = tester.getRect(find.byType(DopeSheet));
    final rows = tester.widget<ListView>(find.byType(ListView)).controller!;

    await wheel(tester, sheet.center, const Offset(0, 60));
    expect(rows.offset, 60);
    expect(s.scrollTime.value, 0, reason: 'sideways is a different gesture');

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await wheel(
      tester,
      sheet.centerLeft + const Offset(12, 0),
      const Offset(0, -60),
    );
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    expect(s.pixelsPerSecond.value, closeTo(120 * 1.15, 1e-6));
  });

  testWidgets('the middle button still drags the sheet about', (tester) async {
    await pumpDock(tester);
    final sheet = tester.getRect(find.byType(DopeSheet));
    final rows = tester.widget<ListView>(find.byType(ListView)).controller!;
    s.scrollTo(10);

    final drag = await tester.startGesture(
      sheet.center,
      buttons: kMiddleMouseButton,
    );
    await drag.moveBy(const Offset(-120, -40));
    await tester.pump();
    expect(s.scrollTime.value, closeTo(11, 1e-6), reason: 'the sheet follows');
    expect(rows.offset, 40);
    await drag.moveBy(const Offset(360, 0));
    await tester.pump();
    expect(s.scrollTime.value, closeTo(8, 1e-6));
    await drag.up();

    // It cannot be dragged off the front either.
    final back = await tester.startGesture(
      sheet.center,
      buttons: kMiddleMouseButton,
    );
    await back.moveBy(const Offset(4000, 0));
    await tester.pump();
    expect(s.scrollTime.value, 0);
    await back.up();
  });

  testWidgets('the bar shows how much is on screen and drags the sheet', (
    tester,
  ) async {
    await pumpDock(tester);
    final bar = tester.getRect(find.byType(TimelineScrollBar));
    expect(bar.width, s.viewWidth.value, reason: 'it spans the sheet');
    expect(bar.height, TimelineScrollBar.height);
    // The tree gives up the same height, so both panes end on the same row.
    expect(
      tester.getRect(find.byType(ListView)).bottom,
      tester.getRect(find.byType(DopeSheet)).bottom,
    );

    // The thumb stands for the share of the scrollable stretch on screen.
    final fraction = s.visibleSpan / (s.maxScroll + s.visibleSpan);
    final thumb = bar.width * fraction;
    final gesture = await tester.startGesture(
      Offset(bar.left + thumb / 2, bar.center.dy),
    );
    await gesture.moveBy(Offset(bar.width / 2, 0));
    await tester.pump();
    expect(
      s.scrollTime.value,
      closeTo(s.maxScroll * (bar.width / 2) / (bar.width - thumb), 0.5),
    );
    await gesture.up();

    // A click beside the thumb jumps it there.
    await tester.tapAt(Offset(bar.left + 20, bar.center.dy));
    await tester.pump();
    expect(s.scrollTime.value, lessThan(2));

    // Wheeling over the bar scrolls too.
    await wheel(tester, bar.center, const Offset(0, 240));
    expect(s.scrollTime.value, closeTo(2, 1e-6));
  });

  testWidgets('a timeline that fits can still be nudged, but only a little', (
    tester,
  ) async {
    // What zoom-to-fit leaves: nothing hidden, so nothing *needs* scrolling
    // — but a gesture that refuses to move reads as broken, so there is
    // half a screen of room and no more.
    await pumpDock(tester, duration: 2);
    s.zoomToFit(s.viewWidth.value);
    await tester.pump();
    expect(s.maxScroll, closeTo(s.visibleSpan * 0.5, 1e-6));

    final sheet = tester.getRect(find.byType(DopeSheet));
    final drag = await tester.startGesture(
      sheet.center,
      buttons: kMiddleMouseButton,
    );
    await drag.moveBy(const Offset(-60, 0));
    await tester.pump();
    expect(
      s.scrollTime.value,
      closeTo(60 / s.pixelsPerSecond.value, 1e-6),
      reason: 'the sheet came with the pointer',
    );
    await drag.moveBy(const Offset(-4000, 0));
    await tester.pump();
    expect(s.scrollTime.value, s.maxScroll, reason: 'and stops there');
    await drag.up();

    await wheel(tester, sheet.center, const Offset(-9000, 0));
    expect(s.scrollTime.value, 0);
  });

  testWidgets('an edit leaves the zoom and the scroll where they are', (
    tester,
  ) async {
    // The dock fits a timeline to the dock the first time it sees it. That
    // used to hang on the asset itself, which changes on *every* edit — so
    // moving a key threw away the zoom and scrolled back to the start.
    await pumpDock(tester);
    s
      ..pixelsPerSecond.value = 200
      ..scrollTo(12);
    await tester.pump();

    s.setKey(0, 20, value: 5.0);
    await tester.pump();
    await tester.pump();
    expect(s.pixelsPerSecond.value, 200);
    expect(s.scrollTime.value, 12);

    s.undo();
    await tester.pump();
    await tester.pump();
    expect(s.pixelsPerSecond.value, 200, reason: 'nor does undoing one');

    // Opening another timeline is a different matter: that is a first look.
    final other = scope.world.createEntityWithComponents([
      TransformComponent(),
      TimelinePlayerComponent(inline: TimelineAsset(duration: 3, fps: 10)),
    ], name: 'Other');
    scope.sceneState.selectedEntity.value = other;
    await tester.pump();
    await tester.pump();
    await tester.pump();
    expect(s.duration, 3);
    expect(s.pixelsPerSecond.value, isNot(200), reason: 'fitted to the dock');
    expect(s.scrollTime.value, 0);
  });

  testWidgets('the playhead stays in view while it plays and while '
      'stepping', (tester) async {
    await pumpDock(tester);
    final span = s.visibleSpan;
    s.play();
    for (var i = 0; i < 20; i++) {
      s.tick(0.5);
    }
    expect(s.playhead.value, closeTo(10, 1e-6));
    expect(s.scrollTime.value, greaterThan(0), reason: 'it followed');
    expect(s.playhead.value, lessThan(s.scrollTime.value + span));
    expect(s.playhead.value, greaterThan(s.scrollTime.value));

    s
      ..pause()
      ..scrollTo(40);
    s.stepFrames(1);
    expect(s.scrollTime.value, lessThan(11), reason: 'back to the playhead');
  });
}

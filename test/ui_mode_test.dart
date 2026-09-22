// The viewport's UI mode: a device frame with the real interface in it,
// picked and dragged with the editor's own handles.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_game_engine_editor/just_game_engine_editor.dart';

import 'support/test_scope.dart';

void main() {
  setUpAll(registerCoreCodecs);

  late EditorScope scope;
  late UiModeSession session;
  late EditorHistory history;

  /// A canvas with two anchored children, named and laid out apart.
  ({Entity canvas, Entity first, Entity second}) buildScene() {
    final canvas = scope.world.createEntityWithComponents([
      UiCanvasComponent(
        designSize: const Size(393, 852),
        scaleMode: UiScaleMode.none,
        safeArea: false,
      ),
      ChildrenComponent(),
    ], name: 'Hud');
    Entity child(String name, Offset at) {
      final entity = scope.world.createEntityWithComponents([
        TextComponent(text: name),
        UiSlotComponent(
          mode: UiSlotMode.anchored,
          anchor: UiAnchor.topLeft,
          pivot: Offset.zero,
          offset: at,
          size: const Size(100, 40),
        ),
        ParentComponent(parentId: canvas.id),
      ], name: name);
      canvas.getComponent<ChildrenComponent>()!.addChild(entity.id);
      return entity;
    }

    return (
      canvas: canvas,
      first: child('Coins', const Offset(20, 20)),
      second: child('Timer', const Offset(200, 300)),
    );
  }

  Future<void> pumpMode(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1000, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: UiModeOverlay(
            session: session,
            sceneState: scope.sceneState,
            history: history,
          ),
        ),
      ),
    );
    await tester.pump();
  }

  setUp(() {
    scope = testScope();
    session = UiModeSession(world: () => scope.world);
    history = EditorHistory();
    addTearDown(session.dispose);
  });

  group('the frame', () {
    testWidgets('shows the interface, drawn by the layer the game uses', (
      tester,
    ) async {
      buildScene();
      await pumpMode(tester);

      expect(find.byType(UiLayer), findsOneWidget);
      expect(find.text('Coins', findRichText: true), findsOneWidget);
      expect(find.text('Timer', findRichText: true), findsOneWidget);
    });

    testWidgets('the screen can be changed, and turned on its side', (
      tester,
    ) async {
      buildScene();
      await pumpMode(tester);
      expect(session.frameSize, const Size(393, 852));

      session.device.value = UiDevices.tablet;
      await tester.pump();
      expect(session.frameSize, const Size(834, 1194));

      session.landscape.value = true;
      await tester.pump();
      expect(session.frameSize, const Size(1194, 834));
      expect(tester.takeException(), isNull);
    });
  });

  group('picking', () {
    testWidgets('a click selects what is under it', (tester) async {
      final scene = buildScene();
      await pumpMode(tester);

      await tester.tapAt(_centreOf(tester, 'Coins'));
      await tester.pump();

      expect(scope.sceneState.selectedEntity.value?.id, scene.first.id);
    });

    testWidgets('a click on the empty part of a canvas selects nothing', (
      tester,
    ) async {
      buildScene();
      await pumpMode(tester);
      scope.sceneState.selectEntity(scope.world.findEntityByName('Coins')!);

      // The bottom of the frame, where neither child is.
      final frame = tester.getRect(find.byType(UiLayer));
      await tester.tapAt(Offset(frame.center.dx, frame.bottom - 20));
      await tester.pump();

      expect(scope.sceneState.selectedEntity.value, isNull);
    });

    testWidgets('the deepest node wins, not the canvas', (tester) async {
      final scene = buildScene();
      await pumpMode(tester);

      await tester.tapAt(_centreOf(tester, 'Timer'));
      await tester.pump();

      expect(scope.sceneState.selectedEntity.value?.id, scene.second.id);
      expect(
        scope.sceneState.selectedEntity.value?.id,
        isNot(scene.canvas.id),
      );
    });
  });

  group('dragging', () {
    testWidgets('a drag moves the element and is one undo step', (
      tester,
    ) async {
      final scene = buildScene();
      session.snap.value = false;
      await pumpMode(tester);
      final slot = scene.first.getComponent<UiSlotComponent>()!;
      expect(slot.offset, const Offset(20, 20));

      final from = _centreOf(tester, 'Coins');
      final gesture = await tester.startGesture(from);
      await tester.pump();
      await gesture.moveBy(const Offset(30, 0));
      await tester.pump();
      await gesture.moveBy(const Offset(30, 0));
      await tester.pump();
      await gesture.up();
      await tester.pump();

      expect(slot.offset.dx, closeTo(80, 1));
      expect(slot.offset.dy, closeTo(20, 1));

      // The whole drag undoes at once.
      history.undo();
      expect(slot.offset, const Offset(20, 20));
      expect(history.canUndo.value, isFalse);
    });

    testWidgets('a drag lands on a sibling edge when snapping is on', (
      tester,
    ) async {
      final scene = buildScene();
      session.snap.value = true;
      await pumpMode(tester);
      final slot = scene.first.getComponent<UiSlotComponent>()!;

      // Drag Coins to just left of where Timer's left edge is (200), near
      // enough that it should land exactly on it.
      final gesture = await tester.startGesture(_centreOf(tester, 'Coins'));
      await tester.pump();
      await gesture.moveBy(const Offset(177, 0));
      await tester.pump();
      await gesture.up();
      await tester.pump();

      expect(slot.offset.dx, closeTo(200, 0.5));
    });

    testWidgets('nothing moves when the drag began on nothing', (
      tester,
    ) async {
      final scene = buildScene();
      await pumpMode(tester);
      final slot = scene.first.getComponent<UiSlotComponent>()!;

      final frame = tester.getRect(find.byType(UiLayer));
      final gesture = await tester.startGesture(
        Offset(frame.center.dx, frame.bottom - 20),
      );
      await gesture.moveBy(const Offset(40, 40));
      await gesture.up();
      await tester.pump();

      expect(slot.offset, const Offset(20, 20));
      expect(history.canUndo.value, isFalse);
    });
  });

  group('snapping on its own', () {
    test('an edge within reach pulls the drag onto it', () {
      const moving = Rect.fromLTWH(0, 0, 100, 40);
      const target = Rect.fromLTWH(104, 0, 100, 40);

      final snapped = snapUiDrag(
        moving: moving,
        offset: const Offset(2, 0),
        targets: [target],
      );

      // The offset is a delta, and its right edge lands on the target's
      // left edge: 100 + 4 = 104.
      expect(snapped.offset.dx, closeTo(4, 0.001));
      expect(moving.shift(snapped.offset).right, closeTo(target.left, 0.001));
      expect(snapped.lines, [target]);
    });

    test('an edge out of reach is left alone', () {
      final snapped = snapUiDrag(
        moving: const Rect.fromLTWH(0, 0, 100, 40),
        offset: const Offset(2, 0),
        targets: [const Rect.fromLTWH(400, 300, 100, 40)],
      );

      expect(snapped.offset, const Offset(2, 0));
      expect(snapped.lines, isEmpty);
    });

    test('centres line up too', () {
      final target = const Rect.fromLTWH(0, 200, 200, 40);
      final snapped = snapUiDrag(
        moving: const Rect.fromLTWH(0, 0, 100, 40),
        offset: const Offset(48, 0),
        targets: [target],
      );

      // Its centre (50 + 48) is pulled to the target's centre (100).
      expect(snapped.offset.dx, closeTo(50, 0.001));
    });
  });

  group('the device list', () {
    test('the nearest screen to a design size', () {
      expect(UiDevices.nearest(390, 850), UiDevices.phone);
      expect(UiDevices.nearest(1600, 900), UiDevices.desktop);
    });

    test('every screen says what it is', () {
      for (final device in UiDevices.all) {
        expect(device.toString(), contains(device.name));
        expect(device.width, greaterThan(0));
        expect(device.height, greaterThan(0));
      }
    });
  });
}

/// The middle of a piece of text on screen.
Offset _centreOf(WidgetTester tester, String text) =>
    tester.getCenter(find.text(text, findRichText: true));

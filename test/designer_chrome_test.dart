// Screen-space chrome — rulers, guides, the minimap — and the panel edits
// that share SelectionOps.

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_game_engine_editor/just_game_engine_editor.dart';

import 'support/test_scope.dart';

void main() {
  late World world;
  late LevelDesignerSession session;
  const canvas = Size(1000, 700);

  setUp(() {
    world = World()..initialize();
    session = LevelDesignerSession(
      scope: testScope(world: world),
      uniqueName: (p) => p,
      onDuplicate: () {},
      onDelete: () {},
      onArray: (_, _) {},
      readModifiers: () => const ModifierKeys(),
    );
    session.camera.viewportSize = canvas;
    // As the overlay would: a 44px palette on the left, panels on the right.
    session.controller.viewportInsets = const EdgeInsets.fromLTRB(
      44,
      0,
      300,
      30,
    );
  });
  tearDown(() {
    session.dispose();
    world.dispose();
  });

  group('ruler guides', () {
    test('dragging out of the left ruler makes a vertical guide, undoably', () {
      final area = session.controller.visibleViewport(canvas);
      final onLeftRuler = Offset(area.left + 5, 200);
      expect(session.onChromePointerDown(onLeftRuler, canvas), isTrue);
      session
        ..onChromePointerMove(const Offset(400, 200), canvas, 32)
        ..onChromePointerUp(const Offset(400, 200), canvas);

      final guide = session.controller.guides.value.single;
      expect(guide.isVertical, isTrue);
      expect(guide.position % 32, 0, reason: 'snapped to the grid');

      session.history.undo();
      expect(session.controller.guides.value, isEmpty);
    });

    test('a guide dropped back on its ruler is removed', () {
      session.controller.guides.value = const [
        DesignerGuide(isVertical: false, position: 0),
      ];
      final area = session.controller.visibleViewport(canvas);
      // The horizontal guide at y=0 crosses the left ruler at this height.
      final y = session.camera.worldToScreen(Offset.zero).dy;
      expect(
        session.onChromePointerDown(Offset(area.left + 5, y), canvas),
        isTrue,
      );
      session.onChromePointerUp(Offset(area.left + 5, area.top + 5), canvas);
      expect(session.controller.guides.value, isEmpty);
    });

    test('a press inside the viewport is not taken by the rulers', () {
      expect(
        session.onChromePointerDown(const Offset(400, 300), canvas),
        isFalse,
      );
    });

    test('guides attract a dragged entity', () {
      session.controller.guides.value = const [
        DesignerGuide(isVertical: true, position: 203),
      ];
      final a = world.createEntityWithComponents([
        TransformComponent(position: Vector3(100, 16, 0)),
        RectangleComponent(width: 64, height: 32),
      ], name: 'A');
      session.sceneState.selectEntity(a);
      session
        ..onPointerDown(const Offset(100, 16), 32)
        // Right edge would land at 200: three units short of the guide.
        ..onPointerMove(const Offset(168, 16), 32)
        ..onPointerUp(const Offset(168, 16), 32);
      expect(DesignerGeometry.worldBounds(a)!.right, closeTo(203, 1e-9));
    });
  });

  test('clicking the minimap centres the visible viewport there', () {
    world.createEntityWithComponents([
      TransformComponent(position: Vector3(3000, 0, 0)),
      RectangleComponent(width: 100, height: 100),
    ]);
    final area = session.controller.visibleViewport(canvas);
    final panel = MinimapLayout.panelFor(
      area,
      bottomReserve: session.controller.minimapBottomReserve,
    );
    Rect view() => Rect.fromPoints(
      session.camera.screenToWorld(area.topLeft),
      session.camera.screenToWorld(area.bottomRight),
    );
    // What the map shows under the click, before the view moves — the map
    // includes the view in its extent, so it re-lays itself out afterwards.
    final target = MinimapLayout.of(
      world,
      session.controller,
      area,
      view(),
    )!.toWorld(panel.center);

    expect(session.onChromePointerDown(panel.center, canvas), isTrue);
    session.onChromePointerUp(panel.center, canvas);

    final visibleCentre = session.camera.screenToWorld(area.center);
    expect((visibleCentre - target).distance, lessThan(1e-6));
  });

  test('typing a width resizes the selection as one step', () {
    final a = world.createEntityWithComponents([
      TransformComponent(position: Vector3(32, 16, 0)),
      RectangleComponent(width: 64, height: 32),
    ], name: 'A');
    for (final w in [70.0, 90.0, 128.0]) {
      // A scrub commits on every step; they fold into one undo.
      session.ops.resizeTo([a], Rect.fromLTWH(0, 0, w, 32), mergeKey: 'w');
    }
    expect(a.components.whereType<RectangleComponent>().single.width, 128);
    session.history.undo();
    expect(a.components.whereType<RectangleComponent>().single.width, 64);
    expect(session.history.undoDepth, 0);
  });

  test('hidden entities are what the render filter skips', () {
    final a = world.createEntityWithComponents([
      TransformComponent(),
      RectangleComponent(width: 10, height: 10),
      LayerComponent(layerId: 'background'),
    ]);
    final c = session.controller;
    expect(c.isShownInViewport(a), isTrue);
    c.setLayerHidden('background', hidden: true);
    expect(c.isShownInViewport(a), isFalse, reason: 'hidden layer hides it');
    c.setLayerHidden('background', hidden: false);
    c.setEntitiesHidden([a.id], hidden: true);
    expect(c.isShownInViewport(a), isFalse);
  });
}

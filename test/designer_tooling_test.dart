import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_game_engine_editor/just_game_engine_editor.dart';

void main() {
  // Sizes come from the definitions' extents, which a game registers at
  // boot and an EditorScope registers for itself; these helpers run bare.
  group('geometry', () {
    test('a quarter-turned platform is bounded by the space it occupies', () {
      final world = World()..initialize();
      addTearDown(world.dispose);
      final e = world.createEntityWithComponents([
        TransformComponent(position: Vector3(0, 0, 0), angle: math.pi / 2),
        RectangleComponent(width: 200, height: 20),
      ]);
      final b = DesignerGeometry.worldBounds(e)!;
      expect(b.width, closeTo(20, 1e-6));
      expect(b.height, closeTo(200, 1e-6));
    });

    test('quarter turns are exact and come back to where they started', () {
      const pivot = Offset(100, 100);
      var p = const Offset(130, 90);
      for (var i = 0; i < 4; i++) {
        p = DesignerGeometry.rotateQuarter(p, pivot, 1);
      }
      expect(p, const Offset(130, 90));
      // Clockwise on screen: east goes to south.
      expect(
        DesignerGeometry.rotateQuarter(const Offset(110, 100), pivot, 1),
        const Offset(100, 110),
      );
    });

    test('dragging a corner resizes from the opposite corner', () {
      const start = Rect.fromLTWH(0, 0, 100, 50);
      final r = DesignerGeometry.resizeRect(
        start,
        ResizeHandle.bottomRight,
        const Offset(150, 80),
      );
      expect(r, const Rect.fromLTWH(0, 0, 150, 80));
    });

    test('an edge handle changes one axis only', () {
      const start = Rect.fromLTWH(0, 0, 100, 50);
      final r = DesignerGeometry.resizeRect(
        start,
        ResizeHandle.left,
        const Offset(-20, 999),
      );
      expect(r, const Rect.fromLTRB(-20, 0, 100, 50));
    });

    test('a drag past the opposite edge stops at the minimum', () {
      const start = Rect.fromLTWH(0, 0, 100, 50);
      final r = DesignerGeometry.resizeRect(
        start,
        ResizeHandle.right,
        const Offset(-500, 0),
        minExtent: 8,
      );
      expect(r.left, 0);
      expect(r.width, 8);
    });

    test('Shift keeps the aspect ratio on a corner', () {
      const start = Rect.fromLTWH(0, 0, 100, 50);
      final r = DesignerGeometry.resizeRect(
        start,
        ResizeHandle.bottomRight,
        const Offset(200, 60),
        keepAspect: true,
      );
      expect(r.width / r.height, closeTo(2, 1e-9));
      expect(r.width, 200);
    });

    test('Alt resizes about the centre', () {
      const start = Rect.fromLTWH(0, 0, 100, 50);
      final r = DesignerGeometry.resizeRect(
        start,
        ResizeHandle.right,
        const Offset(110, 0),
        fromCenter: true,
      );
      expect(r.center, start.center);
      expect(r.width, 120);
    });
  });

  group('resizer', () {
    test('keeps the visual and the collider the same size', () {
      final world = World()..initialize();
      addTearDown(world.dispose);
      final e = world.createEntityWithComponents([
        TransformComponent(),
        RectangleComponent(width: 100, height: 20),
        PhysicsBodyComponent(
          shape: RectangleShape(100, 20),
          bodyType: BodyType.static,
        ),
      ]);
      ComponentResizer.scale(e, 2, 3);

      final rect = e.components.whereType<RectangleComponent>().single;
      final shape =
          e.getComponent<PhysicsBodyComponent>()!.shape as RectangleShape;
      expect((rect.width, rect.height), (200.0, 60.0));
      expect((shape.width, shape.height), (200.0, 60.0));
    });

    test('a quarter-turned entity is resized along its own axes', () {
      final world = World()..initialize();
      addTearDown(world.dispose);
      final e = world.createEntityWithComponents([
        TransformComponent(angle: math.pi / 2),
        RectangleComponent(width: 100, height: 20),
      ]);
      // Stretching in world X is stretching its local height.
      ComponentResizer.scale(e, 2, 1);
      final rect = e.components.whereType<RectangleComponent>().single;
      expect((rect.width, rect.height), (100.0, 40.0));
    });

    test('a polygon is measured by its vertices and resized with them', () {
      final world = World()..initialize();
      addTearDown(world.dispose);
      final e = world.createEntityWithComponents([
        TransformComponent(),
        PolygonComponent(
          vertices: const [Offset(-10, -5), Offset(10, -5), Offset(0, 5)],
        ),
      ]);
      expect(DesignerGeometry.componentSize(e), const Size(20, 10));
      ComponentResizer.scale(e, 2, 3);
      expect(DesignerGeometry.componentSize(e), const Size(40, 30));
    });

    test('never shrinks to nothing', () {
      final world = World()..initialize();
      addTearDown(world.dispose);
      final e = world.createEntityWithComponents([
        TransformComponent(),
        RectangleComponent(width: 10, height: 10),
      ]);
      ComponentResizer.scale(e, 0, 0);
      final rect = e.components.whereType<RectangleComponent>().single;
      expect(rect.width, ComponentResizer.minimumExtent);
    });
  });

  group('smart snap', () {
    const neighbour = Rect.fromLTWH(0, 0, 100, 20);

    test('snaps an edge flush with a neighbour within the threshold', () {
      // Left edge 4 units right of the neighbour's right edge.
      const moving = Rect.fromLTWH(104, 50, 60, 20);
      final r = SmartSnap.snap(moving, [neighbour], threshold: 6);
      expect(r.dx, -4);
    });

    test('leaves an axis alone when nothing is close', () {
      const moving = Rect.fromLTWH(300, 300, 60, 20);
      final r = SmartSnap.snap(moving, [neighbour], threshold: 6);
      expect(r.dx, isNull);
      expect(r.dy, isNull);
    });

    test('centres snap to centres', () {
      // Moving centre x = 53; neighbour centre x = 50.
      const moving = Rect.fromLTWH(23, 100, 60, 20);
      final r = SmartSnap.snap(moving, [neighbour], threshold: 6);
      expect(r.dx, -3);
    });

    test('reports the lines that now align', () {
      const moving = Rect.fromLTWH(100, 50, 60, 20); // left == neighbour.right
      final guides = SmartSnap.guides(moving, [neighbour]);
      expect(
        guides.where((g) => g.vertical && g.position == 100),
        hasLength(1),
      );
    });

    test('measures the gap to the nearest neighbour on each side', () {
      const moving = Rect.fromLTWH(130, 0, 50, 20);
      final gaps = SmartSnap.spacing(moving, [
        neighbour,
        const Rect.fromLTWH(-500, 0, 10, 20), // further away on the same side
      ]);
      expect(gaps.single.distance, 30);
    });
  });
}

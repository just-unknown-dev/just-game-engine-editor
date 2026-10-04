// The advanced tooling, driven the way a user drives it: keys and pointer
// gestures through a real session, checked for the edit and for its undo.

import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_game_engine_editor/just_game_engine_editor.dart';

import 'support/test_scope.dart';

class _Keys {
  bool shift = false, alt = false, control = false;
  ModifierKeys read() => ModifierKeys(shift: shift, alt: alt, control: control);
}

({LevelDesignerSession session, World world, _Keys keys}) _open() {
  final world = World()..initialize();
  final keys = _Keys();
  var n = 0;
  final session = LevelDesignerSession(
    scope: testScope(world: world),
    uniqueName: (p) => '${p}_${n++}',
    onDuplicate: () {},
    onDelete: () {},
    onArray: (_, _) {},
    readModifiers: keys.read,
  );
  return (session: session, world: world, keys: keys);
}

Entity _block(
  World world,
  String name,
  double x,
  double y, {
  double w = 64,
  double h = 32,
}) => world.createEntityWithComponents([
  TransformComponent(position: Vector3(x, y, 0)),
  RectangleComponent(width: w, height: h),
  PhysicsBodyComponent(shape: RectangleShape(w, h), bodyType: BodyType.static),
  LayerComponent(),
], name: name);

Offset _pos(Entity e) {
  final p = e.getComponent<TransformComponent>()!.position;
  return Offset(p.x, p.y);
}

void main() {
  late LevelDesignerSession session;
  late World world;
  late _Keys keys;
  setUp(() => (:session, :world, :keys) = _open());
  tearDown(() {
    session.dispose();
    world.dispose();
  });

  bool key(LogicalKeyboardKey k) => session.handleKey(k, gridSize: 32);

  void drag(Offset from, Offset to) {
    session
      ..onPointerDown(from, 32)
      ..onPointerMove(to, 32)
      ..onPointerUp(to, 32);
  }

  group('keyboard', () {
    test('arrows nudge a grid step, Shift one unit; a run undoes at once', () {
      final a = _block(world, 'A', 0, 0);
      session.sceneState.selectEntity(a);

      key(LogicalKeyboardKey.arrowRight);
      key(LogicalKeyboardKey.arrowRight);
      keys.shift = true;
      key(LogicalKeyboardKey.arrowDown);
      expect(_pos(a), const Offset(64, 1));

      session.history.undo();
      expect(_pos(a), Offset.zero);
    });

    test('a nudge after a move is its own undo step', () {
      final a = _block(world, 'A', 0, 0);
      session.sceneState.selectEntity(a);
      session.ops.moveTo([a], const Offset(100, 100));
      key(LogicalKeyboardKey.arrowRight);
      session.history.undo();
      expect(DesignerGeometry.worldBounds(a)!.left, closeTo(100, 1e-9));
    });

    test('Z turns a quarter turn; four turns come back exactly', () {
      final a = _block(world, 'A', 0, 0);
      final b = _block(world, 'B', 200, 0);
      session.selectAll();
      final before = [_pos(a), _pos(b)];
      for (var i = 0; i < 4; i++) {
        key(LogicalKeyboardKey.keyZ);
      }
      expect([_pos(a), _pos(b)], before);
      expect(a.getComponent<TransformComponent>()!.angle, closeTo(0, 1e-9));
    });

    test('X mirrors positions and flips a sprite with its entity', () {
      final a = world.createEntityWithComponents([
        TransformComponent(position: Vector3(0, 0, 0)),
        SpriteComponent(spritePath: 'hero.png'),
      ], name: 'Hero');
      final b = _block(world, 'B', 100, 0);
      session.selectAll();
      key(LogicalKeyboardKey.keyX);
      // Mirrored across the centre of the selection's bounds, 0..132.
      expect(_pos(a).dx, closeTo(132, 1e-9));
      expect(_pos(b).dx, closeTo(32, 1e-9));
      expect(a.getComponent<SpriteComponent>()!.flipX, isTrue);

      session.history.undo();
      expect(_pos(a).dx, closeTo(0, 1e-9));
      expect(a.getComponent<SpriteComponent>()!.flipX, isFalse);
    });

    test('H hides, Shift+H isolates, Alt+H shows everything', () {
      final a = _block(world, 'A', 0, 0);
      final b = _block(world, 'B', 200, 0);
      final c = session.controller;

      session.sceneState.selectEntity(a);
      key(LogicalKeyboardKey.keyH);
      expect(c.isShownInViewport(a), isFalse);
      expect(c.isPickable(a), isFalse, reason: 'hidden cannot be picked');

      keys.alt = true;
      key(LogicalKeyboardKey.keyH);
      keys.alt = false;
      expect(c.isShownInViewport(a), isTrue);

      session.sceneState.selectEntity(a);
      keys.shift = true;
      key(LogicalKeyboardKey.keyH);
      expect(c.isShownInViewport(a), isTrue);
      expect(c.isShownInViewport(b), isFalse);
    });

    test('L locks against picking without hiding', () {
      final a = _block(world, 'A', 0, 0);
      session.sceneState.selectEntity(a);
      key(LogicalKeyboardKey.keyL);
      expect(session.controller.isPickable(a), isFalse);
      expect(session.controller.isShownInViewport(a), isTrue);
    });

    test('F frames the selection; bookmarks save and restore the view', () {
      final a = _block(world, 'A', 1000, 500);
      session.camera.viewportSize = const Size(800, 600);
      session.sceneState.selectEntity(a);
      key(LogicalKeyboardKey.keyF);
      expect(session.camera.position, const Offset(1000, 500));

      keys.control = true;
      key(LogicalKeyboardKey.digit3);
      keys.control = false;
      session.camera.setPosition(Offset.zero);
      key(LogicalKeyboardKey.digit3);
      expect(session.camera.position, const Offset(1000, 500));
    });

    test('tool shortcuts switch tools', () {
      key(LogicalKeyboardKey.keyB);
      expect(session.controller.toolId.value, BuiltInTools.draw);
      key(LogicalKeyboardKey.keyM);
      expect(session.controller.toolId.value, BuiltInTools.measure);
      // Q is the editor's All, which picks the select tool up: a command,
      // not a tool's key (see transform_toolbar_test).
      expect(session.tools.byShortcut('Q'), isNull);
    });

    test('Shift+R replaces with the active prefab, same place, size and '
        'layer', () {
      final a = _block(world, 'A', 100, 50, w: 96, h: 32);
      a.getComponent<LayerComponent>()!.layer = 7;
      session.sceneState.selectEntity(a);
      session.controller.activePrefabId.value = BuiltInPrefabs.solidId;
      keys.shift = true;
      key(LogicalKeyboardKey.keyR);
      keys.shift = false;

      final replaced = world.query([TransformComponent]).single;
      expect(replaced.id, isNot(a.id));
      expect(_pos(replaced), const Offset(100, 50));
      expect(DesignerGeometry.worldBounds(replaced)!.size, const Size(96, 32));
      expect(replaced.getComponent<LayerComponent>()!.layer, 7);

      session.history.undo();
      expect(world.query([TransformComponent]).single.name, 'A');
    });
  });

  group('select tool gestures', () {
    test('a corner handle resizes the visual and the collider together', () {
      final a = _block(world, 'A', 32, 16); // bounds 0,0 -> 64,32
      session.sceneState.selectEntity(a);
      session.scope.view.transformMode.value = TransformMode.scale;
      drag(const Offset(64, 32), const Offset(128, 64));

      final rect = a.components.whereType<RectangleComponent>().single;
      final shape =
          a.getComponent<PhysicsBodyComponent>()!.shape as RectangleShape;
      expect((rect.width, rect.height), (128.0, 64.0));
      expect((shape.width, shape.height), (128.0, 64.0));
      expect(_pos(a), const Offset(64, 32), reason: 'top-left stays put');

      session.history.undo();
      expect(a.components.whereType<RectangleComponent>().single.width, 64);
      expect(_pos(a), const Offset(32, 16));
    });

    test('Alt+drag moves a copy and leaves the original', () {
      final a = _block(world, 'A', 32, 16);
      session.sceneState.selectEntity(a);
      keys.alt = true;
      drag(const Offset(40, 20), const Offset(240, 20));
      keys.alt = false;

      expect(_pos(a), const Offset(32, 16));
      final copy = world
          .query([TransformComponent])
          .firstWhere((e) => e.id != a.id);
      expect(_pos(copy).dx, closeTo(32 + 192, 1e-9)); // snapped to the grid
      expect(copy.name, isNot(a.name));

      session.history.undo();
      expect(world.query([TransformComponent]), hasLength(1));
      session.history.redo();
      expect(world.query([TransformComponent]), hasLength(2));
    });

    test('Alt-click without dragging makes no copy', () {
      final a = _block(world, 'A', 32, 16);
      session.sceneState.selectEntity(a);
      keys.alt = true;
      drag(const Offset(40, 20), const Offset(40, 20));
      expect(world.query([TransformComponent]), hasLength(1));
      expect(session.history.undoDepth, 0);
    });

    test('an edge snaps flush to a neighbour that is off the grid', () {
      _block(world, 'Wall', 105, 16, w: 10, h: 32); // right edge at 110
      final a = _block(world, 'A', 300, 16);
      session.sceneState.selectEntity(a);
      // Brings A's left edge to 113, three units from the wall.
      drag(const Offset(300, 16), const Offset(145, 16));
      expect(DesignerGeometry.worldBounds(a)!.left, closeTo(110, 1e-9));
    });

    test('Ctrl while dragging places freely', () {
      final a = _block(world, 'A', 32, 16);
      session.sceneState.selectEntity(a);
      session.onPointerDown(const Offset(32, 16), 32);
      keys.control = true;
      session
        ..onPointerMove(const Offset(39, 21), 32)
        ..onPointerUp(const Offset(39, 21), 32);
      expect(_pos(a), const Offset(39, 21));
    });

    test('the rotate ring turns in 15 degree steps', () {
      final a = _block(world, 'A', 0, 0);
      session.sceneState.selectEntity(a);
      session.scope.view.transformMode.value = TransformMode.rotate;
      final bounds = DesignerGeometry.worldBounds(a)!;
      final r = session.scope.handleLayout.ringRadius(bounds, 1);
      // From straight up to just past straight right: a quarter turn.
      drag(bounds.center + Offset(0, -r), bounds.center + Offset(r, 3));
      expect(
        a.getComponent<TransformComponent>()!.angle,
        closeTo(math.pi / 2, 1e-9),
      );
    });
  });

  group('paint', () {
    test('bucket fill fills an enclosed room and nothing more', () {
      // Walls around a 2x1-cell room on a 32-unit grid.
      _block(world, 'Top', 64, 16, w: 128, h: 32);
      _block(world, 'Bottom', 64, 80, w: 128, h: 32);
      _block(world, 'Left', 16, 48, w: 32, h: 32);
      _block(world, 'Right', 112, 48, w: 32, h: 32);
      session
        ..setTool(BuiltInTools.paint)
        ..controller.paintMode.value = PaintMode.fill
        ..controller.activePrefabId.value = BuiltInPrefabs.solidId
        ..onPointerDown(const Offset(50, 48), 32)
        ..onPointerUp(const Offset(50, 48), 32);

      // An entity under the Level Map, on its layer at this depth.
      final filled = _members(world);
      expect(filled, hasLength(1), reason: 'the two cells merge into one');
      expect(
        DesignerGeometry.worldBounds(filled.single),
        const Rect.fromLTWH(32, 32, 64, 32),
      );
      expect(filled.single.hasComponent<PhysicsBodyComponent>(), isTrue);
    });

    test('bucket fill refuses an open region', () {
      _block(world, 'Floor', 64, 80, w: 128, h: 32);
      session
        ..setTool(BuiltInTools.paint)
        ..controller.paintMode.value = PaintMode.fill
        ..controller.activePrefabId.value = BuiltInPrefabs.solidId
        ..onPointerDown(const Offset(50, 40), 32)
        ..onPointerUp(const Offset(50, 40), 32);
      expect(world.query([TransformComponent]), hasLength(1));
    });

    test('a 3x3 brush paints nine cells per dab', () {
      session
        ..setTool(BuiltInTools.paint)
        ..controller.brushSize.value = 3
        ..controller.activePrefabId.value = BuiltInPrefabs.solidId
        ..onPointerDown(const Offset(48, 48), 32)
        ..onPointerUp(const Offset(48, 48), 32);
      final painted = _members(world).single;
      expect(DesignerGeometry.worldBounds(painted)!.size, const Size(96, 96));
    });
  });

  test('the eyedropper samples an entity as the thing to draw', () {
    final a = _block(world, 'Ledge_4', 32, 16);
    session
      ..setTool(BuiltInTools.draw)
      ..setTool(BuiltInTools.eyedropper)
      ..onPointerDown(const Offset(32, 16), 32)
      ..onPointerUp(const Offset(32, 16), 32);
    expect(session.controller.toolId.value, BuiltInTools.draw);
    expect(session.controller.activePrefab!.name, 'Sampled: Ledge');

    drag(const Offset(0, 128), const Offset(128, 160));
    final copy = world
        .query([TransformComponent])
        .firstWhere((e) => e.id != a.id);
    expect(copy.hasComponent<PhysicsBodyComponent>(), isTrue);
    expect(DesignerGeometry.worldBounds(copy)!.size, const Size(128, 32));
  });

  test('guides and bookmarks survive a save and reload of the scene', () {
    session.controller.guides.value = const [
      DesignerGuide(isVertical: true, position: 128),
    ];
    session.camera.setPosition(const Offset(10, 20));
    session.storeBookmark(2);
    final saved = session.editorData();

    final (session: other, world: w2, keys: _) = _open();
    addTearDown(() {
      other.dispose();
      w2.dispose();
    });
    other.restoreEditorData(saved);
    expect(other.controller.guides.value.single.position, 128);
    expect(other.bookmarks[2]!.position, const Offset(10, 20));
  });
}

/// Every entity on a layer of a map in [world].
List<Entity> _members(World world) => [
  for (final e in world.query([LayerComponent]))
    if (LevelMaps.memberLayer(world, e) != null) e,
];

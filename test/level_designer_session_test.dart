// End-to-end behaviour of the Level Designer: placing, selecting, moving,
// duplicating and erasing, each of which must be a single undoable step.
//
// Runs against a bare World with no Engine, so it is fast and needs no render
// surface — the session only ever touches the world, the scene state and its
// own history.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart' as jge;
import 'package:just_game_engine_editor/just_game_engine_editor.dart';

import 'support/test_scope.dart';

/// Tag every prefab this fixture places carries, so tests can find them
/// without depending on any particular game's components.
const String kBlockTag = 'test.block';

/// A stand-in for a project's own designer.
///
/// The session no longer hard-wires a palette, so these tests supply one the
/// same way a real project would — which makes them a working check that the
/// extension model is reachable from outside the editor's own code.
class _TestExtension extends EditorModule {
  @override
  String get id => 'test';

  @override
  String get name => 'Test';

  @override
  List<PrefabDefinition> get prefabs => [
    PrefabDefinition(
      id: 'test.block',
      name: 'Block',
      category: 'Test',
      icon: Icons.crop_square,
      color: const Color(0xFF546E7A),
      namePrefix: 'Block',
      build: (position, size) => [
        jge.TransformComponent(
          position: jge.Vector3(position.dx, position.dy, 0),
        ),
        jge.RectangleComponent(width: size.width, height: size.height),
        jge.PhysicsBodyComponent(
          shape: jge.RectangleShape(size.width, size.height),
          isStatic: true,
        ),
        jge.TagComponent(kBlockTag),
        jge.LayerComponent(),
      ],
    ),
  ];
}

/// Entities this fixture's prefab created.
List<jge.Entity> _blocks(jge.World world) => world
    .query([jge.TagComponent])
    .where((e) => e.hasTag(kBlockTag))
    .toList();

/// A session wired to a throwaway world, with unique names and the selection
/// callbacks the plugin normally supplies.
({LevelDesignerSession session, jge.World world}) _session() {
  final world = jge.World()..initialize();
  var counter = 0;

  late final LevelDesignerSession session;
  session = LevelDesignerSession(
    scope: testScope(world: world, modules: [_TestExtension()])
      ..selectDesigner('test'),
    uniqueName: (prefix) => '${prefix}_${counter++}',
    onDuplicate: () {},
    onDelete: () {},
    onArray: (_, _) {},
  );
  // The editor now ships its own default palette, so the test prefab is no
  // longer whatever happens to be registered first. Every test here places
  // blocks, so select it once rather than in each test.
  session.controller.activePrefabId.value = 'test.block';
  return (session: session, world: world);
}

/// What has been placed: every entity but the level's map they go under.
int _entityCount(jge.World world) => world
    .query([jge.TransformComponent])
    .where((e) => e.isActive && !e.hasComponent<jge.LevelMapComponent>())
    .length;

void main() {
  group('draw tool', () {
    test('a drag places one entity sized to the drag', () {
      final (:session, :world) = _session();
      session.setTool(BuiltInTools.draw);

      session
        ..onPointerDown(const Offset(0, 0), 32)
        ..onPointerMove(const Offset(256, 64), 32)
        ..onPointerUp(const Offset(256, 64), 32);

      expect(_entityCount(world), 1);

      // Read the size through DesignerGeometry, not getComponent: shape
      // components override componentType to RenderableComponent, so
      // getComponent<RectangleComponent>() is always null.
      final placed = _blocks(world).single;
      final size = DesignerGeometry.componentSize(placed)!;
      expect(size.width, closeTo(256, 1));
      expect(size.height, closeTo(64, 1));

      session.dispose();
      world.dispose();
    });

    test('placing is one undoable step', () {
      final (:session, :world) = _session();
      session.setTool(BuiltInTools.draw);

      session
        ..onPointerDown(const Offset(0, 0), 32)
        ..onPointerMove(const Offset(128, 32), 32)
        ..onPointerUp(const Offset(128, 32), 32);
      expect(_entityCount(world), 1);

      session.history.undo();
      expect(_entityCount(world), 0);

      session.history.redo();
      expect(_entityCount(world), 1);

      session.dispose();
      world.dispose();
    });

    test('snapping puts the placed edges on the grid', () {
      final (:session, :world) = _session();
      session
        ..setTool(BuiltInTools.draw)
        ..controller.snapEnabled.value = true;

      session
        ..onPointerDown(const Offset(7, 9), 32)
        ..onPointerMove(const Offset(201, 71), 32)
        ..onPointerUp(const Offset(201, 71), 32);

      final placed = _blocks(world).single;
      final bounds = DesignerGeometry.worldBounds(placed)!;
      expect(bounds.left % 32, closeTo(0, 1e-6));
      expect(bounds.top % 32, closeTo(0, 1e-6));

      session.dispose();
      world.dispose();
    });

    test('a click with no drag places the prefab at its own size', () {
      final (:session, :world) = _session();
      session.setTool(BuiltInTools.draw);

      session
        ..onPointerDown(const Offset(100, 100), 32)
        ..onPointerUp(const Offset(100, 100), 32);

      final placed = _blocks(world).single;
      final size = DesignerGeometry.componentSize(placed)!;
      expect(size.width, greaterThan(0));
      expect(size.height, greaterThan(0));

      session.dispose();
      world.dispose();
    });
  });

  group('select tool', () {
    /// Places [count] platforms in a row, 200 units apart.
    List<jge.Entity> placeRow(LevelDesignerSession session, int count) {
      session.setTool(BuiltInTools.draw);
      for (var i = 0; i < count; i++) {
        final x = i * 200.0;
        session
          ..onPointerDown(Offset(x, 0), 32)
          ..onPointerMove(Offset(x + 128, 64), 32)
          ..onPointerUp(Offset(x + 128, 64), 32);
      }
      session.setTool(BuiltInTools.select);
      return _blocks(session.world);
    }

    test('a marquee selects everything it covers', () {
      final (:session, :world) = _session();
      placeRow(session, 3);

      session
        ..onPointerDown(const Offset(-50, -50), 32)
        ..onPointerMove(const Offset(600, 200), 32)
        ..onPointerUp(const Offset(600, 200), 32);

      expect(session.sceneState.multiSelectedIds.value, hasLength(3));

      session.dispose();
      world.dispose();
    });

    test('a marquee that covers nothing selects nothing', () {
      final (:session, :world) = _session();
      placeRow(session, 3);

      session
        ..onPointerDown(const Offset(2000, 2000), 32)
        ..onPointerMove(const Offset(2400, 2400), 32)
        ..onPointerUp(const Offset(2400, 2400), 32);

      expect(session.sceneState.multiSelectedIds.value, isEmpty);

      session.dispose();
      world.dispose();
    });

    test('dragging moves the whole multi-selection together', () {
      final (:session, :world) = _session();
      final placed = placeRow(session, 3);
      final before = [
        for (final e in placed)
          e.getComponent<jge.TransformComponent>()!.position.x,
      ];

      // Sweep them all up.
      session
        ..onPointerDown(const Offset(-50, -50), 32)
        ..onPointerMove(const Offset(600, 200), 32)
        ..onPointerUp(const Offset(600, 200), 32);
      expect(session.sceneState.multiSelectedIds.value, hasLength(3));

      // Grab one of them and drag; all three should follow.
      final grab = placed.first
          .getComponent<jge.TransformComponent>()!
          .position;
      session
        ..onPointerDown(Offset(grab.x, grab.y), 32)
        ..onPointerMove(Offset(grab.x + 128, grab.y), 32)
        ..onPointerUp(Offset(grab.x + 128, grab.y), 32);

      for (var i = 0; i < placed.length; i++) {
        expect(
          placed[i].getComponent<jge.TransformComponent>()!.position.x,
          closeTo(before[i] + 128, 33),
          reason: 'entity $i should have moved with the selection',
        );
      }

      session.dispose();
      world.dispose();
    });

    test('a multi-entity move is one undoable step', () {
      final (:session, :world) = _session();
      final placed = placeRow(session, 3);
      final before = placed
          .map((e) => e.getComponent<jge.TransformComponent>()!.position.x)
          .toList();

      session
        ..onPointerDown(const Offset(-50, -50), 32)
        ..onPointerMove(const Offset(600, 200), 32)
        ..onPointerUp(const Offset(600, 200), 32);

      final grab = placed.first
          .getComponent<jge.TransformComponent>()!
          .position;
      session
        ..onPointerDown(Offset(grab.x, grab.y), 32)
        ..onPointerMove(Offset(grab.x + 256, grab.y), 32)
        ..onPointerUp(Offset(grab.x + 256, grab.y), 32);

      final depthAfterMove = session.history.undoDepth;
      session.history.undo();

      for (var i = 0; i < placed.length; i++) {
        expect(
          placed[i].getComponent<jge.TransformComponent>()!.position.x,
          closeTo(before[i], 1e-6),
          reason: 'one undo should restore every entity',
        );
      }
      expect(session.history.undoDepth, depthAfterMove - 1);

      session.dispose();
      world.dispose();
    });

    test('a click that does not move anything records no history', () {
      final (:session, :world) = _session();
      final placed = placeRow(session, 1);
      final depthBefore = session.history.undoDepth;

      final at = placed.first.getComponent<jge.TransformComponent>()!.position;
      session
        ..onPointerDown(Offset(at.x, at.y), 32)
        ..onPointerUp(Offset(at.x, at.y), 32);

      expect(
        session.history.undoDepth,
        depthBefore,
        reason: 'a plain selection click must not consume an undo slot',
      );

      session.dispose();
      world.dispose();
    });

    test('locked layers are not pickable', () {
      final (:session, :world) = _session();
      placeRow(session, 3);
      // What is placed goes on a layer of the Level Map, locked there.
      jge.LevelMaps.primaryEntity(world)!
              .getComponent<jge.LevelMapComponent>()!
              .inline!
              .layers
              .single
              .locked =
          true;

      session
        ..onPointerDown(const Offset(-50, -50), 32)
        ..onPointerMove(const Offset(600, 200), 32)
        ..onPointerUp(const Offset(600, 200), 32);

      expect(
        session.sceneState.multiSelectedIds.value,
        isEmpty,
        reason: 'a locked layer should be immune to the marquee',
      );

      session.dispose();
      world.dispose();
    });
  });

  group('paint tool', () {
    test('a rectangle fill merges cells into few entities', () {
      final (:session, :world) = _session();
      session
        ..setTool(BuiltInTools.paint)
        ..controller.paintMode.value = PaintMode.rectangle;

      // 8x4 cells at 32px = 32 cells.
      session
        ..onPointerDown(const Offset(0, 0), 32)
        ..onPointerMove(const Offset(256, 128), 32)
        ..onPointerUp(const Offset(256, 128), 32);

      final placed = _blocks(world);
      expect(
        placed,
        hasLength(1),
        reason: '32 painted cells must merge into one entity, not 32 bodies',
      );

      final size = DesignerGeometry.componentSize(placed.single)!;
      expect(size.width, closeTo(256, 1));
      expect(size.height, closeTo(128, 1));

      session.dispose();
      world.dispose();
    });

    test('a whole stroke is one undoable step', () {
      final (:session, :world) = _session();
      session
        ..setTool(BuiltInTools.paint)
        ..controller.paintMode.value = PaintMode.brush;

      session.onPointerDown(const Offset(10, 10), 32);
      for (var x = 40.0; x < 300; x += 32) {
        session.onPointerMove(Offset(x, 10), 32);
      }
      session.onPointerUp(const Offset(300, 10), 32);

      expect(_blocks(world), isNotEmpty);

      session.history.undo();
      expect(
        _blocks(world),
        isEmpty,
        reason: 'one undo should clear the entire stroke',
      );

      session.dispose();
      world.dispose();
    });

    test('the eraser removes what the brush painted', () {
      final (:session, :world) = _session();
      session
        ..setTool(BuiltInTools.paint)
        ..controller.paintMode.value = PaintMode.rectangle;
      session
        ..onPointerDown(const Offset(0, 0), 32)
        ..onPointerMove(const Offset(128, 64), 32)
        ..onPointerUp(const Offset(128, 64), 32);
      expect(_blocks(world), isNotEmpty);

      session.controller.paintMode.value = PaintMode.eraser;
      session.onPointerDown(const Offset(40, 40), 32);
      for (var x = 40.0; x < 130; x += 20) {
        session.onPointerMove(Offset(x, 40), 32);
      }
      session.onPointerUp(const Offset(130, 40), 32);

      expect(_blocks(world), isEmpty);

      session.dispose();
      world.dispose();
    });

    test('erasing is undoable', () {
      final (:session, :world) = _session();
      session
        ..setTool(BuiltInTools.paint)
        ..controller.paintMode.value = PaintMode.rectangle;
      session
        ..onPointerDown(const Offset(0, 0), 32)
        ..onPointerMove(const Offset(128, 64), 32)
        ..onPointerUp(const Offset(128, 64), 32);

      session.controller.paintMode.value = PaintMode.eraser;
      session
        ..onPointerDown(const Offset(40, 40), 32)
        ..onPointerMove(const Offset(100, 40), 32)
        ..onPointerUp(const Offset(100, 40), 32);
      expect(_blocks(world), isEmpty);

      session.history.undo();
      expect(
        _blocks(world),
        isNotEmpty,
        reason: 'undo must bring the erased geometry back',
      );

      session.dispose();
      world.dispose();
    });

    test('switching tool abandons an in-progress gesture', () {
      final (:session, :world) = _session();
      session.setTool(BuiltInTools.draw);

      session
        ..onPointerDown(const Offset(0, 0), 32)
        ..onPointerMove(const Offset(200, 100), 32);
      expect(session.controller.dragRect.value, isNotNull);

      session.setTool(BuiltInTools.select);

      expect(session.controller.dragRect.value, isNull);
      expect(
        _blocks(world),
        isEmpty,
        reason: 'a half-drawn rectangle is not something the author asked for',
      );

      session.dispose();
      world.dispose();
    });
  });
}

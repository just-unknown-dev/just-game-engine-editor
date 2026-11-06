// A press on the rotate ring that does not travel is a click on what is
// under the ring; one dragged round it is a turn — even one too small to
// make a step, which turns nothing and keeps the selection.
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_game_engine_editor/just_game_engine_editor.dart';

import '../support/test_scope.dart';
import 'package:just_game_engine_editor/src/level_designer/level_designer_2d/tools/tiles/tile_select_tool.dart';
import 'package:just_game_engine_editor/src/level_designer/level_designer_2d/tools/tiles/tile_tool_base.dart';
import 'package:just_game_engine_editor/src/level_map/scope_level_maps.dart';

LevelDesignerSession _session(EditorScope scope) {
  final session = LevelDesignerSession(
    scope: scope,
    uniqueName: (p) => p,
    onDuplicate: () {},
    onDelete: () {},
    onArray: (_, _) {},
    readModifiers: () => const ModifierKeys(),
  );
  addTearDown(session.dispose);
  return session;
}

Offset _onRing(Offset centre, double radius, double degrees) {
  final a = degrees * math.pi / 180;
  return centre + Offset(radius * math.sin(a), -radius * math.cos(a));
}

void main() {
  group('entities', () {
    late World world;
    late EditorScope scope;
    late LevelDesignerSession session;
    late Entity box;
    late Offset centre;
    late double radius;

    setUp(() {
      world = World()..initialize();
      scope = testScope(world: world);
      session = _session(scope);
      box = world.createEntityWithComponents([
        TransformComponent(position: Vector3(32, 16, 0)),
        Rectangle2DComponent(width: 64, height: 32),
        LayerComponent(),
      ], name: 'Box');
      session.sceneState.selectEntity(box);
      scope.view.transformMode.value = TransformMode.rotate;
      final bounds = DesignerGeometry.worldBounds(box)!;
      centre = bounds.center;
      radius = scope.handleLayout.ringRadius(bounds, 1);
    });

    test('a drag too small to make a step turns nothing and keeps the '
        'selection', () {
      final from = _onRing(centre, radius, 0);
      final to = _onRing(centre, radius, 5); // the step is 15°
      session
        ..onPointerDown(from, 32)
        ..onPointerMove(to, 32)
        ..onPointerUp(to, 32);
      expect(box.getComponent<TransformComponent>()!.angle, 0);
      expect(session.sceneState.selectedEntity.value, box);
      expect(scope.history.undoEntries, isEmpty);
    });

    test('a drag of a step turns it, as one undo step', () {
      final from = _onRing(centre, radius, 0);
      final to = _onRing(centre, radius, 20);
      session
        ..onPointerDown(from, 32)
        ..onPointerMove(to, 32)
        ..onPointerUp(to, 32);
      expect(
        box.getComponent<TransformComponent>()!.angle,
        closeTo(15 * math.pi / 180, 1e-9),
      );
      expect(scope.history.undoEntries, hasLength(1));
    });

    test('a click on the ring is a click on what is under it: empty ground '
        'lets go of the selection', () {
      final at = _onRing(centre, radius, 0);
      session
        ..onPointerDown(at, 32)
        ..onPointerUp(at, 32);
      expect(session.sceneState.selectedEntity.value, isNull);
    });
  });

  group('tiles', () {
    late World world;
    late EditorScope scope;
    late LevelDesignerSession session;
    late LevelMapData data;
    final tile = TileCell.make(0, 1);

    setUp(() {
      world = World()..initialize();
      registerLevelMapSystems(world);
      scope = testScope(world: world);
      session = _session(scope);
      data = BuiltInPrefabs.newLevelMap(tileSize: 32);
      final ground = data.layers.single;
      for (var x = 0; x < 3; x++) {
        ground.cells.setCell(x, 0, tile);
      }
      final map = world.createEntityWithComponents([
        TransformComponent(),
        LevelMapComponent(inline: data),
      ], name: LevelMaps.primaryName);
      world.update(0);
      scope.tiles
        ..selectMap(map)
        ..selectLayer(ground);
      session.setTool(TileTools.select);
      scope.view.transformMode.value = TransformMode.rotate;
      scope.tiles.selection.value = {
        for (var x = 0; x < 3; x++) TileCoord(x, 0),
      };
    });

    (Offset, double) ring() {
      final target = scope.tiles.target(world)!;
      final bounds = TileSelectTool.cellsBounds(
        target,
        data.layers.single,
        scope.tiles.selection.value,
        null,
      )!;
      return (bounds.center, scope.handleLayout.ringRadius(bounds, 1));
    }

    test('a drag round the ring that comes to no quarter turn leaves the '
        'tiles and their selection as they were', () {
      final (centre, radius) = ring();
      final from = _onRing(centre, radius, 0);
      final to = _onRing(centre, radius, 30); // a step is a quarter turn
      session
        ..onPointerDown(from, 32)
        ..onPointerMove(to, 32)
        ..onPointerUp(to, 32);
      expect(scope.tiles.selection.value, hasLength(3));
      for (var x = 0; x < 3; x++) {
        expect(data.layers.single.cells.cellAt(x, 0), tile);
      }
      expect(scope.history.undoEntries, isEmpty);
    });
  });
}

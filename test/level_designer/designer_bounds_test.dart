// A piece of a Level Map — tiles cut from a layer into an entity — has the
// size of its tiles in the Level Designer: picked by them, swept by a
// marquee, framed, lined up and erased like anything else, its gizmo on
// them rather than on its corner.
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_game_engine_editor/just_game_engine_editor.dart';

import '../support/test_scope.dart';
import 'package:just_game_engine_editor/src/level_designer/state/designer_bounds.dart';
import 'package:just_game_engine_editor/src/level_designer/state/selection_ops.dart';

final int _tile = TileCell.make(0, 1);

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

void main() {
  late World world;
  late EditorScope scope;
  late LevelDesignerSession session;
  late LevelMapData mapData;
  late Entity map;
  late Entity piece;

  setUp(() {
    world = World()..initialize();
    scope = testScope(world: world);
    session = _session(scope);
    mapData = BuiltInPrefabs.newLevelMap();
    map = world.createEntityWithComponents([
      TransformComponent(),
      LevelMapComponent(inline: mapData),
    ], name: LevelMaps.primaryName);
    // Four tiles of 32 in a row, from the piece's origin.
    final pieceData = BuiltInPrefabs.newLevelMap();
    for (var x = 0; x < 4; x++) {
      pieceData.layers.single.cells.setCell(x, 0, _tile);
    }
    piece = world.createEntityWithComponents([
      TransformComponent(position: Vector3(100, 100, 0)),
      LevelMapComponent(inline: pieceData),
      LayerComponent(mapLayer: mapData.layers.single.id),
    ], name: 'Piece');
    placeEntity(
      piece,
      world: world,
      sceneState: session.sceneState,
      slot: HierarchySlot(parentId: map.id, index: -1),
    );
    expect(LevelMaps.isPiece(world, piece), isTrue);
  });

  test('a piece is as big as its tiles, from its origin', () {
    expect(DesignerBounds.of(piece), const Rect.fromLTWH(100, 100, 128, 32));
    expect(
      SelectionOps.boundsOf([piece]),
      const Rect.fromLTWH(100, 100, 128, 32),
    );
    // The whole map is not a piece: it has no size of its own.
    expect(DesignerBounds.of(map), isNull);
  });

  test('a click on its tiles picks it, far from its corner', () {
    session
      ..onPointerDown(const Offset(210, 116), 32)
      ..onPointerUp(const Offset(210, 116), 32);
    expect(session.sceneState.selectedEntity.value, piece);
  });

  test('a marquee over part of its tiles sweeps it up', () {
    session
      ..onPointerDown(const Offset(180, 60), 32)
      ..onPointerMove(const Offset(260, 120), 32)
      ..onPointerUp(const Offset(260, 120), 32);
    expect(session.sceneState.multiSelectedIds.value, {piece.id});
  });

  test('lined up by its tiles, not by its corner', () {
    final box = world.createEntityWithComponents([
      TransformComponent(position: Vector3(50, 300, 0)),
      Rectangle2DComponent(width: 20, height: 20),
      LayerComponent(),
    ], name: 'Box');
    // Box: 40..60; the piece: 100..228. Right edges to 228.
    final union = DesignerBounds.union([piece, box])!;
    expect(union.right, 228);
    expect(
      DesignerBounds.entitiesIn(const Rect.fromLTWH(220, 110, 4, 4), [
        piece,
        box,
      ], pickable: (_) => true),
      [piece],
    );
  });

  test('the eraser takes a piece, never the whole map', () {
    session.setTool(BuiltInTools.paint);
    session.controller.paintMode.value = PaintMode.eraser;
    session
      ..onPointerDown(const Offset(116, 116), 32)
      ..onPointerUp(const Offset(116, 116), 32);
    expect(piece.isAlive, isFalse, reason: 'erased like anything else on it');
    expect(map.isAlive, isTrue);
    scope.history.undo();
    expect(
      world.entities.where((e) => e.name == 'Piece'),
      hasLength(1),
      reason: 'one undo step brings it back',
    );
  });
}

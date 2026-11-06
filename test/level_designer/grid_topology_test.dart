// The grid is a topology. Squares must behave exactly as the geometry helper
// always did; a hex module's designer must place one entity per cell at the
// cell's centre. (HexGrid's own cell tests are just_editor_core's.)

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_game_engine_editor/just_game_engine_editor.dart';

import '../support/test_scope.dart';

void main() {
  group('SquareGrid is the geometry helper', () {
    const grid = SquareGrid();
    test('cells, ranges and merges match DesignerGeometry', () {
      expect(grid.cellAt(const Offset(33, 65), 32), const Point2(1, 2));
      expect(grid.cellsIn(const Rect.fromLTWH(0, 0, 64, 64), 32), hasLength(4));
      expect(
        grid.cellsIn(const Rect.fromLTWH(40, 40, 0, 0), 32).single,
        const Point2(1, 1),
      );
      final cells = {
        const Point2(0, 0),
        const Point2(1, 0),
        const Point2(0, 1),
        const Point2(1, 1),
      };
      expect(grid.merge(cells, 32), [const Rect.fromLTWH(0, 0, 64, 64)]);
      expect(grid.neighbours(const Point2(0, 0)), hasLength(4));
      expect(
        grid.snapRect(const Rect.fromLTWH(3, 5, 10, 10), 32),
        const Rect.fromLTWH(0, 0, 32, 32),
      );
    });
  });

  test('a hex module puts one entity per painted cell, at hex centres', () {
    final scope = testScope(modules: [HexGridModule()])
      ..selectDesigner('hexGrid');
    expect(scope.grid, isA<HexGrid>());
    final session = LevelDesignerSession(
      scope: scope,
      uniqueName: (p) => p,
      onDuplicate: () {},
      onDelete: () {},
      onArray: (_, _) {},
      readModifiers: () => const ModifierKeys(),
    );
    addTearDown(session.dispose);
    const hex = HexGrid();
    session
      ..setTool(BuiltInTools.paint)
      ..controller.activePrefabId.value = BuiltInPrefabs.rectangleId
      ..controller.brushSize.value = 1;
    final cells = [const Point2(0, 0), const Point2(1, 0), const Point2(2, 0)];
    session.onPointerDown(hex.cellCenter(cells[0], 32), 32);
    for (final c in cells.skip(1)) {
      session.onPointerMove(hex.cellCenter(c, 32), 32);
    }
    session.onPointerUp(hex.cellCenter(cells.last, 32), 32);

    // Entities under the Level Map, one per painted cell.
    final map = LevelMaps.primaryEntity(scope.world)!;
    final placed = [
      for (final id in map.getComponent<ChildrenComponent>()!.childIds)
        scope.world.getEntity(id)!,
    ];
    expect(placed, hasLength(3));
    final centres = {for (final c in cells) hex.cellCenter(c, 32)};
    for (final e in placed) {
      final p = e.getComponent<TransformComponent>()!.position;
      final at = Offset(p.x, p.y);
      expect(
        centres.any((c) => (c - at).distance < 1e-6),
        isTrue,
        reason: '$at',
      );
    }
  });
}

// All, Move, Scale and Rotate — V, W, E and R — in the editor and the
// Level Designer: what each can act on, the keys and the toolbar that pick
// one, and the gizmo the selection then shows — on entities, on a piece of
// a map, and on tiles picked with Select tiles.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_game_engine_editor/just_game_engine_editor.dart';
import 'package:just_game_engine_editor/src/ui/overlay/shared/transform_toolbar.dart';

import 'support/test_scope.dart';

final int a = TileCell.make(0, 1);
final int b = TileCell.make(0, 2);

Entity _block(World world, String name, double x, double y) =>
    world.createEntityWithComponents([
      TransformComponent(position: Vector3(x, y, 0)),
      RectangleComponent(width: 64, height: 32),
      LayerComponent(),
    ], name: name);

Offset _pos(Entity e) {
  final p = e.getComponent<TransformComponent>()!.position;
  return Offset(p.x, p.y);
}

void main() {
  setUpAll(registerCoreCodecs);

  group('what can be moved, scaled and turned', () {
    late World world;
    setUp(() => world = World()..initialize());
    tearDown(() => world.dispose());

    test('an entity takes every mode; a map only moves; a piece of one '
        'also turns, in the designer; tiles move and turn', () {
      final box = _block(world, 'Box', 0, 0);
      final map = world.createEntityWithComponents([
        TransformComponent(),
        LevelMapComponent(inline: LevelMapData()),
      ], name: LevelMaps.primaryName);
      final piece = world.createEntityWithComponents([
        TransformComponent(),
        LevelMapComponent(inline: LevelMapData()),
        LayerComponent(mapLayer: 1),
        ParentComponent(parentId: map.id),
      ], name: 'Piece');
      // Nothing to move, turn or scale: no transform at all.
      final label = world.createEntityWithComponents([
        HealthComponent(maxHealth: 1),
      ], name: 'Label');

      expect(
        TransformModes.forEntities(world, [box]),
        TransformMode.values.toSet(),
      );
      expect(TransformModes.forEntities(world, [map]), {
        TransformMode.all,
        TransformMode.move,
      });
      expect(TransformModes.forEntities(world, [piece]), {
        TransformMode.all,
        TransformMode.move,
        TransformMode.rotate,
      });
      expect(TransformModes.forEntities(world, [piece], turnsPieces: false), {
        TransformMode.all,
        TransformMode.move,
      }, reason: 'only the designer turns a piece, by its tiles');
      expect(TransformModes.forEntities(world, [piece, box]), {
        TransformMode.all,
        TransformMode.move,
      }, reason: 'a piece turns its tiles only when it is all that turns');
      expect(TransformModes.forEntities(world, [label]), isEmpty);
      expect(TransformModes.tiles, {
        TransformMode.all,
        TransformMode.move,
        TransformMode.rotate,
      });
    });

    test('what cannot take the mode chosen shows All instead', () {
      expect(
        TransformModes.shown(TransformMode.scale, TransformModes.tiles),
        TransformMode.all,
      );
      expect(
        TransformModes.shown(TransformMode.rotate, TransformModes.tiles),
        TransformMode.rotate,
      );
      expect(
        TransformModes.shown(TransformMode.rotate, TransformModes.none),
        isNull,
      );
    });
  });

  group("the editor's gizmo", () {
    late World world;
    setUp(() => world = World()..initialize());
    tearDown(() => world.dispose());

    test('shows, and answers to, one mode at a time', () {
      final box = world.createEntityWithComponents([
        TransformComponent(),
        RectangleComponent(width: 64, height: 32),
      ], name: 'Box');
      final camera = Camera()..viewportSize = const Size(400, 300);
      final middle = camera.worldToScreen(Offset.zero);
      GizmoHandle at(Offset offset, TransformMode mode) => GizmoHitTester()
          .hitTest(
            middle + offset,
            box,
            [box],
            camera,
            const Size(400, 300),
            mode: mode,
          )
          .handle;

      const xEnd = Offset(GizmoConstants.arrowLength, 0);
      expect(at(xEnd, TransformMode.move), GizmoHandle.translateX);
      expect(at(xEnd, TransformMode.scale), GizmoHandle.scaleX);
      expect(
        at(const Offset(0, -GizmoConstants.arrowLength), TransformMode.rotate),
        isNot(GizmoHandle.translateY),
      );
      expect(at(Offset.zero, TransformMode.move), GizmoHandle.translateXY);
      expect(
        at(Offset.zero, TransformMode.scale),
        GizmoHandle.body,
        reason: 'no free-move square in Scale',
      );

      const ring = Offset(0, GizmoConstants.rotRadius);
      expect(at(ring, TransformMode.rotate), GizmoHandle.rotate);
      expect(at(ring, TransformMode.move), GizmoHandle.none);
    });

    test('All is the gizmo it always was, less what the entity cannot '
        'take', () {
      final box = world.createEntityWithComponents([
        TransformComponent(),
        RectangleComponent(width: 64, height: 32),
      ], name: 'Box');
      final camera = Camera()..viewportSize = const Size(400, 300);
      final middle = camera.worldToScreen(Offset.zero);
      GizmoHandle at(Offset offset, {Set<TransformMode>? allows}) =>
          GizmoHitTester()
              .hitTest(
                middle + offset,
                box,
                [box],
                camera,
                const Size(400, 300),
                allows: allows,
              )
              .handle;

      const shaft = Offset(GizmoConstants.axisSquareOffset, 0);
      final arcEnd =
          Offset(
            math.cos(GizmoConstants.rotSweep),
            math.sin(GizmoConstants.rotSweep),
          ) *
          GizmoConstants.rotRadius;
      expect(at(Offset.zero), GizmoHandle.translateXY, reason: 'the default');
      expect(
        at(const Offset(GizmoConstants.arrowLength, 0)),
        GizmoHandle.translateX,
      );
      expect(at(shaft), GizmoHandle.scaleX);
      expect(at(arcEnd), GizmoHandle.rotate);

      const onlyMoves = {TransformMode.all, TransformMode.move};
      expect(at(shaft, allows: onlyMoves), GizmoHandle.body);
      expect(at(arcEnd, allows: onlyMoves), isNot(GizmoHandle.rotate));
    });
  });

  group('in the Level Designer', () {
    late World world;
    late EditorScope scope;
    late LevelDesignerSession session;
    var control = false;

    setUp(() {
      world = World()..initialize();
      scope = testScope(world: world);
      control = false;
      session = LevelDesignerSession(
        scope: scope,
        uniqueName: (p) => p,
        onDuplicate: () {},
        onDelete: () {},
        onArray: (_, _) {},
        readModifiers: () => ModifierKeys(control: control),
      );
      addTearDown(session.dispose);
      addTearDown(world.dispose);
    });

    bool press(LogicalKeyboardKey key) => scope.commands.dispatch(
      key,
      CommandContext(
        scope: scope,
        session: session,
        modifiers: const ModifierKeys(),
      ),
      scopes: const {CommandScope.editor},
    );

    void drag(Offset from, Offset to) {
      session.onPointerDown(from, 32);
      control = true; // off the grid
      session
        ..onPointerMove(to, 32)
        ..onPointerUp(to, 32);
      control = false;
    }

    test('it starts on All, and V goes back to it with the select tool', () {
      expect(scope.view.transformMode.value, TransformMode.all);
      scope.view.transformMode.value = TransformMode.scale;
      session.setTool(BuiltInTools.draw);
      expect(press(LogicalKeyboardKey.keyV), isTrue);
      expect(scope.view.transformMode.value, TransformMode.all);
      expect(session.controller.toolId.value, BuiltInTools.select);
    });

    test('All is as it was: the handles resize, the knob turns', () {
      final box = _block(world, 'Box', 32, 16); // bounds 0,0 → 64,32
      session.sceneState.selectEntity(box);
      drag(const Offset(64, 32), const Offset(128, 64));
      expect(box.components.whereType<RectangleComponent>().single.width, 128);

      final bounds = DesignerGeometry.worldBounds(box)!;
      final knob = scope.handleLayout.rotateKnobAt(bounds, 1);
      final r = (knob - bounds.center).distance;
      drag(knob, bounds.center + Offset(r, 3));
      expect(
        box.getComponent<TransformComponent>()!.rotation,
        closeTo(math.pi / 2, 0.3),
      );
    });

    test('W, E and R pick the mode and take up the select tool', () {
      session.setTool(TileTools.stamp);
      expect(press(LogicalKeyboardKey.keyR), isTrue);
      expect(scope.view.transformMode.value, TransformMode.rotate);
      expect(session.controller.toolId.value, BuiltInTools.select);
      press(LogicalKeyboardKey.keyE);
      expect(scope.view.transformMode.value, TransformMode.scale);
      press(LogicalKeyboardKey.keyW);
      expect(scope.view.transformMode.value, TransformMode.move);
    });

    test('with tiles selected, Select tiles keeps them', () {
      session.setTool(TileTools.select);
      scope.tiles.selection.value = {const TileCoord(0, 0)};
      press(LogicalKeyboardKey.keyR);
      expect(session.controller.toolId.value, TileTools.select);
    });

    test('the old keys moved: Q selects tiles, Shift+R replaces', () {
      expect(session.selectToolByShortcut('Q'), isTrue);
      expect(session.controller.toolId.value, TileTools.select);
      expect(
        scope.commands.bindingsFor('designer.replace').map((k) => k.shortcut),
        ['Shift+R'],
      );
    });

    test("Move's arrows each keep to their axis", () {
      final box = _block(world, 'Box', 32, 16); // bounds 0,0 → 64,32
      session.sceneState.selectEntity(box);
      scope.view.transformMode.value = TransformMode.move;
      const centre = Offset(32, 16);

      drag(
        TransformGizmo.xEnd(centre),
        TransformGizmo.xEnd(centre) + const Offset(100, 40),
      );
      expect(_pos(box), const Offset(132, 16));

      final moved = const Offset(132, 16);
      drag(
        TransformGizmo.yEnd(moved),
        TransformGizmo.yEnd(moved) + const Offset(50, -64),
      );
      expect(_pos(box), const Offset(132, -48));
    });

    test('a click on the ring that turns nothing picks what is under it', () {
      final a = _block(world, 'A', 32, 16); // bounds 0,0 → 64,32
      final b = _block(world, 'B', 96, 16); // bounds 64,0 → 128,32
      session.sceneState.selectEntity(a);
      scope.view.transformMode.value = TransformMode.rotate;
      final r = scope.handleLayout.ringRadius(
        const Rect.fromLTWH(0, 0, 64, 32),
        1,
      );
      final onRingOverB = const Offset(32, 16) + Offset(r, 0);
      session
        ..onPointerDown(onRingOverB, 32)
        ..onPointerUp(onRingOverB, 32);
      expect(session.sceneState.selectedEntity.value, b);
      expect(a.getComponent<TransformComponent>()!.rotation, 0);
      expect(scope.history.canUndo.value, isFalse);
    });

    test('in Scale the arrows are not there, in Move the corners are not', () {
      final box = _block(world, 'Box', 32, 16);
      session.sceneState.selectEntity(box);
      scope.view.transformMode.value = TransformMode.scale;
      drag(TransformGizmo.xEnd(const Offset(32, 16)), const Offset(300, 300));
      expect(_pos(box), const Offset(32, 16), reason: 'a marquee, not a move');
    });

    test('Rotate turns a piece of a map by its tiles, a quarter at a time; '
        'one undo puts them back', () {
      final mapData = LevelMapData()..addLayer(name: 'Ground');
      final map = world.createEntityWithComponents([
        TransformComponent(),
        LevelMapComponent(inline: mapData),
      ], name: LevelMaps.primaryName);
      final pieceData = LevelMapData();
      final layer = pieceData.addLayer(name: 'Tiles');
      layer.cells
        ..setCell(0, 0, a)
        ..setCell(1, 0, b);
      final piece = world.createEntityWithComponents([
        TransformComponent(),
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
      session.sceneState.selectEntity(piece);
      scope.view.transformMode.value = TransformMode.rotate;

      final bounds =
          DesignerGeometry.worldBounds(piece) ?? Rect.fromLTWH(0, 0, 0, 0);
      final r = scope.handleLayout.ringRadius(bounds, 1);
      final centre = bounds.center;
      drag(centre + Offset(0, -r), centre + Offset(r, 3));

      // About the block's middle cell, (1, 0): a from its left to above it.
      expect(layer.cells.cellAt(1, -1), TileCell.rotatedRight(a));
      expect(layer.cells.cellAt(1, 0), TileCell.rotatedRight(b));
      expect(TileCell.isEmpty(layer.cells.cellAt(0, 0)), isTrue);
      expect(
        piece.getComponent<TransformComponent>()!.rotation,
        0,
        reason: 'a map follows its position only',
      );

      scope.history.undo();
      expect(layer.cells.cellAt(0, 0), a);
      expect(layer.cells.cellAt(1, 0), b);
      expect(TileCell.isEmpty(layer.cells.cellAt(1, -1)), isTrue);
    });

    group('tiles picked with Select tiles', () {
      late LevelMapData data;
      MapLayerData layer() => data.layers.last;
      int cell(int x, int y) => layer().cells.cellAt(x, y);

      setUp(() {
        data = BuiltInPrefabs.newLevelMap();
        final map = world.createEntityWithComponents([
          TransformComponent(),
          LevelMapComponent(inline: data),
        ], name: LevelMaps.primaryName);
        layer().cells
          ..setCell(0, 0, a)
          ..setCell(1, 0, b);
        session.setTool(TileTools.select);
        // The map the tool selects on, before the selection: choosing a
        // map lets go of any selection on another.
        scope.tiles.selectMap(map);
        scope.tiles.selection.value = {
          const TileCoord(0, 0),
          const TileCoord(1, 0),
        };
      });

      // The two cells' block, 0,0 → 64,32 on a 32-pixel grid.
      const centre = Offset(32, 16);

      test("Move's X arrow carries them along X only", () {
        drag(
          TransformGizmo.xEnd(centre),
          TransformGizmo.xEnd(centre) + const Offset(64, 40),
        );
        expect(cell(2, 0), a);
        expect(cell(3, 0), b);
        expect(TileCell.isEmpty(cell(0, 0)), isTrue);
        expect(scope.tiles.selection.value, {
          const TileCoord(2, 0),
          const TileCoord(3, 0),
        });
      });

      test('a click on an arrow keeps the selection', () {
        final tip = TransformGizmo.xEnd(centre);
        session
          ..onPointerDown(tip, 32)
          ..onPointerUp(tip, 32);
        expect(scope.tiles.selection.value, hasLength(2));
        expect(cell(0, 0), a);
      });

      test('the ring turns them a quarter at a time, the selection with '
          'them; one undo puts them back', () {
        scope.view.transformMode.value = TransformMode.rotate;
        final r = scope.handleLayout.ringRadius(
          const Rect.fromLTWH(0, 0, 64, 32),
          1,
        );
        drag(centre + Offset(0, -r), centre + Offset(r, 3));

        expect(cell(1, -1), TileCell.rotatedRight(a));
        expect(cell(1, 0), TileCell.rotatedRight(b));
        expect(TileCell.isEmpty(cell(0, 0)), isTrue);
        expect(scope.tiles.selection.value, {
          const TileCoord(1, -1),
          const TileCoord(1, 0),
        });
        expect(scope.history.nextUndoLabel.value, 'Rotate tiles');

        scope.history.undo();
        expect(cell(0, 0), a);
        expect(cell(1, 0), b);
      });

      test('All has the ring as well as the arrows', () {
        expect(scope.view.transformMode.value, TransformMode.all);
        // Out past the arrowheads, which it would otherwise sit on.
        final r = TransformGizmo.ringClearOfArrows(
          scope.handleLayout.ringRadius(const Rect.fromLTWH(0, 0, 64, 32), 1),
        );
        expect(
          TransformGizmo.moveHandleAt(centre + Offset(0, -r), centre),
          GizmoHandle.none,
        );
        drag(centre + Offset(0, -r), centre + Offset(r, 3));
        expect(cell(1, -1), TileCell.rotatedRight(a));
      });

      test('half-way round and back is no turn at all', () {
        scope.view.transformMode.value = TransformMode.rotate;
        final r = scope.handleLayout.ringRadius(
          const Rect.fromLTWH(0, 0, 64, 32),
          1,
        );
        final top = centre + Offset(0, -r);
        session
          ..onPointerDown(top, 32)
          ..onPointerMove(centre + Offset(r, 0), 32)
          ..onPointerMove(top + const Offset(1, 0), 32)
          ..onPointerUp(top + const Offset(1, 0), 32);
        expect(cell(0, 0), a);
        expect(cell(1, 0), b);
        expect(scope.history.canUndo.value, isFalse);
      });
    });
  });

  group('the toolbar', () {
    late JustGameEditorPlugin plugin;
    const settings = OverlayUiSettings.defaults();

    void done() {
      plugin.dispose();
      Engine.resetInstance();
    }

    Future<void> pump(WidgetTester tester) async {
      Engine.resetInstance();
      final engine = Engine();
      await tester.runAsync(engine.initialize);
      plugin = JustGameEditorPlugin(engine: engine);
      await tester.runAsync(plugin.onInitialize);
      plugin
        ..setVisible(true)
        ..sceneState.openScene(Scene(name: 'level'), const {});
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.topRight,
              child: TransformToolbar(plugin: plugin, settings: settings),
            ),
          ),
        ),
      );
    }

    ToolStripButton button(WidgetTester tester, String tooltip) =>
        tester.widget(
          find.byWidgetPredicate(
            (w) => w is ToolStripButton && w.tooltip == tooltip,
          ),
        );

    testWidgets('four buttons down a column with their keys, All first; '
        'live with nothing selected, and with something', (tester) async {
      await pump(tester);
      const tips = ['All  (V)', 'Move  (W)', 'Scale  (E)', 'Rotate  (R)'];
      for (final tip in tips) {
        expect(button(tester, tip).enabled, isTrue, reason: tip);
      }
      final tops = [
        for (final tip in tips) tester.getRect(find.byTooltip(tip)).top,
      ];
      expect(tops, orderedEquals([...tops]..sort()), reason: 'a column');
      expect(button(tester, 'All  (V)').isActive, isTrue);

      final box = _block(plugin.engine.world, 'Box', 0, 0);
      plugin.sceneState.selectEntity(box);
      await tester.pump();
      expect(button(tester, 'Rotate  (R)').enabled, isTrue);

      await tester.tap(find.byTooltip('Rotate  (R)'));
      await tester.pump();
      expect(plugin.scope.view.transformMode.value, TransformMode.rotate);
      expect(plugin.shownTransformMode, TransformMode.rotate);
      done();
    });

    testWidgets('a level map can only be moved', (tester) async {
      await pump(tester);
      final map = plugin.engine.world.createEntityWithComponents([
        TransformComponent(),
        LevelMapComponent(inline: LevelMapData()),
      ], name: LevelMaps.primaryName);
      plugin.scope.view.transformMode.value = TransformMode.scale;
      plugin.sceneState.selectEntity(map);
      await tester.pump();
      expect(button(tester, 'All  (V)').enabled, isTrue);
      expect(button(tester, 'Move  (W)').enabled, isTrue);
      expect(button(tester, 'Scale  (E)').enabled, isFalse);
      expect(button(tester, 'Rotate  (R)').enabled, isFalse);
      expect(plugin.shownTransformMode, TransformMode.all);
      expect(button(tester, 'All  (V)').isActive, isTrue);
      done();
    });

    testWidgets('in the designer it is the select tool: lit only while that '
        'is in hand, and a click picks it up', (tester) async {
      await pump(tester);
      plugin.openLevelDesigner();
      final session = plugin.designer.value!;
      session.setTool(BuiltInTools.draw);
      await tester.pump();
      expect(
        tester
            .widgetList<ToolStripButton>(find.byType(ToolStripButton))
            .where((b) => b.isActive),
        isEmpty,
      );
      await tester.tap(find.byTooltip('Move  (W)'));
      await tester.pump();
      expect(session.controller.toolId.value, BuiltInTools.select);
      expect(button(tester, 'Move  (W)').isActive, isTrue);
      plugin.closeLevelDesigner();
      done();
    });

    testWidgets('gone during a play-test', (tester) async {
      await pump(tester);
      plugin.play();
      await tester.pump();
      expect(find.byType(ToolStripButton), findsNothing);
      plugin.stop();
      await tester.pump();
      expect(find.byType(ToolStripButton), findsNWidgets(4));
      done();
    });
  });

  test('a quarter turn is a quarter of a whole one', () {
    final g = MapGeometry.of(BuiltInPrefabs.newLevelMap());
    expect(TileTurn.stepAngle(g), closeTo(math.pi / 2, 1e-12));
  });
}

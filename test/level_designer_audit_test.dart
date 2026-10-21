// The Level Designer's fixes from the first-release audit, each driven as
// an author drives it: keys and pointer gestures through a real session.

import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart' show Colors, Icons, MaterialApp;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_game_engine_editor/just_game_engine_editor.dart';

import 'support/test_scope.dart';
import 'package:just_game_engine_editor/src/core/level_map/tile_edit_state.dart';
import 'package:just_game_engine_editor/src/core/scope/editor_scope_services.dart';
import 'package:just_game_engine_editor/src/ui/level_designer/grid/hex_grid.dart';
import 'package:just_game_engine_editor/src/ui/level_designer/panels/tool_palette.dart';
import 'package:just_game_engine_editor/src/ui/level_designer/state/map_placement.dart';
import 'package:just_game_engine_editor/src/ui/level_designer/tools/tiles/tile_select_tool.dart';
import 'package:just_game_engine_editor/src/ui/level_designer/tools/tiles/tile_tool_base.dart';

class _Keys {
  bool shift = false, alt = false, control = false;
  ModifierKeys read() => ModifierKeys(shift: shift, alt: alt, control: control);
}

/// A designer of its own, with state per session, that counts what it is
/// asked to release.
class _Kit extends EditorModule {
  final List<Object> released = [];

  @override
  String get id => 'kit';
  @override
  String get name => 'Kit';
  @override
  bool get providesLevelDesigner => true;
  @override
  Object? createSessionState(DesignerToolContext context) => _KitState();
  @override
  void disposeSessionState(Object state) => released.add(state);
}

class _KitState {}

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
  RigidBody2D(bodyType: BodyType.static),
  Collider2D(size: Vector2(w, h)),
  LayerComponent(),
], name: name);

Offset _pos(Entity e) {
  final p = e.getComponent<TransformComponent>()!.position;
  return Offset(p.x, p.y);
}

void main() {
  late World world;
  late EditorScope scope;
  late LevelDesignerSession session;
  late _Keys keys;
  late _Kit kit;
  var closed = false;

  setUp(() {
    world = World()..initialize();
    kit = _Kit();
    scope = testScope(world: world, modules: [kit]);
    keys = _Keys();
    var n = 0;
    closed = false;
    session = LevelDesignerSession(
      scope: scope,
      uniqueName: (p) => '${p}_${n++}',
      onDuplicate: () {},
      onDelete: () {},
      onArray: (_, _) {},
      readModifiers: keys.read,
    );
  });
  tearDown(() {
    if (!closed) session.dispose();
  });

  void close() {
    closed = true;
    session.dispose();
  }

  bool key(LogicalKeyboardKey k) => session.handleKey(k, gridSize: 32);
  String status() => session.controller.status.value;
  void under(Entity child, Entity parent) => placeEntity(
    child,
    world: world,
    sceneState: session.sceneState,
    slot: HierarchySlot(parentId: parent.id, index: -1),
  );
  Entity levelMap({LevelMapData? data, Vector3? at}) =>
      world.createEntityWithComponents([
        TransformComponent(position: at ?? Vector3.zero()),
        LevelMapComponent(inline: data ?? BuiltInPrefabs.newLevelMap()),
      ], name: LevelMaps.primaryName);

  PrefabDefinition prefabFile() => PrefabDefinition(
    id: 'file:prefabs/crate.prefab.json',
    name: 'Crate',
    category: 'Prefab files',
    icon: Icons.inventory_2_outlined,
    color: Colors.blue,
    placement: PrefabPlacement.point,
    instanceOf: 'prefabs/crate.prefab.json',
    build: (_, _) => const [],
  );

  group('prefab files are placed, not built (LD-3)', () {
    test('Shift+R with one in hand replaces nothing and says why', () {
      final a = _block(world, 'A', 100, 50);
      session.sceneState.selectEntity(a);
      final file = prefabFile();
      session.sessionPrefabs.register(file);
      session.controller.activePrefabId.value = file.id;
      keys.shift = true;
      key(LogicalKeyboardKey.keyR);
      keys.shift = false;
      expect(a.isAlive, isTrue);
      expect(session.history.undoDepth, 0);
      expect(status(), contains('prefab file'));
      // Nor straight through the selection edits.
      session.ops.replaceWith([a], file);
      expect(a.isAlive, isTrue);
      expect(session.history.undoDepth, 0);
    });

    test('Paint with one in hand paints nothing and says why', () {
      final file = prefabFile();
      session.sessionPrefabs.register(file);
      session
        ..setTool(BuiltInTools.paint)
        ..controller.activePrefabId.value = file.id
        ..onPointerDown(const Offset(48, 48), 32)
        ..onPointerUp(const Offset(48, 48), 32);
      expect(world.query([TransformComponent]), isEmpty);
      expect(status(), contains('prefab file'));
    });
  });

  test('undo, redo and save wait for a drag to end (LD-5)', () {
    final a = _block(world, 'A', 32, 16);
    session.sceneState.selectEntity(a);
    session.ops.nudge([a], const Offset(10, 0));
    session
      ..onPointerDown(const Offset(42, 16), 32)
      ..onPointerMove(const Offset(142, 16), 32);
    final context = CommandContext(
      scope: scope,
      session: session,
      modifiers: const ModifierKeys(),
    );
    scope.commands.byId('editor.undo')!.run(context);
    expect(session.history.undoDepth, 1, reason: 'the nudge is still there');
    expect(status(), contains('waits'));
    scope.commands.byId('editor.save')!.run(context);
    expect(status(), contains('Saving waits'));
    session.onPointerUp(const Offset(142, 16), 32);
    expect(session.history.undoDepth, 2);
    expect(session.history.nextUndoLabel.value, startsWith('Move'));
  });

  group('closing the designer (LD-6, LD-23)', () {
    test('mid-stroke puts the stroke back, with no step and no map left', () {
      session.setTool(TileTools.stamp);
      scope.tiles.stamp.value = TileStamp.single(TileCell.make(0, 1));
      session.onPointerDown(const Offset(16, 16), 32);
      final made = world.query([LevelMapComponent]).single;
      expect(
        made
            .getComponent<LevelMapComponent>()!
            .inline!
            .layers
            .single
            .cells
            .cellAt(0, 0),
        TileCell.make(0, 1),
      );
      close();
      expect(world.query([LevelMapComponent]), isEmpty);
      expect(scope.history.undoDepth, 0);
      expect(scope.tiles.preview, isEmpty);
    });

    test('mid-drag puts what moved back where it was', () {
      final a = _block(world, 'A', 32, 16);
      session.sceneState.selectEntity(a);
      session
        ..onPointerDown(const Offset(32, 16), 32)
        ..onPointerMove(const Offset(232, 16), 32);
      expect(_pos(a), isNot(const Offset(32, 16)));
      close();
      expect(_pos(a), const Offset(32, 16));
      expect(scope.history.undoDepth, 0);
    });

    test('a module\'s session state is released when it leaves and when the '
        'session closes', () {
      scope.selectDesigner('kit');
      final first = session.stateOf<_KitState>();
      expect(first, isNotNull);
      scope.selectDesigner(null);
      expect(kit.released, [first]);
      scope.selectDesigner('kit');
      final second = session.stateOf<_KitState>();
      close();
      expect(kit.released, [first, second]);
    });
  });

  group('Alt+drag copies whole groups, as Ctrl+D does (LD-7)', () {
    late Entity group;
    late Entity coin;
    setUp(() {
      group = world.createEntityWithComponents([
        TransformComponent(position: Vector3(100, 100, 0)),
      ], name: 'Group');
      // Either side of the group, so its origin is no handle of theirs.
      coin = _block(world, 'Coin', 60, 100, w: 32, h: 32);
      under(coin, group);
      under(_block(world, 'Gem', 140, 100, w: 16, h: 16), group);
    });

    List<Entity> groups() => [
      for (final e in world.query([TransformComponent]))
        if (e.name!.startsWith('Group')) e,
    ];
    List<EntityId> childrenOf(Entity e) =>
        e.getComponent<ChildrenComponent>()?.childIds ?? const [];

    void altDrag({Offset from = const Offset(100, 100)}) {
      keys.alt = true;
      session
        ..onPointerDown(from, 32)
        ..onPointerMove(from + const Offset(200, 0), 32)
        ..onPointerUp(from + const Offset(200, 0), 32);
      keys.alt = false;
    }

    test('a group\'s copy holds copies of what it holds', () {
      session.sceneState.selectEntity(group);
      altDrag();
      expect(world.query([TransformComponent]), hasLength(6));
      final copy = groups().singleWhere((e) => e.id != group.id);
      expect(childrenOf(copy), hasLength(2));
      expect(childrenOf(group), hasLength(2));
      expect(
        childrenOf(copy).toSet().intersection(childrenOf(group).toSet()),
        isEmpty,
      );
      expect(_pos(group), const Offset(100, 100));

      session.history.undo();
      expect(world.query([TransformComponent]), hasLength(3));
      session.history.redo();
      expect(world.query([TransformComponent]), hasLength(6));
      final again = groups().singleWhere((e) => e.id != group.id);
      expect(childrenOf(again), hasLength(2), reason: 'made again whole');
    });

    test('a group and one of its own, both selected, are copied once', () {
      session.sceneState
        ..selectEntity(group)
        ..toggleMultiSelect(coin);
      // Pressed on the coin, in the middle of the selection's box.
      altDrag(from: const Offset(60, 100));
      expect(world.query([TransformComponent]), hasLength(6));
    });
  });

  group('the brush knows its tilesets by path (LD-8)', () {
    late LevelMapData data;
    setUp(() {
      data = LevelMapData(
        tileWidth: 32,
        tileHeight: 32,
        tilesets: ['t/b.tileset.json'],
      )..addLayer(name: 'Ground');
      levelMap(data: data);
      session.setTool(TileTools.stamp);
    });

    int cell(int x, int y) => data.layers.single.cells.cellAt(x, y);
    void click(int x, int y) {
      final at = MapGeometry.of(data).cellCenter(x, y);
      session
        ..onPointerDown(at, 32)
        ..onPointerUp(at, 32);
    }

    test('a tile from another map paints the same tile here', () {
      // Picked on a map that keeps b in slot 1; this one keeps it in 0.
      scope.tiles.setStamp(
        TileStamp.single(TileCell.make(1, 3)),
        tilesets: const {0: 't/a.tileset.json', 1: 't/b.tileset.json'},
      );
      click(0, 0);
      expect(cell(0, 0), TileCell.make(0, 3));
    });

    test('a tile of a tileset the map lacks is refused, and named', () {
      scope.tiles.setStamp(
        TileStamp.single(TileCell.make(0, 3)),
        tilesets: const {0: 't/a.tileset.json'},
      );
      click(1, 0);
      expect(TileCell.isEmpty(cell(1, 0)), isTrue);
      expect(status(), contains('t/a.tileset.json'));
    });

    test('Ctrl+V and a turn keep what the slots stand for', () {
      const table = {1: 't/b.tileset.json'};
      scope.tiles.setClipboard(
        TileStamp.single(TileCell.make(1, 2)),
        tilesets: table,
      );
      keys.control = true;
      key(LogicalKeyboardKey.keyV);
      keys.control = false;
      expect(scope.tiles.stampTilesets, table);
      key(LogicalKeyboardKey.keyZ);
      expect(scope.tiles.stampTilesets, table);
      // A brush set without saying is painted as it is.
      scope.tiles.stamp.value = TileStamp.single(TileCell.make(0, 5));
      expect(scope.tiles.stampTilesets, isEmpty);
    });
  });

  test('resizing keeps the same components, and undoes exactly (LD-9)', () {
    final a = _block(world, 'A', 32, 16); // bounds 0,0 -> 64,32
    session.sceneState.selectEntity(a);
    session.scope.view.transformMode.value = TransformMode.scale;
    final collider = a.getComponent<Collider2D>();
    final rect = a.components.whereType<RectangleComponent>().single;
    session
      ..onPointerDown(const Offset(64, 32), 32)
      ..onPointerMove(const Offset(96, 48), 32);
    expect(identical(a.getComponent<Collider2D>(), collider), isTrue);
    expect(
      identical(a.components.whereType<RectangleComponent>().single, rect),
      isTrue,
    );
    session
      ..onPointerMove(const Offset(8, 8), 32)
      ..onPointerMove(const Offset(128, 64), 32)
      ..onPointerUp(const Offset(128, 64), 32);
    expect((rect.width, rect.height), (128.0, 64.0));
    session.history.undo();
    expect(a.components.whereType<RectangleComponent>().single.width, 64);
  });

  group('Paint Fill (LD-11)', () {
    void walls() {
      _block(world, 'Top', 64, 16, w: 128, h: 32);
      _block(world, 'Bottom', 64, 80, w: 128, h: 32);
      _block(world, 'Left', 16, 48, w: 32, h: 32);
      _block(world, 'Right', 112, 48, w: 32, h: 32);
    }

    void fillAt(Offset at) => session
      ..setTool(BuiltInTools.paint)
      ..controller.paintMode.value = PaintMode.fill
      ..controller.activePrefabId.value = BuiltInPrefabs.solidId
      ..onPointerDown(at, 32)
      ..onPointerUp(at, 32);

    test('fills a room inside a camera\'s bounds drawn round the level', () {
      walls();
      // What a camera's bounds or a region looks like: a box round it all.
      world.createEntityWithComponents([
        TransformComponent(position: Vector3(64, 48, 0)),
        RectangleComponent(width: 2000, height: 2000),
      ], name: 'Camera bounds');
      fillAt(const Offset(50, 48));
      final filled = [
        for (final e in world.query([LayerComponent]))
          if (LevelMaps.memberLayer(world, e) != null) e,
      ];
      expect(filled, hasLength(1));
    });

    test('a click inside something solid says so', () {
      walls();
      fillAt(const Offset(64, 16));
      expect(status(), contains('inside Top'));
    });
  });

  test('a click near the Level Map\'s origin picks what is there, not the '
      'map (LD-15)', () {
    final map = levelMap();
    final platform = _block(world, 'Platform', 16, 8);
    under(platform, map);
    session
      ..onPointerDown(const Offset(2, 2), 32)
      ..onPointerUp(const Offset(2, 2), 32);
    expect(session.sceneState.selectedEntity.value, same(platform));
  });

  group('the eyedropper (LD-16)', () {
    Entity drawCopy(Entity sampled) {
      session
        ..setTool(BuiltInTools.draw)
        ..setTool(BuiltInTools.eyedropper)
        ..onPointerDown(_pos(sampled), 32)
        ..onPointerUp(_pos(sampled), 32);
      session
        ..onPointerDown(const Offset(0, 320), 32)
        ..onPointerMove(const Offset(128, 352), 32)
        ..onPointerUp(const Offset(128, 352), 32);
      return world
          .query([TransformComponent])
          .firstWhere((e) => e.name!.startsWith('Ledge') && e.id != sampled.id);
    }

    test('copies a scaled thing at the size drawn', () {
      final a = _block(world, 'Ledge', 32, 16);
      a.getComponent<TransformComponent>()!.scale
        ..x = 2
        ..y = 2;
      final copy = drawCopy(a);
      expect(DesignerGeometry.worldBounds(copy)!.size, const Size(128, 32));
    });

    test('copies a thing turned a quarter at the size drawn', () {
      final a = _block(world, 'Ledge', 32, 160);
      a.getComponent<TransformComponent>()!.angle = math.pi / 2;
      final size = DesignerGeometry.worldBounds(drawCopy(a))!.size;
      expect(size.width, closeTo(128, 1e-6));
      expect(size.height, closeTo(32, 1e-6));
    });
  });

  test('the layer under the pointer is the one drawn on top, not the last '
      'listed (LD-17)', () {
    final data = LevelMapData(tileWidth: 16, tileHeight: 16);
    final ground = data.addLayer(name: 'Ground');
    final back = data.addLayer(name: 'Back')
      ..sortLayerId = 'background'
      ..sortLayer = -100;
    ground.cells.setCell(0, 0, TileCell.make(0, 1));
    back.cells.setCell(0, 0, TileCell.make(0, 2));
    final target = scope.mapDocs.resolve(levelMap(data: data))!;
    expect(
      TileSelectTool.layerUnder(target, const Offset(8, 8), null)!.name,
      'Ground',
    );
    expect(TileTool.drawOrder(data.layers).last.name, 'Ground');
  });

  test('a cancelled move takes its smart guides with it (LD-19)', () {
    final a = _block(world, 'A', 32, 16);
    session.sceneState.selectEntity(a);
    session
      ..onPointerDown(const Offset(32, 16), 32)
      ..onPointerMove(const Offset(100, 16), 32);
    session.controller.snapGuides = const [
      SnapGuide(vertical: true, position: 0, start: 0, end: 10),
    ];
    session.onPointerCancel();
    expect(session.controller.snapGuides, isEmpty);
    expect(session.controller.spacingGuides, isEmpty);
  });

  test('X pressed mid-drag of a filled rectangle still fills it (LD-20)', () {
    final data = BuiltInPrefabs.newLevelMap();
    levelMap(data: data);
    final g = MapGeometry.of(data);
    session.setTool(TileTools.fill);
    scope.tiles
      ..fillShape.value = TileFillShape.rect
      ..stamp.value = TileStamp.single(TileCell.make(0, 1));
    session
      ..onPointerHover(g.cellCenter(5, 5), 32)
      ..onPointerDown(g.cellCenter(0, 0), 32)
      ..onPointerMove(g.cellCenter(2, 1), 32);
    key(LogicalKeyboardKey.keyX);
    session.onPointerUp(g.cellCenter(2, 1), 32);
    final cells = data.layers.single.cells;
    for (var y = 0; y <= 1; y++) {
      for (var x = 0; x <= 2; x++) {
        expect(TileCell.isEmpty(cells.cellAt(x, y)), isFalse, reason: '$x,$y');
      }
    }
    expect(TileCell.isEmpty(cells.cellAt(5, 5)), isTrue);
  });

  test('guides saved as something else are skipped, not thrown (LD-24)', () {
    session.restoreEditorData({'guides': <String, Object?>{}});
    expect(session.controller.guides.value, isEmpty);
    session.restoreEditorData({'guides': 'none'});
    expect(session.controller.guides.value, isEmpty);
  });

  test('a ruler guide being pulled goes again when the drag is abandoned '
      '(LD-29)', () {
    session.camera.viewportSize = const Size(800, 600);
    const canvas = Size(800, 600);
    expect(session.onChromePointerDown(const Offset(200, 5), canvas), isTrue);
    expect(session.controller.guides.value, hasLength(1));
    session.onPointerCancel();
    expect(session.controller.guides.value, isEmpty);
    expect(session.history.undoDepth, 0);
  });

  test('Ctrl+A takes what is on the Level Map, not the map (LD-31)', () {
    final map = levelMap();
    final a = _block(world, 'A', 0, 0);
    final b = _block(world, 'B', 200, 0);
    under(a, map);
    under(b, map);
    session.selectAll();
    expect(session.sceneState.multiSelectedIds.value, {a.id, b.id});
  });

  group('big tile areas are refused, not laid out (LD-4)', () {
    late LevelMapData data;
    setUp(() {
      data = BuiltInPrefabs.newLevelMap();
      levelMap(data: data);
    });

    Offset at(int x, int y) => MapGeometry.of(data).cellCenter(x, y);

    test('a box selection', () {
      session.setTool(TileTools.select);
      scope.tiles.selectMode.value = TileSelectMode.rect;
      session
        ..onPointerDown(at(0, 0), 32)
        ..onPointerMove(at(400, 400), 32)
        ..onPointerUp(at(400, 400), 32);
      expect(scope.tiles.selection.value, isEmpty);
      expect(status(), contains('Too many'));
    });

    test('a filled rectangle', () {
      session.setTool(TileTools.fill);
      scope.tiles
        ..fillShape.value = TileFillShape.rect
        ..stamp.value = TileStamp.single(TileCell.make(0, 1));
      session
        ..onPointerDown(at(0, 0), 32)
        ..onPointerMove(at(400, 400), 32);
      expect(scope.tiles.preview, isEmpty);
      session.onPointerUp(at(400, 400), 32);
      expect(TileCell.isEmpty(data.layers.single.cells.cellAt(0, 0)), isTrue);
      expect(scope.history.undoDepth, 0);
    });

    test('tiles picked up', () {
      session.setTool(TileTools.stamp);
      session
        ..onPointerDown(at(0, 0), 32, button: ToolButton.secondary)
        ..onPointerMove(at(400, 400), 32)
        ..onPointerUp(at(400, 400), 32);
      expect(scope.tiles.stamp.value, isNull);
      expect(status(), contains('Too much'));
    });
  });

  group('a flood that reaches its limit does nothing, and says so (LD-18)', () {
    late LevelMapData data;
    setUp(() {
      data = BuiltInPrefabs.newLevelMap();
      levelMap(data: data);
      // A view of far more open ground than a flood may take.
      session.camera.viewportSize = const Size(20000, 20000);
    });

    void click(int x, int y) {
      final at = MapGeometry.of(data).cellCenter(x, y);
      session
        ..onPointerDown(at, 32)
        ..onPointerUp(at, 32);
    }

    test('the bucket', () {
      session.setTool(TileTools.fill);
      scope.tiles
        ..fillShape.value = TileFillShape.bucket
        ..stamp.value = TileStamp.single(TileCell.make(0, 1));
      click(0, 0);
      expect(TileCell.isEmpty(data.layers.single.cells.cellAt(0, 0)), isTrue);
      expect(status(), contains('more than'));
    });

    test('the wand', () {
      session.setTool(TileTools.select);
      scope.tiles.selectMode.value = TileSelectMode.wand;
      click(0, 0);
      expect(scope.tiles.selection.value, isEmpty);
      expect(status(), contains('more than'));
    });
  });

  test('the hex grid draws without touching the camera (LD-21)', () {
    final view = GameCameraEditorView.of(Camera())
      ..viewportSize = const Size(100, 100);
    final recorder = PictureRecorder();
    const HexGrid().paintGrid(
      Canvas(recorder),
      view,
      const Size(800, 600),
      cellSize: 32,
    );
    recorder.endRecording().dispose();
    expect(view.viewportSize, const Size(100, 100));
  });

  testWidgets('the undo button names the step it would undo (LD-28)', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: EditorScopeProvider(
          scope: scope,
          child: ToolPalette(session: session),
        ),
      ),
    );
    scope.history.push(
      CallbackCommand(label: 'First', onRedo: () {}, onUndo: () {}),
    );
    await tester.pump();
    expect(find.byTooltip('Undo First  (Ctrl+Z)'), findsOneWidget);
    scope.history.push(
      CallbackCommand(label: 'Second', onRedo: () {}, onUndo: () {}),
    );
    await tester.pump();
    expect(find.byTooltip('Undo Second  (Ctrl+Z)'), findsOneWidget);
  });

  test('a map file that will not load says so (LD-26)', () async {
    world.createEntityWithComponents([
      TransformComponent(),
      LevelMapComponent(mapPath: 'maps/missing.map.json'),
    ], name: LevelMaps.primaryName);
    try {
      await scope.mapDocs.tiles.map('maps/missing.map.json');
    } on Object {
      // Expected: there is no such file.
    }
    expect(MapPlacement.whyNoMap(scope, world), contains('could not be read'));
  });
}

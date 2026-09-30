// Double-clicks between the scene tree and the Level Designer: the Level
// Map's row opens the designer on it, ready to paint, and open ground in the
// designer selects the map.

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_game_engine_editor/just_game_engine_editor.dart';

import 'support/test_scope.dart';

/// Records how many presses each gesture began with.
class _Clicks extends LevelToolHandler {
  final counts = <int>[];

  @override
  String get id => 'test.clicks';
  @override
  String get label => 'Clicks';
  @override
  IconData get icon => const IconData(0x41);

  @override
  bool onPointerDown(ToolContext context) {
    counts.add(context.clickCount);
    return true;
  }
}

void main() {
  setUpAll(registerCoreCodecs);

  group('in the designer', () {
    late World world;
    late EditorScope scope;
    late LevelDesignerSession session;

    setUp(() {
      world = World()..initialize();
      scope = testScope(world: world);
      session = LevelDesignerSession(
        scope: scope,
        uniqueName: (p) => p,
        onDuplicate: () {},
        onDelete: () {},
        onArray: (_, _) {},
        readModifiers: () => const ModifierKeys(),
      );
      addTearDown(session.dispose);
    });

    void press(Offset at, int ms, {Offset? screen}) {
      session.onPointerDown(
        at,
        32,
        screen: screen ?? at,
        time: Duration(milliseconds: ms),
      );
      session.onPointerUp(at, 32);
    }

    test('a second press soon after and close by is a double-click', () {
      final probe = _Clicks();
      session.tools.register(probe);
      session.setTool(probe.id);
      press(Offset.zero, 0);
      press(Offset.zero, 200);
      press(Offset.zero, 300);
      expect(probe.counts, [1, 2, 3], reason: 'a run keeps counting');

      press(Offset.zero, 2000);
      expect(probe.counts.last, 1, reason: 'too late');
      press(const Offset(40, 0), 2100);
      expect(probe.counts.last, 1, reason: 'too far');

      // A press made by code has no time: never a double-click.
      session.onPointerDown(Offset.zero, 32);
      session.onPointerDown(Offset.zero, 32);
      expect(probe.counts.last, 1);
    });

    test('a double-click on open ground selects the Level Map', () {
      final map = world.createEntityWithComponents([
        TransformComponent(),
        LevelMapComponent(inline: BuiltInPrefabs.newLevelMap()),
      ], name: LevelMaps.primaryName);
      scope.sceneState.registerEntity(map);
      session.setTool(BuiltInTools.select);
      const ground = Offset(500, 500);
      press(ground, 0);
      expect(scope.sceneState.selectedEntity.value, isNull);
      press(ground, 150);
      expect(scope.sceneState.selectedEntity.value, same(map));
      expect(scope.tiles.mapEntityId.value, map.id);
    });
  });

  group('in the scene tree', () {
    late JustGameEditorPlugin plugin;

    setUp(() async {
      TestWidgetsFlutterBinding.ensureInitialized();
      Engine.resetInstance();
      final engine = Engine();
      await engine.initialize();
      plugin = JustGameEditorPlugin(engine: engine);
      await plugin.onInitialize();
      plugin.sceneState.openScene(Scene(name: 'level'));
    });

    tearDown(() {
      plugin.dispose();
      Engine.resetInstance();
    });

    test('double-clicking the Level Map opens the designer on it, the '
        'Stamp in hand and the view on what is painted', () {
      final data = BuiltInPrefabs.newLevelMap();
      data.layers.single.cells
        ..setCell(10, 2, TileCell.make(0, 1))
        ..setCell(12, 4, TileCell.make(0, 1));
      final map = plugin.engine.world.createEntityWithComponents([
        TransformComponent(),
        LevelMapComponent(inline: data),
      ], name: LevelMaps.primaryName);

      plugin.focusOn(map);
      expect(plugin.isLevelDesignerOpen, isTrue);
      final session = plugin.designer.value!;
      expect(session.controller.toolId.value, TileTools.stamp);
      expect(plugin.scope.tiles.mapEntityId.value, map.id);
      expect(plugin.sceneState.selectedEntity.value, same(map));
      // Cells 10..12 and 2..4 of 32px: centred on cell (11, 3).
      expect(
        plugin.engine.cameraSystem.mainCamera.position,
        const Offset(11 * 32 + 16, 3 * 32 + 16),
      );

      // A tile tool already in hand stays.
      session.setTool(TileTools.fill);
      plugin.focusOn(map);
      expect(session.controller.toolId.value, TileTools.fill);
    });

    test('anything else is framed, as before', () {
      final crate = plugin.engine.world.createEntityWithComponents([
        TransformComponent(position: Vector3(300, 200, 0)),
      ], name: 'Crate');
      plugin.focusOn(crate);
      expect(plugin.isLevelDesignerOpen, isFalse);
      expect(
        plugin.engine.cameraSystem.mainCamera.position,
        const Offset(300, 200),
      );
    });
  });
}

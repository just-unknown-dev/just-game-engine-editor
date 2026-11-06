// Keys and presses the Level Designer's session hands on: Esc lets go of a
// ruler guide being pulled (and nothing else), a tool's keys act once a
// press however long the key is held, and a press arriving while a gesture
// is still open ends that gesture first.
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_game_engine_editor/just_game_engine_editor.dart';

import '../support/test_scope.dart';
import 'package:just_game_engine_editor/src/level_designer/level_designer_2d/tools/tiles/tile_tool_base.dart';
import 'package:just_game_engine_editor/src/level_designer/level_designer_session.dart';
import 'package:just_game_engine_editor/src/level_map/scope_level_maps.dart';

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

Entity _block(World world, String name, double x, double y) =>
    world.createEntityWithComponents([
      TransformComponent(position: Vector3(x, y, 0)),
      Rectangle2DComponent(width: 64, height: 32),
      LayerComponent(),
    ], name: name);

void main() {
  late World world;
  late EditorScope scope;
  late LevelDesignerSession session;

  setUp(() {
    world = World()..initialize();
    scope = testScope(world: world);
    session = _session(scope);
  });

  group('Esc while a ruler guide is pulled', () {
    test('lets the guide go, and keeps the selection', () {
      final box = _block(world, 'Box', 32, 16);
      session.sceneState.selectEntity(box);
      const canvas = Size(800, 600);
      expect(session.onChromePointerDown(const Offset(300, 5), canvas), isTrue);
      expect(session.controller.guides.value, hasLength(1));
      expect(
        session.handleKey(LogicalKeyboardKey.escape, gridSize: 32),
        isTrue,
      );
      expect(session.hasChromeGesture, isFalse);
      expect(
        session.controller.guides.value,
        isEmpty,
        reason: 'the guide the press made goes with it, as no step records it',
      );
      expect(session.sceneState.selectedEntity.value, box);
      expect(scope.history.undoEntries, isEmpty);
    });

    test('the Cancel command, whatever key it is on, lets the guide go and '
        'keeps the selection too', () {
      final box = _block(world, 'Box', 32, 16);
      session.sceneState.selectEntity(box);
      const canvas = Size(800, 600);
      expect(session.onChromePointerDown(const Offset(300, 5), canvas), isTrue);
      scope.commands
          .byId('designer.cancel')!
          .run(
            CommandContext(
              scope: scope,
              session: session,
              modifiers: const ModifierKeys(),
            ),
          );
      expect(session.hasChromeGesture, isFalse);
      expect(session.controller.guides.value, isEmpty);
      expect(session.sceneState.selectedEntity.value, box);
    });

    test('with no guide pulled, Esc still clears the selection', () {
      final box = _block(world, 'Box', 32, 16);
      session.sceneState.selectEntity(box);
      session.handleKey(LogicalKeyboardKey.escape, gridSize: 32);
      expect(session.sceneState.selectedEntity.value, isNull);
    });
  });

  group('a tool key held down', () {
    setUp(() {
      registerLevelMapSystems(world);
      final map = world.createEntityWithComponents([
        TransformComponent(),
        LevelMapComponent(inline: BuiltInPrefabs.newLevelMap()),
      ], name: 'Map');
      world.update(0);
      scope.tiles.selectMap(map);
      session.setTool(TileTools.stamp);
      scope.tiles.stamp.value = TileStamp.single(_tile);
    });

    test('turns the brush once, however many times it repeats', () {
      expect(session.handleKey(LogicalKeyboardKey.keyZ, gridSize: 32), isTrue);
      final once = scope.tiles.stamp.value;
      for (var i = 0; i < 5; i++) {
        expect(
          session.handleKey(
            LogicalKeyboardKey.keyZ,
            gridSize: 32,
            isRepeat: true,
          ),
          isTrue,
          reason: 'kept, so nothing else acts on it either',
        );
      }
      expect(scope.tiles.stamp.value, same(once));
      // Let go and pressed again: another turn.
      session.handleKey(LogicalKeyboardKey.keyZ, gridSize: 32);
      expect(scope.tiles.stamp.value, isNot(same(once)));
    });

    test('a repeat the tool never had does not reach it', () {
      final before = scope.tiles.stamp.value;
      session.handleKey(LogicalKeyboardKey.keyZ, gridSize: 32, isRepeat: true);
      expect(scope.tiles.stamp.value, same(before));
    });
  });

  group('a press while a gesture is still open', () {
    test('puts the open one back first, as Esc would, so it is never '
        'overwritten half-done', () {
      final box = _block(world, 'Box', 32, 16);
      session
        ..onPointerDown(const Offset(32, 16), 32)
        ..onPointerMove(const Offset(132, 16), 32);
      expect(box.getComponent<TransformComponent>()!.position.x, isNot(32));
      // Its release lost: the window lost focus mid-drag.
      session.onPointerDown(const Offset(500, 500), 32);
      expect(
        box.getComponent<TransformComponent>()!.position.x,
        32,
        reason: 'not left moved with no undo step',
      );
      session.onPointerUp(const Offset(500, 500), 32);
      expect(scope.history.undoEntries, isEmpty);
    });
  });
}

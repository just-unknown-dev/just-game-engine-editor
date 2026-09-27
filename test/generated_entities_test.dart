// Entities a system builds from other data — a tile map's collision bodies —
// are not part of the level. They must never be saved, listed in the scene
// tree, picked in the viewport or left behind by a scene switch.
//
// Also here: what else a scene switch resets (the undo history), and which
// JSON files the viewport takes for sprite atlases.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_game_engine_editor/just_game_engine_editor.dart';
import 'package:just_game_engine_editor/src/core/state/play_snapshot.dart';

import 'support/test_scope.dart';

Entity _generated(World world, String name) =>
    world.createEntityWithComponents([
      TransformComponent(),
      PhysicsBodyComponent(shape: RectangleShape(32, 32), isStatic: true),
      GeneratedEntityComponent(source: 'test'),
    ], name: name);

void main() {
  setUpAll(registerCoreCodecs);

  group('a generated entity', () {
    late World world;
    late EditorScope scope;
    setUp(() {
      world = World()..initialize();
      scope = testScope(world: world);
    });

    test('is not authored, so nothing saves it', () {
      final platform = world.createEntityWithComponents([
        TransformComponent(),
      ], name: 'Platform');
      final body = _generated(world, 'Body');

      final authored = PlaySnapshot.authored(world);

      expect(authored, contains(platform));
      expect(authored, isNot(contains(body)));
      expect(PlaySnapshot.isGenerated(body), isTrue);
      expect(
        [for (final e in scope.codec.encodeEntities(authored)) e['name']],
        ['Platform'],
      );
    });

    test('made during play is gone when play stops', () {
      world.createEntityWithComponents([TransformComponent()], name: 'A');
      final snapshot = PlaySnapshot.capture(world, scope.codec);

      final body = _generated(world, 'Body');
      snapshot.restoreInto(world);

      expect(body.isAlive, isFalse);
    });

    test('is not listed in the scene tree', () {
      final platform = world.createEntityWithComponents([
        TransformComponent(),
      ], name: 'Platform');
      _generated(world, 'Body');

      final tree = SceneTreeModel.build(
        world: world,
        rootOrder: const [],
        expanded: const {},
      );

      expect([for (final row in tree.rows) row.entity], [platform]);
    });
  });

  group('opening a scene', () {
    late Directory project;
    late EditorScope scope;
    late SceneIO io;

    setUp(() {
      project = Directory.systemTemp.createTempSync('generated_test');
      final scenes = Directory('${project.path}/assets/scenes')
        ..createSync(recursive: true);
      File('${scenes.path}/level_test.scene.json').writeAsStringSync(
        jsonEncode({
          'version': SceneFormat.current,
          ...Scene(name: 'level_test').toJson(),
          'entities': [
            {
              'name': 'Platform',
              'components': [
                {
                  'type': 'TransformComponent',
                  'fields': {
                    'position': {'x': 0.0, 'y': 0.0},
                  },
                },
              ],
            },
          ],
        }),
      );
      File('${scenes.path}/scenes.json').writeAsStringSync(
        jsonEncode({
          'scenes': ['level_test'],
        }),
      );
      scope = testScope(scenesRoot: scenes.path);
      io = SceneIO(
        scope: scope,
        world: () => scope.world,
        sceneState: scope.sceneState,
      );
      addTearDown(() {
        if (project.existsSync()) project.deleteSync(recursive: true);
      });
    });

    test('destroys what a system generated for the last one', () async {
      await io.open('level_test');
      final body = _generated(scope.world, 'Body');

      await io.open('level_test');

      expect(body.isAlive, isFalse);
      expect(scope.world.findEntityByName('Platform'), isNotNull);
    });

    test('starts a new undo history', () async {
      await io.open('level_test');
      scope.history.push(
        CallbackCommand(label: 'Something', onRedo: () {}, onUndo: () {}),
      );
      expect(scope.history.canUndo.value, isTrue);

      await io.open('level_test');

      expect(scope.history.canUndo.value, isFalse);
      expect(scope.history.canRedo.value, isFalse);
    });
  });

  group('the viewport takes for a sprite atlas', () {
    test('a plain .json', () {
      expect(
        JustGameEditorPlugin.isSpriteAtlasPath('assets/a/hero.json'),
        true,
      );
      expect(JustGameEditorPlugin.canDropAsset('assets/a/hero.json'), true);
    });

    test('none of the editor\'s other data files', () {
      for (final path in [
        'assets/scenes/level_01.scene.json',
        'assets/scenes/scenes.json',
        'assets/sprites/player.animator.json',
        'assets/timelines/coin.timeline.json',
        'assets/ui/default.uitheme.json',
      ]) {
        expect(
          JustGameEditorPlugin.isSpriteAtlasPath(path),
          isFalse,
          reason: path,
        );
        expect(JustGameEditorPlugin.canDropAsset(path), isFalse, reason: path);
      }
      // Tile files are no atlases either, but they do drop: as tile maps.
      for (final path in [
        'assets/tilesets/grass.tileset.json',
        'assets/maps/cave.tilemap.json',
      ]) {
        expect(
          JustGameEditorPlugin.isSpriteAtlasPath(path),
          isFalse,
          reason: path,
        );
        expect(JustGameEditorPlugin.canDropAsset(path), isTrue, reason: path);
      }
    });
  });
}

// Work that happens on its own — an import still reading, the log capture,
// the scene checks — must act on what is open now and cost little: an
// import that finishes after the scene changed does nothing, the log is
// not flooded by a game that spawns, and the checks count a big map's
// tiles again only when they changed.

import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_game_engine_editor/just_game_engine_editor.dart';

import 'support/test_scope.dart';
import 'package:just_game_engine_editor/src/core/ecs/systems/editor_log_capture_system.dart';
import 'package:just_game_engine_editor/src/core/validation/built_in_validators.dart';
import 'package:just_game_engine_editor/src/extension/built_in_tile_contributions.dart';

void main() {
  group('an import still reading when the scene changes (EC-35)', () {
    test('does not land in the scene opened meanwhile', () async {
      final scope = testScope();
      scope.sceneState.openScene(EditorScene(name: 'first'));
      final reading = Completer<String>();
      final files = TiledFiles(
        root: Directory.systemTemp.path,
        read: (_) => reading.future,
        write: (_, _) async {},
        exists: (_) => false,
      );
      final importing = BuiltInTileContributions.importIntoScene(
        scope,
        'level.tmx',
        using: files,
      );
      scope.sceneState.openScene(EditorScene(name: 'second'));
      // A real map: read whole, it would import.
      reading.complete(
        File('../just_tiled/test/fixtures/ortho_finite.tmx').readAsStringSync(),
      );
      expect(await importing, 0);
      expect(
        scope.log.entries.value.map((e) => e.message),
        contains(contains('the scene changed')),
      );
      expect(scope.world.entities.where((e) => e.isAlive), isEmpty);
    });
  });

  group('the log capture (EC-40)', () {
    test('logs a change of systems, not every change of entities', () async {
      final world = World()..initialize();
      addTearDown(world.dispose);
      final scope = testScope(world: world);
      final capture = EditorLogCaptureSystem(scope.log);
      world.addSystem(capture);
      int lines() => scope.log.entries.value
          .where((e) => e.message.startsWith('World snapshot changed'))
          .length;

      capture.update(0);
      final first = lines();
      for (var i = 0; i < 20; i++) {
        world.createEntity(name: 'Bullet $i');
        capture.update(0);
      }
      expect(lines(), first, reason: 'at most one every few seconds');

      await Future<void>.delayed(const Duration(milliseconds: 300));
      world.addSystem(MovementSystem());
      capture.update(0);
      expect(lines(), first + 1, reason: 'a system came: said at once');
    });
  });

  group('the map checks (EC-27)', () {
    test('count a layer\'s tiles again when they change', () {
      final scope = testScope();
      final data = LevelMapData()..addLayer(name: 'Ground');
      scope.world.createEntityWithComponents([
        TransformComponent(),
        LevelMapComponent(inline: data),
      ], name: LevelMaps.primaryName);
      final cells = data.layers.single.cells;
      // Slot 3: a tileset the map does not have.
      cells.setCell(0, 0, TileCell.make(3, 1));
      String? orphans() =>
          BuiltInValidators.levelMaps(
                ValidationContext(
                  scope: scope,
                  projectRoot: Directory.systemTemp.path,
                ),
              )
              .map((p) => p.message)
              .where((m) => m.contains('no longer has'))
              .firstOrNull;

      expect(orphans(), contains('1 tile '));
      expect(orphans(), contains('1 tile '), reason: 'unchanged: the same');
      cells.setCell(1, 0, TileCell.make(3, 1));
      expect(orphans(), contains('2 tiles'));
      cells
        ..setCell(0, 0, TileCell.empty)
        ..setCell(1, 0, TileCell.empty);
      expect(orphans(), isNull);
    });
  });
}

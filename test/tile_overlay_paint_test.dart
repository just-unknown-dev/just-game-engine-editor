// Painting the tile overlays must not choose a map or a layer. Choosing
// writes signals, and a signal written mid-paint schedules a build during
// the frame — the "Build scheduled during frame" errors the editor logged
// whenever a tile tool was in hand with nothing chosen yet.

import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_game_engine_editor/just_game_engine_editor.dart';

import 'support/test_scope.dart';
import 'package:just_game_engine_editor/src/core/scope/editor_scope_services.dart';
import 'package:just_game_engine_editor/src/ui/level_designer/overlays/tile_overlays.dart';
import 'package:just_game_engine_editor/src/ui/level_designer/tools/tiles/tile_tool_base.dart';

void main() {
  late World world;
  late EditorScope scope;
  late LevelDesignerSession session;

  setUp(() {
    world = World()..initialize();
    registerLevelMapSystems(world);
    scope = testScope(world: world);
    session = LevelDesignerSession(
      scope: scope,
      uniqueName: (p) => p,
      onDuplicate: () {},
      onDelete: () {},
      onArray: (_, _) {},
      readModifiers: ModifierKeys.fromHardwareKeyboard,
    );
    addTearDown(session.dispose);
    world.createEntityWithComponents([
      TransformComponent(),
      LevelMapComponent(inline: BuiltInPrefabs.newLevelMap(tileSize: 16)),
    ], name: 'Level map');
    world.update(0);
    // A tile tool in hand, and no map or layer chosen yet.
    session.controller.toolId.value = TileTools.fill;
    scope.tiles.mapEntityId.value = null;
    scope.tiles.layerId.value = null;
  });

  test('the tile overlays paint without choosing anything', () {
    final writes = <String>[];
    final unwatchMap = scope.tiles.mapEntityId.watch(() => writes.add('map'));
    final unwatchLayer = scope.tiles.layerId.watch(() => writes.add('layer'));
    addTearDown(() {
      unwatchMap();
      unwatchLayer();
    });

    final recorder = PictureRecorder();
    final context = OverlayPaintContext(
      draw: DesignerCanvas(
        canvas: Canvas(recorder),
        size: const Size(400, 300),
        camera: GameCameraEditorView.of(Camera()),
      ),
      world: world,
      controller: session.controller,
    );
    for (final overlay in [TileGridOverlay(scope), TileBrushOverlay(scope)]) {
      overlay.paint(context);
    }
    recorder.endRecording().dispose();

    expect(writes, isEmpty);
    expect(scope.tiles.mapEntityId.value, isNull);
    expect(scope.tiles.layerId.value, isNull);
  });
}

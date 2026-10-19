// The scene tree and the inspector beside it, where they used to lose
// work or misbehave: a Tiled map's layer rows change nothing (a save would
// write the editor's map over the Tiled file), the list scrolls to the row
// asked for, Ungroup takes apart groups only, and an inspector pinned to
// something deleted lets go without breaking the frame.

import 'dart:io' show FileSystemException;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_game_engine_editor/just_game_engine_editor.dart';

import 'support/test_scope.dart';
import 'package:just_game_engine_editor/src/core/entity/entity_ops.dart';
import 'package:just_game_engine_editor/src/core/level_map/tile_commands.dart';
import 'package:just_game_engine_editor/src/core/scope/editor_scope_services.dart';
import 'package:just_game_engine_editor/src/ui/panels/entity_inspector_panel.dart';
import 'package:just_game_engine_editor/src/ui/scene_tree/scene_tree_controller.dart';
import 'package:just_game_engine_editor/src/ui/scene_tree/scene_tree_panel.dart';

void main() {
  late EditorScope scope;
  late EntityOps ops;
  late SceneTreeController controller;

  setUp(() {
    scope = testScope();
    ops = EntityOps(
      scope: scope,
      world: () => scope.world,
      sceneState: scope.sceneState,
      camera: () => GameCameraEditorView.of(Camera()),
    );
    controller = SceneTreeController(world: () => scope.world);
    addTearDown(controller.dispose);
    scope.sceneState.openScene(EditorScene(name: 'level'));
  });

  Entity make(String name, List<Component> components) {
    final e = scope.world.createEntityWithComponents(components, name: name);
    scope.sceneState.registerEntity(e);
    return e;
  }

  Future<void> pumpTree(WidgetTester tester, {Widget? beside}) async {
    tester.view
      ..physicalSize = const Size(720, 600)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Row(
            children: [
              SizedBox(
                width: 320,
                child: SceneTreePanel(
                  scope: scope,
                  entities: ops,
                  controller: controller,
                ),
              ),
              if (beside != null) Expanded(child: beside),
            ],
          ),
        ),
      ),
    );
    await tester.pump();
  }

  group('a Tiled map named directly', () {
    const path = 'assets/maps/caves.tmx';
    late Entity map;
    late MapLayerData back;

    setUp(() {
      final data = LevelMapData();
      back = data.addLayer(name: 'Back');
      scope.world.context.tiles.putMap(path, data);
      map = make(LevelMaps.primaryName, [
        TransformComponent(),
        LevelMapComponent(mapPath: path),
      ]);
    });

    testWidgets('its layer rows say what is shown and locked, and change '
        'nothing', (tester) async {
      controller.expand(map.id);
      await pumpTree(tester);
      expect(find.text('Back'), findsOneWidget);
      expect(find.byTooltip('Hide map layer'), findsNothing);
      expect(find.byTooltip('Lock map layer'), findsNothing);

      await tester.tap(
        find.byTooltip('A Tiled map: convert it to edit it').first,
      );
      await tester.pump();
      expect((back.visible, back.locked), (true, false));

      // A double-click does not open the rename box.
      final boxes = find.byType(TextField).evaluate().length;
      await tester.tap(find.text('Back'));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(find.text('Back'));
      await tester.pump();
      expect(find.byType(TextField).evaluate().length, boxes);

      expect(scope.history.undoEntries, isEmpty);
      expect(scope.mapDocs.dirtyPaths.value, isEmpty);
    });

    test('nothing marks its file to be saved, and nothing writes it', () async {
      scope.mapDocs.markEdited(LevelMapRef(entityId: map.id, path: path));
      expect(scope.mapDocs.dirtyPaths.value, isEmpty);
      await expectLater(
        scope.mapDocs.writeMap(path, LevelMapData()),
        throwsA(isA<FileSystemException>()),
      );
      await expectLater(
        scope.mapDocs.writeMap('assets/maps/CAVES.TMJ', LevelMapData()),
        throwsA(isA<FileSystemException>()),
      );
    });
  });

  testWidgets('the list scrolls to the row asked for, rows being as tall as '
      'they are drawn', (tester) async {
    expect(kSceneTreeRowHeight, kSceneTreeRowTileHeight);
    final row = kSceneTreeRowTileHeight;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 300,
            child: ListView.builder(
              controller: controller.scroll,
              itemExtent: row,
              itemCount: 300,
              itemBuilder: (_, i) => Text('row $i'),
            ),
          ),
        ),
      ),
    );
    void expectShown(int index) {
      final position = controller.scroll.position;
      expect(position.pixels, lessThanOrEqualTo(index * row + 1e-6));
      expect(
        position.pixels + position.viewportDimension,
        greaterThanOrEqualTo((index + 1) * row - 1e-6),
      );
    }

    controller.scrollToIndex(200);
    await tester.pump();
    expectShown(200);
    controller.scrollToIndex(14);
    await tester.pump();
    expectShown(14);
    controller.scrollToIndex(299);
    await tester.pump();
    expectShown(299);
  });

  group('ungroup', () {
    late Entity player, weapon;
    setUp(() {
      player = make('Player', [
        TransformComponent(),
        ChildrenComponent(),
        CircleComponent(radius: 4),
      ]);
      weapon = make('Weapon', [TransformComponent(), ChildrenComponent()]);
      ops.reparentEntity(weapon, player);
    });

    test('takes apart a group only: an entity holding others stays', () {
      ops.ungroup(player);
      expect(player.isAlive, isTrue);
      expect(weapon.getComponent<ParentComponent>()?.parentId, player.id);
      expect(scope.history.undoEntries, hasLength(1), reason: 'the reparent');
    });

    testWidgets('Ctrl+Shift+G in the tree leaves a non-group whole', (
      tester,
    ) async {
      await pumpTree(tester);
      await tester.tap(find.text('Player'));
      await tester.pump(const Duration(milliseconds: 600));
      expect(scope.sceneState.selectedEntity.value, same(player));
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyG);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();
      expect(player.isAlive, isTrue);
      expect(weapon.getComponent<ParentComponent>()?.parentId, player.id);
    });
  });

  testWidgets('an inspector pinned to something deleted lets go of it '
      'without breaking the frame', (tester) async {
    final a = make('A', [TransformComponent()]);
    scope.sceneState.selectEntity(a);
    await pumpTree(
      tester,
      beside: EntityInspectorPanel(
        scope: scope,
        sceneState: scope.sceneState,
        world: scope.world,
        onGroupSelection: () {},
      ),
    );
    scope.view.togglePinned(a.id);
    await tester.pump();

    scope.sceneState.clearSelection();
    scope.world.destroyEntity(a);
    scope.sceneState.refresh();
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(scope.view.pinned.value, isNull);
    await tester.pump();
    expect(find.text('Nothing selected'), findsOneWidget);
  });
}

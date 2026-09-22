// The scene tree over a piece of interface: what a drop does, and what
// each row looks like.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_game_engine_editor/just_game_engine_editor.dart';

import 'support/test_scope.dart';

void main() {
  setUpAll(registerCoreCodecs);

  late EditorScope scope;
  late EntityOps ops;

  setUp(() {
    scope = testScope();
    ops = EntityOps(
      scope: scope,
      world: () => scope.world,
      sceneState: scope.sceneState,
      camera: Camera.new,
    );
    scope.sceneState.openScene(Scene(name: 'level_test'), const {});
  });

  List<EntityId> childrenOf(Entity entity) =>
      entity.getComponent<ChildrenComponent>()?.childIds ?? const [];

  group('moving interface about', () {
    test('an element can be dropped into a panel', () {
      final canvas = ops.createUi('canvas')!;
      final panel = ops.createUi('panel')!;
      // Made under the canvas, beside the panel rather than in it.
      final text = ops.createUi('text', parent: canvas)!;
      expect(text.getComponent<ParentComponent>()!.parentId, canvas.id);

      ops.reparentEntity(text, panel);

      expect(text.getComponent<ParentComponent>()!.parentId, panel.id);
      expect(childrenOf(panel), contains(text.id));
      expect(childrenOf(canvas), isNot(contains(text.id)));
    });

    test('a panel that has never held anything grows a children list', () {
      final canvas = ops.createUi('canvas')!;
      final text = ops.createUi('text', parent: canvas)!;
      // A bare entity, as a game's own component might leave one.
      final holder = scope.world.createEntityWithComponents([
        UiPanelComponent(),
        UiSlotComponent(),
        ParentComponent(parentId: canvas.id),
      ], name: 'Bare');

      ops.reparentEntity(text, holder);

      expect(holder.getComponent<ChildrenComponent>(), isNotNull);
      expect(childrenOf(holder), [text.id]);
    });

    test('a parent cannot be dropped into its own child', () {
      ops.createUi('canvas');
      final panel = ops.createUi('panel')!;
      final text = ops.createUi('text', parent: panel)!;

      ops.reparentEntity(panel, text);

      expect(childrenOf(text), isEmpty);
      expect(childrenOf(panel), contains(text.id));
    });
  });

  group('what a row shows', () {
    test('every kind of interface has an icon of its own', () {
      final canvas = ops.createUi('canvas')!;
      final icons = <String, IconData?>{
        for (final option in UiCreateOptions.builtIns)
          option.id: uiIconFor(ops.createUi(option.id, parent: canvas)!),
      };

      // Nothing falls through to "some entity".
      expect(icons.values, everyElement(isNotNull));
      // A screen and a layer are told apart, and so are the containers.
      expect(icons['canvas'], Icons.web_asset);
      expect(icons['screen'], Icons.web_asset_outlined);
      expect(icons['row'], Icons.view_column);
      expect(icons['column'], Icons.view_agenda);
      expect(icons['text'], Icons.text_fields);
      expect(icons['button'], Icons.smart_button);
      expect(icons['panel'], Icons.rectangle_outlined);
      // Every kind that is not a container reads as itself.
      final leaves = [
        for (final entry in icons.entries)
          if (!const ['canvas', 'screen'].contains(entry.key)) entry.value,
      ];
      expect(leaves.toSet().length, greaterThan(8));
    });

    test('a widget the game brought reads as one', () {
      ops.createUi('canvas');
      UiWidgets.register(
        UiWidgetDefinition(
          id: 'mini_map',
          label: 'Mini map',
          build: (context) => const SizedBox.shrink(),
        ),
      );
      addTearDown(UiWidgets.clear);

      final made = ops.createUi('custom:mini_map')!;

      expect(uiIconFor(made), Icons.extension_outlined);
    });

    test('an entity that is not interface is left alone', () {
      final world = scope.world;
      final plain = world.createEntityWithComponents([
        TransformComponent(),
      ], name: 'Platform');

      expect(uiIconFor(plain), isNull);
    });

    testWidgets('the tree draws them', (tester) async {
      ops.createUi('canvas');
      ops.createUi('screen');

      tester.view.physicalSize = const Size(360, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SceneTreePanel(
              scope: scope,
              sceneState: scope.sceneState,
              world: scope.world,
              onCreateEntity: () {},
              onCreateGroup: () {},
              onCreateGroupFrom: (_) {},
              onDeleteEntity: (_) {},
              onCopyEntity: (_) {},
              onPasteEntity: () {},
              onReparentEntity: (_, _) {},
            ),
          ),
        ),
      );
      await tester.pump();

      // Both are canvases with children lists, and neither reads as a
      // folder because of it.
      expect(find.byIcon(Icons.web_asset), findsOneWidget);
      expect(find.byIcon(Icons.web_asset_outlined), findsOneWidget);
      expect(find.byIcon(Icons.folder_rounded), findsNothing);
    });
  });
  group('what a drop on a row means', () {
    // A tree row is about this tall.
    const height = 31.0;

    test('the body of a row means inside it', () {
      expect(dropZoneFor(height / 2, height), DropZone.onto);
      // Eight pixels down used to mean "between": the band was a share of
      // the row, which left most of a row meaning something other than
      // what it looks like it means.
      expect(dropZoneFor(8, height), DropZone.onto);
      expect(dropZoneFor(height - 8, height), DropZone.onto);
    });

    test('the very edges mean between', () {
      expect(dropZoneFor(0, height), DropZone.above);
      expect(dropZoneFor(4, height), DropZone.above);
      expect(dropZoneFor(height, height), DropZone.below);
      expect(dropZoneFor(height - 1, height), DropZone.below);
    });

    test('a row too short to have edges is all body', () {
      // A third each way at most, so there is always somewhere to drop
      // into however tight the row.
      expect(dropZoneFor(6, 12), DropZone.onto);
      expect(dropZoneFor(1, 12), DropZone.above);
    });

    test('most of a row means inside it', () {
      var onto = 0;
      for (var dy = 0.0; dy <= height; dy += 0.5) {
        if (dropZoneFor(dy, height) == DropZone.onto) onto++;
      }
      expect(onto / (height / 0.5 + 1), greaterThan(0.6));
    });
  });
  group('a piece of interface is not in the world', () {
    test('the viewport gizmo has nothing to grab, and does not throw', () {
      ops.createUi('canvas');
      final text = ops.createUi('text')!;
      final platform = scope.world.createEntityWithComponents([
        TransformComponent(position: Vector3(100, 100, 0)),
        RectangleComponent(width: 64, height: 16),
      ], name: 'Platform');

      final camera = Camera();
      // The interface is selected — from the tree, as it now can be —
      // and the pointer moves over the viewport.
      expect(
        () => GizmoHitTester().hitTest(
          const Offset(10, 10),
          text,
          [platform],
          camera,
          const Size(400, 300),
        ),
        returnsNormally,
      );
      final result = GizmoHitTester().hitTest(
        const Offset(10, 10),
        text,
        [platform],
        camera,
        const Size(400, 300),
      );
      expect(result.isNone, isTrue);
    });

    test('the world still hit-tests around it', () {
      final platform = scope.world.createEntityWithComponents([
        TransformComponent(position: Vector3(0, 0, 0)),
        RectangleComponent(width: 200, height: 200),
      ], name: 'Platform');
      ops.createUi('canvas');
      final text = ops.createUi('text')!;

      final camera = Camera()..viewportSize = const Size(400, 300);
      final middle = camera.worldToScreen(Offset.zero);

      // Interface selected, but the platform under the pointer is still
      // found: the selection being elsewhere must not blind the viewport.
      final result = GizmoHitTester().hitTest(
        middle,
        text,
        [platform],
        camera,
        const Size(400, 300),
      );

      expect(result.entity?.id, platform.id);
    });
  });
}

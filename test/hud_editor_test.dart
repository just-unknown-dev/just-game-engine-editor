// The HUD editor as a window of its own: what the world's tree shows of a
// HUD (a leaf), what the HUD editor's tree shows (the HUDs), and the
// window's own buttons.

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_game_engine_editor/just_game_engine_editor.dart';

import 'support/test_scope.dart';

void main() {
  setUpAll(registerCoreCodecs);

  late EditorScope scope;

  Entity entity(String name, List<Component> components, {Entity? under}) {
    final made = scope.world.createEntityWithComponents([
      ...components,
      ChildrenComponent(),
    ], name: name);
    scope.sceneState.registerEntity(made);
    if (under != null) scope.entities.reparentEntity(made, under);
    return made;
  }

  setUp(() {
    scope = testScope();
    scope.sceneState.openScene(Scene(name: 'level_test'), const {});
  });

  SceneTree treeOf(
    TreeContents contents, {
    Set<EntityId> expanded = const {},
  }) => SceneTreeModel.build(
    world: scope.world,
    rootOrder: scope.sceneState.rootOrder(scope.world),
    expanded: expanded,
    contents: contents,
  );

  List<String?> namesIn(SceneTree tree) => [
    for (final row in tree.rows) row.entity.name,
  ];

  Future<void> open(
    WidgetTester tester, {
    required VoidCallback onClose,
    ValueNotifier<bool>? fullScreen,
  }) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: UiModeOverlay(
            scope: scope,
            session: scope.uiMode,
            sceneState: scope.sceneState,
            history: scope.history,
            onClose: onClose,
            fullScreen: fullScreen,
            onToggleFullScreen: fullScreen == null
                ? null
                : () => fullScreen.value = !fullScreen.value,
          ),
        ),
      ),
    );
    await tester.pump();
  }

  group('what each tree shows', () {
    test('a HUD is a leaf in the world, whatever is in it', () {
      final platform = entity('Platform', [TransformComponent()]);
      final hud = entity('Hud', [TransformComponent(), UiCanvasComponent()]);
      entity('Coins', [UiSlotComponent()], under: hud);

      final world = treeOf(TreeContents.world, expanded: {hud.id, platform.id});

      // Open or shut, nothing of the interface is listed here — and no
      // chevron offers to list it.
      expect(namesIn(world), ['Platform', 'Hud']);
      expect(
        world.rows.firstWhere((r) => r.entity.id == hud.id).hasChildren,
        isFalse,
      );
    });

    test('the HUD editor is rooted at the HUDs, and shows what is in them', () {
      entity('Platform', [TransformComponent()]);
      final hud = entity('Hud', [TransformComponent(), UiCanvasComponent()]);
      final coins = entity('Coins', [UiSlotComponent()], under: hud);
      entity('CoinsLabel', [UiSlotComponent()], under: coins);

      final ui = treeOf(TreeContents.ui, expanded: {hud.id, coins.id});

      expect(namesIn(ui), ['Hud', 'Coins', 'CoinsLabel']);
      expect(ui.rows.first.depth, 0);
      expect(ui.rows.last.depth, 2);
    });

    test('every HUD in the scene is a root, wherever it hangs', () {
      final group = entity('Interface', [TransformComponent()]);
      // One at the top level and one parked inside a world group: both are
      // roots here, so you can switch between them without going back.
      entity('Hud', [TransformComponent(), UiCanvasComponent()]);
      entity('PauseHud', [
        TransformComponent(),
        UiCanvasComponent(),
      ], under: group);

      expect(namesIn(treeOf(TreeContents.ui)), ['Hud', 'PauseHud']);
      // And the group that holds one is still an ordinary world row.
      expect(namesIn(treeOf(TreeContents.world)), ['Interface', 'Hud']);
    });
  });

  group('moving things about', () {
    test('a widget can be moved from one HUD to another', () {
      final hud = entity('Hud', [TransformComponent(), UiCanvasComponent()]);
      final pause = entity('Pause', [
        TransformComponent(),
        UiCanvasComponent(),
      ]);
      final coins = entity('Coins', [UiSlotComponent()], under: hud);

      scope.entities.reparentAll([coins], pause);

      expect(coins.getComponent<ParentComponent>()!.parentId, pause.id);
      expect(
        hud.getComponent<ChildrenComponent>()!.childIds,
        isNot(contains(coins.id)),
      );
      // And the interface tree shows it in its new home.
      final ui = treeOf(TreeContents.ui, expanded: {hud.id, pause.id});
      expect(namesIn(ui), ['Hud', 'Pause', 'Coins']);

      // One step back.
      scope.history.undo();
      expect(coins.getComponent<ParentComponent>()!.parentId, hud.id);
    });

    test('a widget dropped on nothing stays where it is', () {
      final hud = entity('Hud', [TransformComponent(), UiCanvasComponent()]);
      final coins = entity('Coins', [UiSlotComponent()], under: hud);

      // What a drop past the last row would do in the world's tree. In
      // the interface tree the panel refuses it, because a widget at the
      // world's top level is in no screen at all and would vanish from
      // here.
      scope.entities.reparentAll([coins], null);
      expect(namesIn(treeOf(TreeContents.ui, expanded: {hud.id})), ['Hud']);
      scope.history.undo();

      expect(coins.getComponent<ParentComponent>()!.parentId, hud.id);
    });
  });

  group('the window', () {
    testWidgets('has a close button and one that fills the editor', (
      tester,
    ) async {
      var closed = false;
      final filled = ValueNotifier(false);
      addTearDown(filled.dispose);
      await open(tester, onClose: () => closed = true, fullScreen: filled);

      expect(find.byIcon(Icons.open_in_full), findsOneWidget);
      await tester.tap(find.byIcon(Icons.open_in_full));
      await tester.pump();
      expect(filled.value, isTrue);
      // And it offers the way back.
      expect(find.byIcon(Icons.close_fullscreen), findsOneWidget);

      await tester.tap(find.byIcon(Icons.close));
      expect(closed, isTrue);
    });

    testWidgets('Escape shuts it', (tester) async {
      var closed = false;
      await open(tester, onClose: () => closed = true);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();

      expect(closed, isTrue);
    });

    double frameWidth(WidgetTester tester) =>
        tester.getSize(find.byType(FittedBox).first).width;

    testWidgets('the screen can be sized, and put back to fit', (tester) async {
      await open(tester, onClose: () {});
      final fitted = frameWidth(tester);

      // It starts fitted to the window, and says so.
      expect(scope.uiMode.isFitted, isTrue);
      expect(find.text('Fit'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.add));
      await tester.pump();

      expect(scope.uiMode.isFitted, isFalse);
      expect(frameWidth(tester), greaterThan(fitted));
      // The first step out is a step from what the eye was looking at,
      // not from 100%.
      expect(
        scope.uiMode.zoom.value,
        greaterThan(fitted / scope.uiMode.frameSize.width),
      );
      expect(find.text('Fit'), findsNothing);

      final larger = scope.uiMode.zoom.value;
      await tester.tap(find.byIcon(Icons.remove));
      await tester.pump();
      expect(
        scope.uiMode.zoom.value,
        lessThan(larger),
        reason: 'it was $larger',
      );
    });

    testWidgets('Ctrl and the wheel sizes it; Ctrl+0 fits it again', (
      tester,
    ) async {
      await open(tester, onClose: () {});
      final fitted = frameWidth(tester);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      final pointer = TestPointer(1, PointerDeviceKind.mouse);
      final over = tester.getCenter(find.byType(FittedBox).first);
      await tester.sendEventToBinding(pointer.hover(over));
      await tester.sendEventToBinding(pointer.scroll(const Offset(0, -60)));
      await tester.pump();

      expect(scope.uiMode.isFitted, isFalse, reason: 'the wheel sized it');
      expect(frameWidth(tester), greaterThan(fitted));

      await tester.sendKeyEvent(LogicalKeyboardKey.digit0);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();

      expect(scope.uiMode.isFitted, isTrue);
      expect(frameWidth(tester), fitted);
    });

    testWidgets('the wheel alone sizes it, about the pointer', (tester) async {
      await open(tester, onClose: () {});
      final was = tester.getRect(find.byType(FittedBox).first);
      // A corner of the screen, well away from the middle of the view.
      final corner = was.topLeft + const Offset(20, 20);

      final pointer = TestPointer(1, PointerDeviceKind.mouse);
      await tester.sendEventToBinding(pointer.hover(corner));
      await tester.sendEventToBinding(pointer.scroll(const Offset(0, -80)));
      await tester.pump();

      // No Ctrl needed, and what was under the pointer is still there.
      expect(scope.uiMode.isFitted, isFalse);
      final now = tester.getRect(find.byType(FittedBox).first);
      expect(now.width, greaterThan(was.width));
      expect(
        (now.topLeft - corner).dx,
        closeTo((was.topLeft - corner).dx * (now.width / was.width), 1.5),
      );

      // Sizing about a corner has to have moved the view.
      expect(scope.uiMode.pan.value, isNot(Offset.zero));
    });

    testWidgets('the middle button pushes the view about', (tester) async {
      await open(tester, onClose: () {});
      scope.uiMode.zoom.value = 1;
      await tester.pump();
      final was = tester.getTopLeft(find.byType(FittedBox).first);

      final pointer = TestPointer(1, PointerDeviceKind.mouse);
      final middle = tester.getCenter(find.byType(FittedBox).first);
      await tester.sendEventToBinding(
        pointer.down(middle, buttons: kMiddleMouseButton),
      );
      await tester.sendEventToBinding(
        pointer.move(middle + const Offset(-40, 25)),
      );
      await tester.pump();
      await tester.sendEventToBinding(pointer.up());
      await tester.pump();

      expect(scope.uiMode.pan.value, const Offset(-40, 25));
      expect(
        tester.getTopLeft(find.byType(FittedBox).first),
        was + const Offset(-40, 25),
      );

      // And fitting it again puts the view back in the middle.
      scope.uiMode.zoomToFit();
      await tester.pump();
      expect(scope.uiMode.pan.value, Offset.zero);
    });

    testWidgets('a widget can be dragged in the tree; a HUD cannot', (
      tester,
    ) async {
      final hud = entity('Hud', [TransformComponent(), UiCanvasComponent()]);
      final coins = entity('Coins', [UiSlotComponent()], under: hud);
      await open(tester, onClose: () {});
      // Selecting a row opens whatever it is inside, which is how the
      // widget comes to be on screen at all.
      scope.sceneState.selectEntity(coins);
      await tester.pump();
      expect(find.text('Coins'), findsOneWidget);

      Finder draggableOf(String name) => find.ancestor(
        of: find.text(name),
        matching: find.byType(LongPressDraggable<List<Entity>>),
      );

      expect(draggableOf('Coins'), findsOneWidget);
      // A HUD sits in the world; where it goes is the world tree's
      // business, and there is nowhere in here it could land.
      expect(draggableOf('Hud'), findsNothing);

      // Held, then moved: that is a drag, and it says what it carries.
      final held = await tester.startGesture(
        tester.getCenter(find.text('Coins')),
      );
      await tester.pump(const Duration(milliseconds: 400));
      await held.moveBy(const Offset(0, 12));
      await tester.pump();
      expect(find.text('Coins'), findsNWidgets(2), reason: 'the drag label');
      await held.up();
      await tester.pumpAndSettle();
    });

    testWidgets('it brings its own tree, listing the HUD', (tester) async {
      entity('Platform', [TransformComponent()]);
      entity('Hud', [TransformComponent(), UiCanvasComponent()]);

      await open(tester, onClose: () {});

      expect(find.text('Hud'), findsOneWidget);
      // The world's rows are not its business.
      expect(find.text('Platform'), findsNothing);
    });
  });

  group('dropping in the interface tree', () {
    testWidgets('a HUD row takes a widget however it was hovered first', (
      tester,
    ) async {
      final hud = entity('Hud', [TransformComponent(), UiCanvasComponent()]);
      final coins = entity('Coins', [UiSlotComponent()], under: hud);
      entity('Pause', [TransformComponent(), UiCanvasComponent()]);
      await open(tester, onClose: () {});
      scope.sceneState.selectEntity(coins);
      await tester.pump();

      // Pick the widget up and pass over the *edge* of a row on the way,
      // which is what used to poison the HUD row for the rest of the
      // drag: it refused on the stale zone and never heard another move.
      // Measured before the drag starts: once it has, the label under
      // the pointer carries the same name and the finder is ambiguous.
      final row = tester.getRect(find.text('Coins'));
      final held = await tester.startGesture(row.center);
      await tester.pump(const Duration(milliseconds: 400));
      await held.moveTo(row.centerLeft + const Offset(0, -11));
      await tester.pump();
      await held.moveTo(tester.getCenter(find.text('Pause')));
      await tester.pump();

      // The row under the pointer is the one taking the drop.
      expect(find.text('Coins'), findsNWidgets(2), reason: 'still dragging');

      await held.up();
      await tester.pumpAndSettle();
    });

    test('the edge of a HUD row means into it, not beside it', () {
      final hud = entity('Hud', [TransformComponent(), UiCanvasComponent()]);
      final coins = entity('Coins', [UiSlotComponent()], under: hud);
      final pause = entity('Pause', [
        TransformComponent(),
        UiCanvasComponent(),
      ]);

      // What the panel does with a drop on the top edge of "Pause": into
      // it, because beside a HUD is out of every screen there is.
      scope.entities.reparentAll([coins], pause);

      expect(coins.getComponent<ParentComponent>()!.parentId, pause.id);
      expect(namesIn(treeOf(TreeContents.ui, expanded: {hud.id, pause.id})), [
        'Hud',
        'Pause',
        'Coins',
      ]);
    });
  });
}

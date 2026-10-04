// Using the scene tree: clicking, renaming, walking it with the keyboard,
// and following the selection wherever it was made.

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart' show kSecondaryButton;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_game_engine_editor/just_game_engine_editor.dart';

import 'support/test_scope.dart';

void main() {
  late EditorScope scope;
  late EntityOps ops;
  late SceneTreeController controller;
  final focused = <String?>[];

  setUp(() {
    focused.clear();
    scope = testScope();
    ops = EntityOps(
      scope: scope,
      world: () => scope.world,
      sceneState: scope.sceneState,
      camera: () => GameCameraEditorView.of(Camera()),
    );
    controller = SceneTreeController(world: () => scope.world);
    addTearDown(controller.dispose);
    scope.sceneState.openScene(EditorScene(name: 'level_test'));
  });

  Entity node(String name, {Entity? under}) {
    final entity = scope.world.createEntityWithComponents([
      TransformComponent(),
      ChildrenComponent(),
    ], name: name);
    scope.sceneState.registerEntity(entity);
    if (under != null) ops.reparentEntity(entity, under);
    return entity;
  }

  Future<void> pumpTree(WidgetTester tester) async {
    tester.view.physicalSize = const Size(300, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SceneTreePanel(
            scope: scope,
            entities: ops,
            controller: controller,
            onFocusEntity: (e) => focused.add(e.name),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  String? selected() => scope.sceneState.selectedEntity.value?.name;

  /// Clicks [finder] at a given moment.
  ///
  /// Synthetic pointer events all carry a timestamp of zero unless one is
  /// given, and the tree reads two clicks close together as a double
  /// click — so a test that wants two separate clicks has to say when
  /// each one happened.
  Future<void> clickAt(
    WidgetTester tester,
    Finder finder, {
    Duration at = Duration.zero,
  }) async {
    final centre = tester.getCenter(finder);
    final gesture = await tester.createGesture();
    await gesture.down(centre, timeStamp: at);
    await gesture.up(timeStamp: at);
    await tester.pump();
  }

  group('selecting', () {
    testWidgets('one click selects, with no wait for a second', (tester) async {
      node('A');
      node('B');
      await pumpTree(tester);

      await tester.tap(find.text('B'));
      await tester.pump();

      // No `pump(400ms)` for a double-tap window: the row has no
      // double-tap recogniser competing with its tap any more.
      expect(selected(), 'B');
    });

    testWidgets('double-clicking asks the viewport to focus it', (
      tester,
    ) async {
      node('A');
      await pumpTree(tester);

      await clickAt(tester, find.text('A'));
      await clickAt(
        tester,
        find.text('A'),
        at: const Duration(milliseconds: 120),
      );
      await tester.pump(const Duration(milliseconds: 600));

      expect(focused, ['A']);
      // And the rename the first click was about to start is taken back.
      expect(controller.renaming.value, isNull);
    });

    testWidgets('control adds to the selection', (tester) async {
      node('A');
      node('B');
      await pumpTree(tester);
      await tester.tap(find.text('A'));
      await tester.pump();

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.tap(find.text('B'));
      await tester.pump();
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);

      expect(scope.sceneState.multiSelectedIds.value, hasLength(2));
    });
  });

  group('opening and shutting', () {
    testWidgets('the chevron opens a row', (tester) async {
      final root = node('Root');
      node('Child', under: root);
      await pumpTree(tester);
      expect(find.text('Child'), findsNothing);

      await tester.tap(find.byIcon(Icons.chevron_right_rounded));
      await tester.pump();

      expect(find.text('Child'), findsOneWidget);
      expect(controller.isExpanded(root.id), isTrue);
    });

    testWidgets('a selection made elsewhere is revealed', (tester) async {
      final root = node('Root');
      final middle = node('Middle', under: root);
      final deep = node('Deep', under: middle);
      await pumpTree(tester);
      expect(find.text('Deep'), findsNothing);

      // What the viewport, the UI mode or the Problems dock does.
      scope.sceneState.selectEntity(deep);
      await tester.pump();

      expect(find.text('Deep'), findsOneWidget);
      expect(controller.isExpanded(root.id), isTrue);
      expect(controller.isExpanded(middle.id), isTrue);
    });

    testWidgets('what was open is remembered by name', (tester) async {
      final root = node('Root');
      node('Child', under: root);
      await pumpTree(tester);
      controller.expand(root.id);
      await tester.pump();

      final saved = controller.toEditorData();
      controller.collapseAll();
      expect(controller.isExpanded(root.id), isFalse);

      controller.restoreEditorData(saved);

      expect(controller.isExpanded(root.id), isTrue);
      expect(saved['expanded'], ['Root']);
    });
  });

  group('renaming', () {
    testWidgets('clicking a row that is already selected opens the box', (
      tester,
    ) async {
      final a = node('A');
      await pumpTree(tester);
      await clickAt(tester, find.text('A'));

      // One click on a selected row means rename — after the moment it
      // takes to be sure no second click is coming, which would mean
      // focus instead.
      await clickAt(
        tester,
        find.text('A'),
        at: const Duration(milliseconds: 900),
      );
      expect(controller.renaming.value, isNull, reason: 'waiting to be sure');
      await tester.pump(const Duration(milliseconds: 600));

      expect(find.byType(TextField), findsNWidgets(2), reason: 'search + row');
      expect(controller.renaming.value, a.id);
    });

    testWidgets('a new name is taken, and is one undo step', (tester) async {
      final a = node('A');
      await pumpTree(tester);
      scope.sceneState.selectEntity(a);
      controller.renaming.value = a.id;
      await tester.pump();

      final box = find.byType(TextField).last;
      await tester.enterText(box, 'Ledge');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();

      expect(a.name, 'Ledge');
      expect(controller.renaming.value, isNull);
      scope.history.undo();
      expect(a.name, 'A');
    });

    testWidgets('a name something else has is refused, and says so', (
      tester,
    ) async {
      final a = node('A');
      node('B');
      await pumpTree(tester);
      scope.sceneState.selectEntity(a);
      controller.renaming.value = a.id;
      await tester.pump();

      await tester.enterText(find.byType(TextField).last, 'B');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();

      expect(a.name, 'A');
      // Still open, and saying why — a rename silently dropped is one the
      // author believes they made. The box is exactly a row tall, so the
      // reason is in its tooltip and its colour rather than a line of
      // text that would cover the rows beneath.
      expect(controller.renaming.value, a.id);
      expect(controller.renameError.value, contains('already called that'));
      expect(
        tester
            .widget<Tooltip>(
              find.ancestor(
                of: find.byType(TextField).last,
                matching: find.byType(Tooltip),
              ),
            )
            .message,
        contains('already called that'),
      );
    });

    testWidgets('clicking another row takes the name being typed', (
      tester,
    ) async {
      final a = node('A');
      node('B');
      await pumpTree(tester);
      scope.sceneState.selectEntity(a);
      controller.renaming.value = a.id;
      await tester.pump();
      await tester.enterText(find.byType(TextField).last, 'Ledge');

      // Somewhere else entirely — a box left open behind a click is a
      // rename the author believes they finished.
      await clickAt(
        tester,
        find.text('B'),
        at: const Duration(milliseconds: 1500),
      );

      expect(a.name, 'Ledge');
      expect(controller.renaming.value, isNull);
      expect(selected(), 'B');
    });

    testWidgets('Escape throws the typing away', (tester) async {
      final a = node('A');
      await pumpTree(tester);
      scope.sceneState.selectEntity(a);
      controller.renaming.value = a.id;
      await tester.pump();
      await tester.enterText(find.byType(TextField).last, 'Ledge');

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();

      expect(a.name, 'A');
      expect(controller.renaming.value, isNull);
    });
  });

  testWidgets('the right button neither selects nor renames', (tester) async {
    final a = node('A');
    await pumpTree(tester);
    await clickAt(tester, find.text('A'));
    expect(selected(), 'A');

    // A right click belongs to the context menu; on its way past it
    // used to open the rename box.
    final centre = tester.getCenter(find.text('A'));
    final gesture = await tester.createGesture(buttons: kSecondaryButton);
    const at = Duration(milliseconds: 2000);
    await gesture.down(centre, timeStamp: at);
    await gesture.up(timeStamp: at);
    await tester.pump();

    expect(controller.renaming.value, isNull);
    expect(selected(), 'A', reason: 'still just selected');
    expect(a.name, 'A');
  });

  group('empty space', () {
    testWidgets('clicking below the rows selects nothing', (tester) async {
      node('A');
      await pumpTree(tester);
      await clickAt(tester, find.text('A'));
      expect(selected(), 'A');

      // Well below the last row.
      final gesture = await tester.createGesture();
      const at = Duration(milliseconds: 2000);
      await gesture.down(const Offset(150, 500), timeStamp: at);
      await gesture.up(timeStamp: at);
      await tester.pump();

      expect(selected(), isNull);
      expect(scope.sceneState.multiSelectedIds.value, isEmpty);
    });
  });

  group('the keyboard', () {
    Future<void> press(WidgetTester tester, LogicalKeyboardKey key) async {
      await tester.sendKeyEvent(key);
      await tester.pump();
    }

    testWidgets('arrows walk the rows', (tester) async {
      node('A');
      node('B');
      node('C');
      await pumpTree(tester);
      await tester.tap(find.text('A'));
      await tester.pump();

      await press(tester, LogicalKeyboardKey.arrowDown);
      expect(selected(), 'B');
      await press(tester, LogicalKeyboardKey.arrowDown);
      expect(selected(), 'C');
      await press(tester, LogicalKeyboardKey.arrowUp);
      expect(selected(), 'B');
    });

    testWidgets('right opens a row, left shuts it and then goes up', (
      tester,
    ) async {
      final root = node('Root');
      node('Child', under: root);
      await pumpTree(tester);
      await tester.tap(find.text('Root'));
      await tester.pump();

      await press(tester, LogicalKeyboardKey.arrowRight);
      expect(controller.isExpanded(root.id), isTrue);
      await press(tester, LogicalKeyboardKey.arrowRight);
      expect(selected(), 'Child', reason: 'into the first child');

      await press(tester, LogicalKeyboardKey.arrowLeft);
      expect(selected(), 'Root', reason: 'back up to the parent');
      await press(tester, LogicalKeyboardKey.arrowLeft);
      expect(controller.isExpanded(root.id), isFalse);
    });

    testWidgets('F2 renames and Delete deletes', (tester) async {
      final a = node('A');
      await pumpTree(tester);
      await tester.tap(find.text('A'));
      await tester.pump();

      await press(tester, LogicalKeyboardKey.f2);
      expect(controller.renaming.value, a.id);
      controller.renaming.value = null;
      await tester.pump();

      await press(tester, LogicalKeyboardKey.delete);
      expect(scope.world.findEntityByName('A'), isNull);
      scope.history.undo();
      expect(scope.world.findEntityByName('A'), isNotNull);
    });

    testWidgets('Alt and an arrow move a row among its siblings', (
      tester,
    ) async {
      final root = node('Root');
      final a = node('A', under: root);
      final b = node('B', under: root);
      controller.expand(root.id);
      await pumpTree(tester);
      await tester.tap(find.text('B'));
      await tester.pump();

      await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
      await press(tester, LogicalKeyboardKey.arrowUp);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);

      expect(root.getComponent<ChildrenComponent>()!.childIds, [b.id, a.id]);
    });

    testWidgets('a letter jumps to the next row starting with it', (
      tester,
    ) async {
      node('Apple');
      node('Ledge');
      node('Marker');
      await pumpTree(tester);
      await tester.tap(find.text('Apple'));
      await tester.pump();

      await press(tester, LogicalKeyboardKey.keyM);

      expect(selected(), 'Marker');
    });
  });

  testWidgets('the runtime section is kept apart while playing', (
    tester,
  ) async {
    final authored = node('Platform');
    node('Bullet');

    tester.view.physicalSize = const Size(300, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SceneTreePanel(
            scope: scope,
            entities: ops,
            controller: controller,
            authored: {authored.id},
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Platform'), findsOneWidget);
    expect(find.text('Bullet'), findsOneWidget);
    // Drawn as the game's, not the scene's.
    final bullet = tester.widget<Text>(find.text('Bullet'));
    expect(bullet.style?.fontStyle, FontStyle.italic);
  });

  group('isolate', () {
    testWidgets('hides everything but the row and what is under it', (
      tester,
    ) async {
      final keep = node('Keep');
      node('Child', under: keep);
      final other = node('Other');
      await pumpTree(tester);

      final centre = tester.getCenter(find.text('Keep'));
      final gesture = await tester.createGesture(buttons: kSecondaryButton);
      const at = Duration(milliseconds: 2000);
      await gesture.down(centre, timeStamp: at);
      await gesture.up(timeStamp: at);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Isolate: hide everything else'));
      await tester.pumpAndSettle();

      // The row, and what is under it, are what is left showing.
      expect(scope.view.isHidden(other.id), isTrue);
      expect(scope.view.isHidden(keep.id), isFalse);
      expect(
        scope.view.isHidden(scope.world.findEntityByName('Child')!.id),
        isFalse,
      );

      // And with something hidden, the menu offers the way back.
      final again = await tester.createGesture(buttons: kSecondaryButton);
      await again.down(centre, timeStamp: at);
      await again.up(timeStamp: at);
      await tester.pumpAndSettle();
      expect(find.text('Isolate: hide everything else'), findsNothing);

      await tester.tap(find.text('Show everything again'));
      await tester.pumpAndSettle();

      expect(scope.view.hidden.value, isEmpty);
    });
  });

  group('icons, colours and the filter bar', () {
    testWidgets('a module says what its own entities look like', (
      tester,
    ) async {
      node('Coin');
      await pumpTree(tester);

      // Nothing claims it, so it gets the editor's generic box.
      expect(find.byIcon(Icons.category_rounded), findsWidgets);
      expect(find.byIcon(Icons.monetization_on_outlined), findsNothing);

      scope.modules.register(_CoinModule());
      scope.reload();
      await tester.pumpWidget(const SizedBox());
      await pumpTree(tester);

      expect(find.byIcon(Icons.monetization_on_outlined), findsOneWidget);
    });

    testWidgets('a row can be marked with a colour, and unmarked', (
      tester,
    ) async {
      final a = node('A');
      await pumpTree(tester);

      final centre = tester.getCenter(find.text('A'));
      final gesture = await tester.createGesture(buttons: kSecondaryButton);
      const at = Duration(milliseconds: 2000);
      await gesture.down(centre, timeStamp: at);
      await gesture.up(timeStamp: at);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Mark with a colour…'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Teal'));
      await tester.pumpAndSettle();

      expect(controller.colorOf(a.id), SceneTreeController.swatches[4]);

      // It is saved by name, because ids are handed out again next load.
      expect(controller.toEditorData()['colors'], {'A': 4});
      controller.setColor(a.id, null);
      expect(controller.colorOf(a.id), isNull);
    });

    testWidgets('a chip is offered only when the scene can answer it', (
      tester,
    ) async {
      node('Platform');
      await pumpTree(tester);

      // Every scene has components; this one has no tags and no layers,
      // and a chip that opens an empty menu is a row saying nothing.
      expect(find.text('Component'), findsOneWidget);
      expect(find.text('Tag'), findsNothing);
      expect(find.text('Layer'), findsNothing);

      final tagged = scope.world.createEntityWithComponents([
        TransformComponent(),
        ChildrenComponent(),
        TagComponent('coin'),
      ], name: 'Coin');
      scope.sceneState.registerEntity(tagged);
      scope.sceneState.refresh();
      await tester.pump();

      expect(find.text('Tag'), findsOneWidget);
    });

    testWidgets('the chips narrow the tree to one kind of entity', (
      tester,
    ) async {
      node('Platform');
      final coin = scope.world.createEntityWithComponents([
        TransformComponent(),
        ChildrenComponent(),
        TagComponent('coin'),
      ], name: 'Coin');
      scope.sceneState.registerEntity(coin);
      await pumpTree(tester);

      expect(find.text('Platform'), findsOneWidget);

      await tester.tap(find.text('Tag'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('coin'));
      await tester.pumpAndSettle();

      // The chip says what it is filtering by, and the tree shows it.
      expect(find.text('Coin'), findsWidgets);
      expect(find.text('Platform'), findsNothing);

      await tester.tap(find.text('Clear'));
      await tester.pumpAndSettle();
      expect(find.text('Platform'), findsOneWidget);
    });
  });
  group('what the panel tells you', () {
    testWidgets('the header counts the scene, and the selection', (
      tester,
    ) async {
      final a = node('A');
      final b = node('B');
      node('C');
      await pumpTree(tester);

      expect(find.text('3 entities'), findsOneWidget);

      scope.sceneState
        ..toggleMultiSelect(a)
        ..toggleMultiSelect(b);
      await tester.pump();
      expect(find.text('2 selected'), findsOneWidget);
    });

    testWidgets('the chips say how much there is to pick from', (tester) async {
      final tagged = scope.world.createEntityWithComponents([
        TransformComponent(),
        ChildrenComponent(),
        TagComponent('coin'),
      ], name: 'Coin');
      scope.sceneState.registerEntity(tagged);
      await pumpTree(tester);

      // One tag in the scene, so the chip says 1 before it is opened.
      expect(
        find.descendant(of: find.text('Tag'), matching: find.text('1')),
        findsNothing,
      );
      expect(find.text('Tag'), findsOneWidget);
      expect(find.text('1'), findsWidgets);
    });

    testWidgets('the list has a scrollbar', (tester) async {
      for (var i = 0; i < 40; i++) {
        node('Entity_$i');
      }
      await pumpTree(tester);

      expect(find.byType(Scrollbar), findsOneWidget);
    });

    testWidgets('the selected row offers the colour swatch', (tester) async {
      final a = node('A');
      node('B');
      await pumpTree(tester);

      scope.sceneState.selectEntity(a);
      await tester.pump();

      await tester.tap(
        find
            .descendant(
              of: find.ancestor(
                of: find.text('A'),
                matching: find.byType(SceneTreeRowTile),
              ),
              matching: find.byTooltip('Mark with a colour'),
            )
            .first,
      );
      await tester.pumpAndSettle();

      // Each swatch is drawn in the colour it stands for; they were all
      // the menu's own grey, which made the list unreadable.
      final swatches = tester
          .widgetList<Icon>(find.byIcon(Icons.square_rounded))
          .toList();
      expect(swatches.length, SceneTreeController.swatches.length);
      expect(swatches.first.color, SceneTreeController.swatches.first);
      expect(swatches[3].color, SceneTreeController.swatches[3]);

      await tester.tap(find.text('Green'));
      await tester.pumpAndSettle();

      expect(controller.colorOf(a.id), SceneTreeController.swatches[3]);
    });
  });
  group('the row as redesigned', () {
    testWidgets('name, then the tick, the mark, the padlock and the menu', (
      tester,
    ) async {
      final a = node('A');
      await pumpTree(tester);

      // The tick is always there, in a column of its own at the far
      // left. (The eye and the padlock need the view state this harness
      // does not pass; they are checked in editor_view_state_test.)
      expect(find.byIcon(Icons.check_box_rounded), findsOneWidget);

      // Left of everything, including the row's indent: the ticks line
      // up whatever the depth, so the column can be read down.
      final tick = tester.getRect(find.byIcon(Icons.check_box_rounded));
      expect(tick.left, lessThan(tester.getRect(find.text('A')).left));

      // The tick is the saved flag, and it undoes.
      await tester.tap(find.byIcon(Icons.check_box_rounded));
      await tester.pump();
      expect(a.isActive, isFalse);
      expect(find.byIcon(Icons.check_box_outline_blank_rounded), findsWidgets);
      scope.history.undo();
      await tester.pump();
      expect(a.isActive, isTrue);
    });

    testWidgets('a control does not pick the row it sits on', (tester) async {
      final a = node('A');
      final b = node('B');
      await pumpTree(tester);
      scope.sceneState.selectEntity(b);
      await tester.pump();

      // The tick belongs to the tick. Pressing it used to select the
      // row on the way past, because the row's listener sits above the
      // controls and hears the same press.
      await tester.tap(
        find.descendant(
          of: find.ancestor(
            of: find.text('A'),
            matching: find.byType(SceneTreeRowTile),
          ),
          matching: find.byIcon(Icons.check_box_rounded),
        ),
      );
      await tester.pump();

      expect(a.isActive, isFalse, reason: 'the tick did its own job');
      expect(
        scope.sceneState.selectedEntity.value?.id,
        b.id,
        reason: 'and left the selection alone',
      );
    });

    testWidgets('the menu button opens the row menu', (tester) async {
      node('A');
      await pumpTree(tester);
      scope.sceneState.selectEntity(scope.world.findEntityByName('A')!);
      await tester.pump();

      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();

      // The same menu the right button opens.
      expect(find.text('Rename'), findsOneWidget);
      expect(find.text('Mark with a colour…'), findsOneWidget);
    });
  });
}

/// A module that knows what a coin looks like — what the kit does for a
/// platformer, in miniature.
class _CoinModule extends EditorModule {
  @override
  String get id => 'coins';

  @override
  String get name => 'Coins';

  @override
  IconData get icon => Icons.monetization_on_outlined;

  @override
  List<EntityIcon> get entityIcons => [
    EntityIcon(
      id: 'coins.icon',
      of: (entity) =>
          entity.name == 'Coin' ? Icons.monetization_on_outlined : null,
    ),
  ];
}

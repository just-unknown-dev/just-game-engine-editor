// The scene tree's keys and its slow-second-click rename: Home, End and the
// arrows land on the nearest row that can be selected the way the key
// goes; a rename armed by a click on the selected row is for that row
// only; and renaming from the tree takes inline timelines bound to the old
// name along, as renaming in the inspector does.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_editor_core/host.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_game_engine_editor/src/entities/entity_ops.dart';
import 'package:just_game_engine_editor/src/entities/scope_entities.dart';
import 'package:just_game_engine_editor/src/scene_tree/scene_tree_controller.dart';
import 'package:just_game_engine_editor/src/scene_tree/scene_tree_panel.dart';

import '../support/test_scope.dart';

void main() {
  late EditorScope scope;
  late EntityOps ops;
  late SceneTreeController controller;

  setUp(() {
    scope = testScope();
    ops = scope.entities;
    controller = SceneTreeController(world: () => scope.world);
    addTearDown(controller.dispose);
    scope.sceneState.openScene(EditorScene(name: 'level'));
  });

  Entity node(String name) {
    final e = scope.world.createEntityWithComponents([
      TransformComponent(),
    ], name: name);
    scope.sceneState.registerEntity(e);
    return e;
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
            onFocusEntity: (_) {},
          ),
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 1));
  }

  String? selected() => scope.sceneState.selectedEntity.value?.name;

  Future<void> clickAt(WidgetTester tester, String row, Duration at) async {
    final gesture = await tester.createGesture();
    await gesture.down(tester.getCenter(find.text(row)), timeStamp: at);
    await gesture.up(timeStamp: at);
    await tester.pump();
  }

  group('Home, End and the arrows', () {
    late Entity alpha, bravo, charlie;

    setUp(() {
      alpha = node('Alpha');
      bravo = node('Bravo');
      charlie = node('Charlie');
    });

    Future<void> key(WidgetTester tester, LogicalKeyboardKey k) async {
      await tester.sendKeyEvent(k);
      await tester.pump();
    }

    Future<void> focusTree(WidgetTester tester, Entity on) async {
      await clickAt(tester, on.name!, Duration.zero);
      await tester.pump(const Duration(seconds: 1));
    }

    testWidgets('End, the last row out of reach, lands on the last that is '
        'not', (tester) async {
      await pumpTree(tester);
      await focusTree(tester, alpha);
      scope.sceneState.selectable.value = (e) => e.name != 'Charlie';
      await tester.pump();
      await key(tester, LogicalKeyboardKey.end);
      expect(selected(), 'Bravo');
    });

    testWidgets('Home, the first row out of reach, lands on the first that '
        'is not', (tester) async {
      await pumpTree(tester);
      await focusTree(tester, charlie);
      scope.sceneState.selectable.value = (e) => e.name != 'Alpha';
      await tester.pump();
      await key(tester, LogicalKeyboardKey.home);
      expect(selected(), 'Bravo');
    });

    testWidgets('↑ with nothing selected starts from the bottom, past what '
        'is out of reach', (tester) async {
      await pumpTree(tester);
      await focusTree(tester, alpha);
      scope.sceneState.selectable.value = (e) => e.name != 'Charlie';
      scope.sceneState.clearSelection();
      await tester.pump();
      await key(tester, LogicalKeyboardKey.arrowUp);
      expect(selected(), 'Bravo');
      expect(bravo.isAlive, isTrue);
    });
  });

  group('a rename armed by a click on the selected row', () {
    testWidgets('is taken back when another row is clicked before it opens', (
      tester,
    ) async {
      final alpha = node('Alpha');
      node('Bravo');
      scope.sceneState.selectEntity(alpha);
      await pumpTree(tester);
      await clickAt(tester, 'Alpha', const Duration(seconds: 10));
      await tester.pump(const Duration(milliseconds: 250));
      await clickAt(tester, 'Bravo', const Duration(seconds: 11));
      await tester.pump(const Duration(milliseconds: 600));
      expect(selected(), 'Bravo');
      expect(
        controller.renaming.value,
        isNull,
        reason: 'no box opens on a row that is not selected',
      );
    });

    testWidgets('is taken back when the selection moves elsewhere', (
      tester,
    ) async {
      final alpha = node('Alpha');
      final bravo = node('Bravo');
      scope.sceneState.selectEntity(alpha);
      await pumpTree(tester);
      await clickAt(tester, 'Alpha', const Duration(seconds: 10));
      // The viewport picks something else meanwhile.
      scope.sceneState.selectEntity(bravo);
      await tester.pump(const Duration(milliseconds: 600));
      expect(controller.renaming.value, isNull);
    });

    testWidgets('opens on its own when nothing else happens', (tester) async {
      final alpha = node('Alpha');
      scope.sceneState.selectEntity(alpha);
      await pumpTree(tester);
      await clickAt(tester, 'Alpha', const Duration(seconds: 10));
      await tester.pump(const Duration(milliseconds: 600));
      expect(controller.renaming.value, alpha.id);
    });
  });

  testWidgets(
    'F2 renaming takes the inline timelines bound to the old name along, '
    'as one undo step',
    (tester) async {
      final lift = node('Lift');
      final player = TimelinePlayerComponent(
        inline: TimelineAsset(
          duration: 1,
          tracks: [
            PropertyTrack(
              component: 'TransformComponent',
              field: 'position',
              channel: 'x',
              binding: const TrackBinding.name('Lift'),
            ),
          ],
        ),
      );
      final director = scope.world.createEntityWithComponents([
        TransformComponent(),
        player,
      ], name: 'Director');
      scope.sceneState.registerEntity(director);
      scope.sceneState.selectEntity(lift);
      await pumpTree(tester);
      await tester.tap(find.text('Lift'));
      await tester.pump(const Duration(seconds: 1));
      await tester.sendKeyEvent(LogicalKeyboardKey.f2);
      await tester.pump();
      // The row's box, not the search field above the rows.
      expect(controller.renaming.value, lift.id, reason: 'F2 opened it');
      await tester.enterText(
        find.descendant(
          of: find.byType(EntityRenameBox),
          matching: find.byType(TextField),
        ),
        'Elevator',
      );
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(lift.name, 'Elevator');
      expect(
        player.inline!.tracks.single.binding.value,
        'Elevator',
        reason: 'the track still moves it',
      );
      scope.history.undo();
      expect(lift.name, 'Lift');
      expect(player.inline!.tracks.single.binding.value, 'Lift');
    },
  );
}

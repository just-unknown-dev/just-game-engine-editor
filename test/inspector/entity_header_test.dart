// The inspector header renames through the entity operations, so inline
// timelines' tracks bound to the old name follow it in the same undo step,
// as from the scene tree — and are rebound once, not twice.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_game_engine_editor/just_game_engine_editor.dart';
import 'package:just_game_engine_editor/src/inspector/entity_header.dart';

import '../support/test_scope.dart';

void main() {
  testWidgets('a rename in the header takes the inline timelines bound to '
      'the old name along, as one undo step', (tester) async {
    final scope = testScope();
    scope.sceneState.openScene(EditorScene(name: 'level'));
    final hero = scope.world.createEntityWithComponents([
      TransformComponent(),
    ], name: 'Hero');
    final player = TimelinePlayerComponent(
      inline: TimelineAsset(
        duration: 1,
        tracks: [
          PropertyTrack(
            component: 'TransformComponent',
            field: 'position',
            channel: 'x',
            binding: const TrackBinding.name('Hero'),
          ),
        ],
      ),
    );
    final director = scope.world.createEntityWithComponents([
      TransformComponent(),
      player,
    ], name: 'Director');
    for (final e in [hero, director]) {
      scope.sceneState.registerEntity(e);
    }
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 360,
              child: EntityHeader(
                entity: hero,
                scope: scope,
                sceneState: scope.sceneState,
              ),
            ),
          ),
        ),
      ),
    );

    // A double-click on the name opens the box.
    await tester.tap(find.text('Hero'));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(find.text('Hero'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(EntityRenameBox), 'Heroine');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(hero.name, 'Heroine');
    expect(
      player.inline!.tracks.single.binding,
      const TrackBinding.name('Heroine'),
      reason: 'the track still moves it',
    );
    expect(scope.history.undoDepth, 1, reason: 'one step');

    scope.history.undo();
    expect(hero.name, 'Hero');
    expect(
      player.inline!.tracks.single.binding,
      const TrackBinding.name('Hero'),
    );
    scope.history.redo();
    expect(player.inline!.tracks.single.binding.value, 'Heroine');
  });
}

// The authoring grid is an editing aid, not part of the game, so it must not
// be painted over a running play-test.

import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_game_engine_editor/just_game_engine_editor.dart';

void main() {
  // play() is gated on both the engine and the plugin being initialised, and
  // attach registers a hardware-keyboard handler — so this needs a
  // binding even though none of these are widget tests.
  TestWidgetsFlutterBinding.ensureInitialized();

  late JustGameEditorPlugin plugin;

  setUp(() async {
    final engine = Engine();
    addTearDown(engine.dispose);
    await engine.initialize();

    plugin = JustGameEditorPlugin(engine: engine);
    await plugin.attach(plugin.engine);
    plugin
      ..setVisible(true)
      ..applyOverlaySettings(
        showGrid: true,
        gridSnappingEnabled: true,
        gridSize: 32,
      );
  });

  tearDown(() {
    plugin.dispose();
  });

  test('the grid is drawn while authoring', () {
    expect(plugin.playState, EditorPlayState.stopped);
    expect(plugin.isGridVisible.value, isTrue);
  });

  test('the grid is hidden while playing', () {
    plugin.play();

    expect(plugin.playState, EditorPlayState.playing);
    expect(plugin.isGridVisible.value, isFalse);
  });

  test('the grid stays hidden while paused', () {
    plugin
      ..play()
      ..pause();

    expect(plugin.playState, EditorPlayState.paused);
    expect(
      plugin.isGridVisible.value,
      isFalse,
      reason: 'pausing is still a play session; the grid should not blink back',
    );
  });

  test('the grid comes back on stop', () {
    plugin
      ..play()
      ..stop();

    expect(plugin.playState, EditorPlayState.stopped);
    expect(plugin.isGridVisible.value, isTrue);
  });

  test('turning the grid off in settings still wins while authoring', () {
    plugin.applyOverlaySettings(
      showGrid: false,
      gridSnappingEnabled: true,
      gridSize: 32,
    );

    expect(plugin.isGridVisible.value, isFalse);
  });

  test('the grid is hidden when the editor itself is closed', () {
    plugin.setVisible(false);

    expect(plugin.isGridVisible.value, isFalse);
  });
}

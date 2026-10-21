// While a workspace is open over the level, the level is drawn only every
// JustGameEditorPlugin.drawIntervalUnderWorkspace — the game keeps
// running — and drawn as the game asks again once it closes.

import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_game_engine_editor/just_game_engine_editor.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Engine engine;
  late JustGameEditorPlugin plugin;

  setUp(() async {
    engine = Engine();
    addTearDown(engine.dispose);
    await engine.initialize();
    plugin = JustGameEditorPlugin(engine: engine, startVisible: false);
    await plugin.attach(plugin.engine);
  });

  test('a workspace over the level spares its drawing; closing it gives '
      "the game's own back", () {
    const own = Duration(milliseconds: 40);
    engine.rendering.drawInterval = own;

    expect(plugin.scope.openInWorkspace('assets/data/notes.json'), isTrue);
    expect(
      engine.rendering.drawInterval,
      JustGameEditorPlugin.drawIntervalUnderWorkspace,
    );

    // Another opened in its place holds it as the first did.
    expect(plugin.scope.openInWorkspace('assets/data/more.json'), isTrue);
    expect(
      engine.rendering.drawInterval,
      JustGameEditorPlugin.drawIntervalUnderWorkspace,
    );

    plugin.scope.closeWorkspace();
    expect(engine.rendering.drawInterval, own);
    plugin.dispose();
  });

  test('the editor going away with a workspace open gives it back too', () {
    expect(engine.rendering.drawInterval, isNull);
    plugin.scope.openInWorkspace('assets/data/notes.json');
    expect(engine.rendering.drawInterval, isNotNull);
    plugin.dispose();
    expect(engine.rendering.drawInterval, isNull);
  });
}

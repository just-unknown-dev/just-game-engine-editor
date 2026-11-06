// The editor's own docks: what they share is the editor's, kept in its
// scope and let go with it.

import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart' show Engine;
import 'package:just_game_engine_editor/just_game_engine_editor.dart';
import 'package:just_game_engine_editor/src/plugin/built_in_docks.dart';

void main() {
  test("the History dock's undo notifier is the editor's, disposed with "
      'it', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final engine = Engine();
    await engine.initialize();
    addTearDown(engine.dispose);
    final plugin = JustGameEditorPlugin(engine: engine);
    await plugin.attach(plugin.engine);
    final history = BuiltInDocks.historyOf(plugin);
    expect(history.value, same(plugin.history));
    expect(BuiltInDocks.historyOf(plugin), same(history), reason: 'one');

    plugin.dispose();
    expect(
      () => history.addListener(() {}),
      throwsFlutterError,
      reason: 'disposed with the editor',
    );
  });
}

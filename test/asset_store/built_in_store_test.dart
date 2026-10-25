// The Asset Store is one of the editor's own modules: every game's editor
// has it, 2-D or 3-D, with nothing to add to the modules list.
import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/graphics_3d.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_game_engine_editor/asset_store.dart';
import 'package:just_game_engine_editor/just_game_engine_editor.dart';
import 'package:just_game_engine_editor/src/ui/overlay/shared/transform_toolbar.dart'
    show ToolColumnButtons;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('the editor brings it to every game, 2-D and 3-D', () {
    final flat = Engine();
    final deep = Engine(config: EngineConfig(graphics3D: Graphics3D()));
    for (final engine in [flat, deep]) {
      expect(
        JustGameEditorPlugin.builtInsFor(engine),
        contains(BuiltInAssetStoreModule.make),
      );
    }
  });

  test('a scope made with the built-ins has it, as a built-in', () {
    final scope = EditorScope(
      world: World()..initialize(),
      builtIns: JustGameEditorPlugin.builtInsFor(Engine()),
    );
    addTearDown(scope.dispose);
    final store = scope.modules.byId(BuiltInAssetStoreModule.moduleId);
    expect(store, isA<BuiltInAssetStoreModule>());
    expect(scope.modules.isBuiltIn(store!), isTrue);
    // Not one of the game's modules, so a hot reload's syncModules, which
    // replaces those, keeps it.
    expect(scope.modules.all, isNot(contains(store)));
    expect(
      scope.modules.withBuiltIns.expand((m) => m.keyBindings),
      contains(
        isA<KeyBinding>().having((k) => k.commandId, 'command', 'store.open'),
      ),
    );
    // Its shop button is in the column under the transform tools, as one
    // of the editor's own features, in every game.
    expect([
      for (final b in ToolColumnButtons.buttonsOf(scope)) b.id,
    ], contains('asset_store.open'));
  });
}

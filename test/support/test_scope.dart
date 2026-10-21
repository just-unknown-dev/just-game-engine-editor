import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_game_engine_editor/just_game_engine_editor.dart';

/// An editor scope over a bare world, disposed with the test.
///
/// What a test reaches for instead of the process-wide registries the editor
/// used to have: two tests get two scopes, and nothing leaks between them.
EditorScope testScope({
  World? world,
  List<EditorModule> modules = const [],
  String? scenesRoot,
}) {
  final scope = EditorScope(
    builtIns: const [BuiltInEditorModule.new],
    world: world ?? (World()..initialize()),
    modules: modules,
    scenesRoot: scenesRoot,
  );
  addTearDown(scope.dispose);
  return scope;
}

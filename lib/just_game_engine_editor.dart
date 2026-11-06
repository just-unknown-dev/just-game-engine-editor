/// The level editor for just_game_engine games: it runs inside a debug
/// build of the game, over the running world, and saves the project's
/// scenes on disk (Windows, macOS and Linux).
///
/// A game's editor entry point makes it with [JustGameEditorPlugin.register]
/// — null in a release build, and where the editor cannot run
/// ([JustGameEditorPlugin.supportsPlatform]) — and shows it with
/// [JustGameEngineEditor]:
///
/// ```dart
/// final plugin = await JustGameEditorPlugin.register(
///   engine: engine,
///   modules: [MyGameModule()],
/// );
/// runApp(MaterialApp(
///   home: JustGameEngineEditor(engine: engine, plugin: plugin),
/// ));
/// ```
///
/// What a module builds on — the module contract, the scope, undo, the
/// inspector's rows, the Level Designer's tools — is `just_editor_core`,
/// re-exported here. The editor's own tools come as [BuiltInEditorModule];
/// a module's tests that need them make their scope with
/// `builtIns: const [BuiltInEditorModule.new]`, and drive a
/// [LevelDesignerSession] over it.
///
/// The materials windows and their tools are in `materials.dart`.
library;

export 'package:just_editor_core/just_editor_core.dart';

export 'src/chrome/chrome.dart' show JustGameEngineEditor;
export 'src/level_designer/level_designer.dart'
    show BuiltInPrefabs, ComponentResizer, LevelDesignerSession;
export 'src/level_map/level_map.dart'
    show TiledFiles, TiledImportPlan, TiledImporter;
export 'src/play/play.dart' show EditorPlayState;
export 'src/plugin/plugin.dart' show BuiltInEditorModule, JustGameEditorPlugin;
export 'src/viewport/viewport.dart' show Gizmo2DPainter;

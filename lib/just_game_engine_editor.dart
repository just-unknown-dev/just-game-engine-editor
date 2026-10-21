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

export 'src/core/level_map/tiled_import.dart'
    show TiledFiles, TiledImportPlan, TiledImporter;
export 'src/core/play/play_controller.dart' show EditorPlayState;
export 'src/core/plugin/editor_plugin.dart' show JustGameEditorPlugin;
export 'src/core/view/orbit_fly_editor_view.dart'
    show OrbitFlyEditorView, ViewPose3D;
export 'src/extension/built_in_editor_module.dart' show BuiltInEditorModule;
export 'src/integration/just_game_editor_adapter.dart'
    show JustGameEngineEditor;
export 'src/ui/level_designer/grid/hex_grid.dart' show HexGridModule;
export 'src/ui/level_designer/level_designer_session.dart'
    show LevelDesignerSession;
export 'src/ui/level_designer/state/built_in_prefabs.dart' show BuiltInPrefabs;
export 'src/ui/level_designer/state/component_resizer.dart'
    show ComponentResizer;
export 'src/ui/overlay/gizmo_painter.dart' show GizmoPainter;

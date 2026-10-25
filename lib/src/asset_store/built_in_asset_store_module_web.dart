// The Asset Store where the editor never runs: the web, JavaScript or
// WebAssembly. The store installs packages into a project on disk and runs
// pub, which the web can't do (just_asset_store leaves that part out
// there), so this module adds nothing. It exists so that a game whose debug
// entry point imports the editor still compiles for the web.
import 'package:just_editor_core/just_editor_core.dart';

/// The Asset Store on the web: an empty module of the same name.
class BuiltInAssetStoreModule extends EditorModule {
  /// The store for the project at [root].
  BuiltInAssetStoreModule({this.root, this.cacheDir});

  /// The module for [scope]: how the editor makes its built-ins.
  static EditorModule make(EditorScope scope) => BuiltInAssetStoreModule();

  /// Its id.
  static const String moduleId = 'asset_store';

  /// The store window's id.
  static const String workspaceId = 'asset_store';

  /// The project folder.
  final String? root;

  /// The download cache.
  final String? cacheDir;

  @override
  String get id => moduleId;

  @override
  String get name => 'Asset Store';
}

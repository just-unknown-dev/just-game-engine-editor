/// The Asset Store in the editor: the editor's own module for installing
/// art, sound, editor tools and kits into a project
/// ([BuiltInAssetStoreModule], which `JustGameEditorPlugin` brings itself).
///
/// Its window opens with Ctrl+Shift+G (Cmd+Shift+G on macOS) or from the
/// Assets dock. Installs go through `just_asset_store`, the same code as
/// `just store …`. On the web, where the editor never runs, the module adds
/// nothing.
library;

export 'src/asset_store/asset_store.dart' show BuiltInAssetStoreModule;

/// The Asset Store in the editor: the editor's own module for installing
/// art, sound, editor tools and kits ([BuiltInAssetStoreModule]).
///
/// The store works on a project on disk, so on the web — where the editor
/// never runs — the module is an empty stand-in, and nothing here reaches
/// `dart:io`.
library;

export 'built_in_asset_store_module.dart'
    if (dart.library.js_interop) 'built_in_asset_store_module_web.dart';

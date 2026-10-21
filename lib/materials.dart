/// Materials in the editor, 2-D and 3-D: the editor's own module for them
/// ([BuiltInMaterialsModule], which `JustGameEditorPlugin` brings itself),
/// and the normal map maker ([NormalMaps], over [Pixels]) for tools that
/// make maps from pictures.
///
/// A module adds to the material windows through the workspace
/// contributions of `just_editor_core` (`WorkspaceIds.material`,
/// `WorkspaceIds.material2D`), not by importing this.
library;

export 'src/materials/built_in_materials_module.dart'
    show BuiltInMaterialsModule;
export 'src/materials/image_pixels.dart' show Pixels;
export 'src/materials/normal_maps.dart' show NormalMapOptions, NormalMaps;

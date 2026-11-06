/// Materials in the editor, 2-D and 3-D: the editor's own module for them
/// ([BuiltInMaterialsModule], which `JustGameEditorPlugin` brings itself),
/// and the normal map maker ([NormalMaps], over [ImagePixels]) for tools that
/// make maps from pictures.
///
/// A module adds to the material windows through the workspace
/// contributions of `just_editor_core` (`WorkspaceIds.material3D`,
/// `WorkspaceIds.material2D`), not by importing this.
library;

export 'src/materials/materials.dart'
    show BuiltInMaterialsModule, ImagePixels, NormalMapOptions, NormalMaps;

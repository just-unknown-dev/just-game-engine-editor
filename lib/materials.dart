/// Materials in the editor, 2-D and 3-D: the editor's own module for them
/// ([BuiltInMaterialsModule]), their windows, pictures and tools — the
/// normal map maker ([NormalMaps]), texture sets made into materials
/// ([TextureSets]), a model's materials written out ([ModelMaterials]) —
/// for tools and for modules that build on them.
///
/// A module adds to the material windows through the workspace
/// contributions of `just_editor_core` (`WorkspaceIds.material`,
/// `WorkspaceIds.material2D`), not by importing this.
library;

export 'src/materials/materials.dart';

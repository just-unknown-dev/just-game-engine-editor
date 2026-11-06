/// 3-D graphics in the editor: the editor's own module for models, lights
/// and the environment ([BuiltInGraphics3DModule], which
/// `JustGameEditorPlugin` brings itself for a game with 3-D graphics), and
/// model cooking ([ModelCooking]) and pictures ([ModelThumbnails]) for
/// tools that work on a project's models.
library;

export 'src/graphics/graphics.dart'
    show BuiltInGraphics3DModule, ModelCooking, ModelThumbnails;

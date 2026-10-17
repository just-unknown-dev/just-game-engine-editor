import 'package:just_editor_core/host.dart';

import '../ui/level_designer_3d/shapes/collider_size_handles.dart';
import '../ui/level_designer_3d/shapes/polygon_handles.dart';
import '../ui/level_designer_3d/shapes/shape_size_handles.dart';
import '../ui/level_designer_3d/shapes/shape_pictures.dart';
import '../ui/level_designer_3d/shapes/shape_prefabs.dart';
import '../ui/level_designer_3d/shapes/shape_ray_test.dart';

/// The Level Designer's default kit for 3-D scenes, as the built-in module
/// hands it over: the basic shapes to place, picking them by their
/// triangles, and dragging a polygon's corners. Its tools are the
/// session's own (`LevelDesignerSession`), registered beside the 2-D ones
/// and offered only in a 3-D scene.
abstract final class BuiltIn3DDesignerContributions {
  /// The basic shapes, Cube to Polygon.
  static List<PrefabDefinition> get prefabs => ShapePrefabs.all;

  /// The cube's id: what a 3-D designer has in hand to begin with.
  static const String cubeId = 'shape.cube';

  /// Picks a shape by what is drawn, not its box. One per editor: it keeps
  /// the shapes' triangles.
  static EntityRayTest shapeTest() => ShapeRayTest();

  /// What a selected shape or collider lets the author drag: a polygon's
  /// corners, a shape's faces, a collider's faces.
  static List<ViewportHandles> get viewportHandles => [
    PolygonHandles(),
    ShapeSizeHandles(),
    ColliderSizeHandles(),
  ];

  /// Pictures of any prefab made of a shape, for the palette.
  static List<PrefabPicture> get prefabPictures => [ShapePictures.picture];
}

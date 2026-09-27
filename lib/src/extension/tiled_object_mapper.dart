import 'dart:ui';

import 'package:just_game_engine/just_game_engine.dart';

/// An object from a Tiled map's object layers, as an importer sees it:
/// already placed in the world, with plain values rather than Tiled's
/// model.
class TiledObjectInfo {
  const TiledObjectInfo({
    required this.id,
    required this.name,
    required this.className,
    required this.layerName,
    required this.center,
    required this.size,
    this.rotation = 0,
    this.isPoint = false,
    this.isEllipse = false,
    this.polygon,
    this.polyline,
    this.gid,
    this.properties = const {},
  });

  /// Its id in the Tiled map.
  final int id;
  final String name;

  /// Its class — Tiled's "type" before 1.9.
  final String className;

  /// The object layer it was on, groups included (`Group/Layer`).
  final String layerName;

  /// Its middle, in the world. A point object's point.
  final Offset center;
  final Size size;

  /// Degrees, clockwise, as Tiled keeps it.
  final double rotation;

  final bool isPoint;
  final bool isEllipse;

  /// Corners, relative to [center], for a polygon or polyline object.
  final List<Offset>? polygon;
  final List<Offset>? polyline;

  /// For a tile object: the tile's global id in the Tiled map.
  final int? gid;

  /// Its custom properties, by name.
  final Map<String, Object?> properties;
}

/// Turns objects of a Tiled map into entities when the map is imported: a
/// spawn point, a coin, a moving platform.
///
/// A module lists its mappers in `EditorModule.tiledObjectMappers`. The
/// first (by [order]) whose [matches] says yes makes the entity — so a
/// mapper's objects are entities even when their class names a prefab that
/// is a shape. Objects no mapper takes become the prefab their class names
/// (its id, name or one of its `aliases`): its shape in the level's map
/// when it has one, else the entity it builds. Anything else is a shape of
/// the map, or a plain named entity for a point.
class TiledObjectMapper {
  const TiledObjectMapper({
    required this.id,
    required this.matches,
    required this.build,
    this.order = 100,
  });

  final String id;
  final int order;

  /// Whether this mapper makes [object]: by its class, its name, its layer.
  final bool Function(TiledObjectInfo object) matches;

  /// The components of the entity [object] becomes.
  final List<Component> Function(TiledObjectInfo object) build;
}

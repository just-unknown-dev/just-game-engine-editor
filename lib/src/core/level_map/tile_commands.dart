import 'package:just_game_engine/just_game_engine.dart';

import 'package:just_editor_core/host.dart';
import 'level_map_documents.dart';

/// Which map an undo step belongs to: the entity it is on, and the file it
/// is kept in when it has one.
///
/// Commands name their map rather than hold it. When a play-test stops, or
/// an undo replaces the entity's components, the map object is replaced;
/// the entity id and the file path are what stay the same — and when an
/// undo and redo make the entity again under a new id, its [entityName].
class LevelMapRef {
  const LevelMapRef({required this.entityId, this.path, this.entityName});

  final int entityId;

  /// The `.map.json` the map is kept in, or null when it is in the
  /// scene.
  final String? path;

  /// The map entity's name: how it is found once its id is another's.
  final String? entityName;

  bool get isFile => path != null;

  @override
  bool operator ==(Object other) =>
      other is LevelMapRef &&
      other.entityId == entityId &&
      other.path == path &&
      other.entityName == entityName;

  @override
  int get hashCode => Object.hash(entityId, path, entityName);
}

/// One stroke of a tile tool, recorded as it is painted.
///
/// Tools write through [set] so the map shows each cell as it changes;
/// [finish] turns what changed into one undo step.
class TileStroke {
  TileStroke({required this.docs, required this.ref, required this.layer});

  final LevelMapDocuments docs;
  final LevelMapRef ref;
  final MapLayerData layer;

  final Map<TileCoord, int> _before = {};
  final Map<TileCoord, int> _after = {};

  bool get isEmpty => _after.isEmpty;

  /// The cells this stroke has changed so far.
  Iterable<TileCoord> get cells => _after.keys;

  /// Sets cell [c] to [value]. Returns whether it changed.
  bool set(TileCoord c, int value) {
    final current = layer.cells.cellAt(c.x, c.y);
    if (current == value) return false;
    _before.putIfAbsent(c, () => current);
    layer.cells.setCell(c.x, c.y, value);
    _after[c] = value;
    return true;
  }

  /// Puts back every cell the stroke changed — a cancelled drag.
  void revert() {
    _before.forEach((c, v) => layer.cells.setCell(c.x, c.y, v));
    _before.clear();
    _after.clear();
  }

  /// The stroke as one undo step, already applied; null when it changed
  /// nothing. Marks the map edited.
  TileEditCommand? finish(String label) {
    final changes = <TileCoord, (int, int)>{
      for (final c in _after.keys)
        if (_before[c] != _after[c]) c: (_before[c]!, _after[c]!),
    };
    _before.clear();
    _after.clear();
    if (changes.isEmpty) return null;
    docs.markEdited(ref);
    return TileEditCommand(
      label: label,
      docs: docs,
      ref: ref,
      layerId: layer.id,
      changes: changes,
    );
  }
}

/// Cells of one layer changed: each one's value before and after.
///
/// Never merged with the next one: two strokes are two undo steps, however
/// alike their labels.
class TileEditCommand extends EditorCommand {
  TileEditCommand({
    required this.label,
    required this.docs,
    required this.ref,
    required this.layerId,
    required this.changes,
  });

  @override
  final String label;
  final LevelMapDocuments docs;
  final LevelMapRef ref;
  final int layerId;

  /// Cell → (before, after).
  final Map<TileCoord, (int, int)> changes;

  void _apply(bool after) {
    final layer = docs.dataFor(ref)?.layerById(layerId);
    // The map is gone — another scene, a deleted entity: nothing to do.
    if (layer == null) return;
    changes.forEach(
      (c, v) => layer.cells.setCell(c.x, c.y, after ? v.$2 : v.$1),
    );
    docs.markEdited(ref);
  }

  @override
  void redo() => _apply(true);

  @override
  void undo() => _apply(false);
}

/// A map's settings and layers — everything but the cells, which stay in
/// the layer objects kept here.
///
/// What a structural undo step saves: adding a layer and taking it away
/// again gives back the same layer, cells and all, because the layer object
/// is kept; renaming one or changing its opacity is put back from the
/// settings recorded beside it.
///
/// Captured field by field: going through `toJson` encoded every chunk of
/// every layer — twice for each step — only to throw the cells away, which
/// made a drag of a layer's opacity slider lag on a big map.
class MapStructure {
  MapStructure.capture(LevelMapData map)
    : _settings = _MapSettings.of(map),
      _layers = [...map.layers],
      _meta = [for (final l in map.layers) _LayerSettings.of(l)];

  final _MapSettings _settings;
  final List<MapLayerData> _layers;
  final List<_LayerSettings> _meta;

  /// Puts [map] back to this shape.
  void restoreInto(LevelMapData map) {
    _settings.applyTo(map);
    map.layers
      ..clear()
      ..addAll(_layers);
    for (var i = 0; i < _layers.length; i++) {
      _meta[i].applyTo(_layers[i]);
    }
    map.touch();
  }
}

/// A map's settings, without its layers.
class _MapSettings {
  _MapSettings.of(LevelMapData m)
    : orientation = m.orientation,
      tileWidth = m.tileWidth,
      tileHeight = m.tileHeight,
      staggerAxis = m.staggerAxis,
      staggerIndex = m.staggerIndex,
      hexSideLength = m.hexSideLength,
      renderOrder = m.renderOrder,
      nextLayerId = m.nextLayerId,
      backgroundColor = m.backgroundColor,
      className = m.className,
      properties = m.properties.copy(),
      tilesets = List.of(m.tilesets);

  final MapOrientation orientation;
  final int tileWidth;
  final int tileHeight;
  final TileStaggerAxis staggerAxis;
  final TileStaggerIndex staggerIndex;
  final int hexSideLength;
  final TileRenderOrder renderOrder;
  final int nextLayerId;
  final int? backgroundColor;
  final String className;
  final TileProperties properties;
  final List<String?> tilesets;

  void applyTo(LevelMapData map) {
    map
      ..orientation = orientation
      ..tileWidth = tileWidth
      ..tileHeight = tileHeight
      ..staggerAxis = staggerAxis
      ..staggerIndex = staggerIndex
      ..hexSideLength = hexSideLength
      ..renderOrder = renderOrder
      ..nextLayerId = nextLayerId
      ..backgroundColor = backgroundColor
      ..className = className
      // A copy each time: what is edited after must not change this.
      ..properties = properties.copy();
    map.tilesets
      ..clear()
      ..addAll(tilesets);
  }
}

/// A layer's settings, without its cells.
class _LayerSettings {
  _LayerSettings.of(MapLayerData l)
    : name = l.name,
      visible = l.visible,
      locked = l.locked,
      opacity = l.opacity,
      tint = l.tint,
      offsetX = l.offsetX,
      offsetY = l.offsetY,
      parallaxX = l.parallaxX,
      parallaxY = l.parallaxY,
      sortLayerId = l.sortLayerId,
      sortLayer = l.sortLayer,
      zOrder = l.zOrder,
      collides = l.collides,
      className = l.className,
      properties = l.properties.copy(),
      material = l.material,
      castsShadows = l.castsShadows,
      shadowDepth = l.shadowDepth;

  final String name;
  final bool visible;
  final bool locked;
  final double opacity;
  final int? tint;
  final double offsetX;
  final double offsetY;
  final double parallaxX;
  final double parallaxY;
  final String sortLayerId;
  final int sortLayer;
  final int zOrder;
  final bool collides;
  final String className;
  final TileProperties properties;
  final String material;
  final bool castsShadows;
  final double shadowDepth;

  void applyTo(MapLayerData layer) {
    layer
      ..name = name
      ..visible = visible
      ..locked = locked
      ..opacity = opacity
      ..tint = tint
      ..offsetX = offsetX
      ..offsetY = offsetY
      ..parallaxX = parallaxX
      ..parallaxY = parallaxY
      ..sortLayerId = sortLayerId
      ..sortLayer = sortLayer
      ..zOrder = zOrder
      ..collides = collides
      ..className = className
      ..properties = properties.copy()
      ..material = material
      ..castsShadows = castsShadows
      ..shadowDepth = shadowDepth;
  }
}

/// A change to a map's settings or layers: add, remove, reorder, rename,
/// any layer property, the tileset list.
///
/// Consecutive steps with the same [mergeKey] fold into one — dragging an
/// opacity slider is one undo step, not a hundred.
class MapStructureCommand extends EditorCommand {
  MapStructureCommand({
    required this.label,
    required this.docs,
    required this.ref,
    required this.before,
    required this.after,
    this.mergeKey,
  });

  /// Records [change] made to the map [ref] names: the shape before, the
  /// change, the shape after. Null when the map is not there.
  static MapStructureCommand? record({
    required String label,
    required LevelMapDocuments docs,
    required LevelMapRef ref,
    required void Function(LevelMapData map) change,
    Object? mergeKey,
  }) {
    final map = docs.dataFor(ref);
    if (map == null) return null;
    final before = MapStructure.capture(map);
    change(map);
    map.touch();
    docs.markEdited(ref);
    return MapStructureCommand(
      label: label,
      docs: docs,
      ref: ref,
      before: before,
      after: MapStructure.capture(map),
      mergeKey: mergeKey,
    );
  }

  @override
  final String label;
  final LevelMapDocuments docs;
  final LevelMapRef ref;
  final MapStructure before;
  MapStructure after;
  final Object? mergeKey;

  void _apply(MapStructure shape) {
    final map = docs.dataFor(ref);
    if (map == null) return;
    shape.restoreInto(map);
    docs.markEdited(ref);
  }

  @override
  void redo() => _apply(after);

  @override
  void undo() => _apply(before);

  @override
  bool mergeWith(EditorCommand next) {
    if (mergeKey == null ||
        next is! MapStructureCommand ||
        next.mergeKey != mergeKey ||
        next.ref != ref) {
      return false;
    }
    after = next.after;
    return true;
  }
}

import 'dart:ui';

import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_signals/just_signals.dart';

import '../state/editor_scene_state.dart';
import 'level_map_documents.dart';

/// What the tile fill tool fills.
enum TileFillShape {
  /// The connected run of the same tile under the pointer.
  bucket,

  /// A dragged rectangle.
  rect,

  /// A dragged ellipse.
  ellipse,
}

/// How the tile select tool picks cells.
enum TileSelectMode {
  /// A dragged rectangle.
  rect,

  /// The connected run of the same tile.
  wand,

  /// Every cell with the same tile.
  sameTile,
}

/// The terrain a terrain brush paints: a Wang set's colour, in a tileset.
class TerrainChoice {
  const TerrainChoice({
    required this.slot,
    required this.set,
    required this.color,
  });

  /// The map's slot for the tileset.
  final int slot;

  /// The Wang set, by index in the tileset.
  final int set;

  /// The colour, from 1.
  final int color;

  @override
  bool operator ==(Object other) =>
      other is TerrainChoice &&
      other.slot == slot &&
      other.set == set &&
      other.color == color;

  @override
  int get hashCode => Object.hash(slot, set, color);
}

/// Everything the tile tools share: which map and layer are being painted,
/// what the brush holds, and how the tools are set.
///
/// Lives on the scope, not in a tool — tools are rebuilt on every hot
/// reload and designer switch, and the palette, the layers panel, the
/// status bar and the overlays all read it.
class TileEditState {
  TileEditState({required this.sceneState, required LevelMapDocuments docs})
    : _docs = docs {
    _unwatchScene = sceneState.activeScene.watch(reset);
    _unwatchSelection = sceneState.selectedEntity.watch(_follow);
    // A selection belongs to one layer.
    _unwatchLayer = layerId.watch(() => selection.value = const {});
  }

  late final VoidCallback _unwatchLayer;

  /// Fades every layer of the map being painted but the layer being
  /// painted, while [active] (a tile tool in hand, authoring) and
  /// [highlightLayer] are on; every other map, and every map otherwise,
  /// shows as it is. A view, not an edit: called each frame.
  void syncHighlight(World world, {required bool active}) {
    final on = active && highlightLayer.value;
    // The map the tools would paint — the chosen one, else the level's own —
    // found without choosing it, as the overlays find it.
    final mapId = on ? peek(world)?.entity.id : null;
    for (final entity in world.query([LevelMapComponent])) {
      final runtime = entity.getComponent<LevelMapComponent>()?.runtime;
      if (runtime == null) continue;
      if (!on || entity.id != mapId) {
        if (runtime.layerAlpha.isNotEmpty) runtime.layerAlpha.clear();
        continue;
      }
      for (final layer in runtime.base.layers) {
        if (layer.id == layerId.value) {
          runtime.layerAlpha.remove(layer.id);
        } else {
          runtime.layerAlpha[layer.id] = 0.3;
        }
      }
    }
  }

  final EditorSceneState sceneState;
  final LevelMapDocuments _docs;
  late final VoidCallback _unwatchScene;
  late final VoidCallback _unwatchSelection;

  /// The map being painted, by entity id.
  final Signal<int?> mapEntityId = Signal(null, debugLabel: 'levelMap');

  /// The layer being painted, by id within the map.
  final Signal<int?> layerId = Signal(null, debugLabel: 'tileLayer');

  /// The tileset shown in the palette, by the map's slot.
  final Signal<int> slot = Signal(0, debugLabel: 'tileSlot');

  /// What the stamp and fill tools paint.
  final Signal<TileStamp?> stamp = Signal(null, debugLabel: 'tileStamp');

  /// What the terrain tool paints.
  final Signal<TerrainChoice?> terrain = Signal(
    null,
    debugLabel: 'tileTerrain',
  );

  /// Paint a random one of the stamp's tiles per cell.
  final Signal<bool> random = Signal(false, debugLabel: 'tileRandom');

  /// Fade every layer but the one being painted.
  final Signal<bool> highlightLayer = Signal(
    false,
    debugLabel: 'tileHighlight',
  );

  /// Whether the Tileset panel shows its tilesets' terrains rather than
  /// their tiles. The terrain tool turns it on, the stamp and fill off.
  final Signal<bool> paletteTerrains = Signal(
    false,
    debugLabel: 'tilePaletteTerrains',
  );

  /// How large the Tileset panel draws its tiles.
  final Signal<double> paletteZoom = Signal(1, debugLabel: 'tilePaletteZoom');

  /// The tilesets the Tileset panel shows folded away, by path.
  final Signal<Set<String>> collapsedTilesets = Signal(
    const {},
    debugLabel: 'tileCollapsedTilesets',
  );

  /// Draw the painted tiles' collision over the map.
  final Signal<bool> showCollision = Signal(false, debugLabel: 'mapCollision');

  final Signal<TileFillShape> fillShape = Signal(
    TileFillShape.bucket,
    debugLabel: 'tileFillShape',
  );

  final Signal<TileSelectMode> selectMode = Signal(
    TileSelectMode.rect,
    debugLabel: 'tileSelectMode',
  );

  /// Cells of the active layer picked by the select tool.
  final Signal<Set<TileCoord>> selection = Signal(
    const {},
    debugLabel: 'tileSelection',
  );

  // What the tools are showing — read by the overlays every frame, so plain
  // fields rather than signals.

  /// The cell under the pointer; a signal so the status bar can say which,
  /// changing only when the pointer crosses into another cell.
  final Signal<TileCoord?> hover = Signal(null, debugLabel: 'tileHover');

  TileCoord? get hoverCell => hover.value;
  set hoverCell(TileCoord? cell) {
    if (hover.value != cell) hover.value = cell;
  }

  /// The pointer itself, in the world.
  Offset? hoverPoint;

  /// What the active tool would do if clicked now: each cell it would
  /// change, and to what ([TileCell.empty] erases).
  Map<TileCoord, int> preview = const {};

  /// An area being dragged out — tiles being picked up, a selection
  /// rectangle — as its two corner cells.
  (TileCoord, TileCoord)? dragArea;

  /// Cells lifted by the select tool while they are moved, by where they
  /// were, and how far they have been moved.
  Map<TileCoord, int> floating = const {};
  TileCoord floatOffset = const TileCoord(0, 0);

  /// Where [cell] is while the floating cells are moved by [floatOffset],
  /// which is in [g]'s stable coordinates so a block keeps its shape.
  TileCoord floated(MapGeometry g, TileCoord cell) {
    final s = g.toStable(cell);
    return g.fromStable(TileCoord(s.x + floatOffset.x, s.y + floatOffset.y));
  }

  /// Tiles copied with Ctrl+C, relative to the middle of the block. The
  /// author's, like the brush: it survives opening another scene.
  TileStamp? clipboard;

  /// Clears what the tools are showing.
  void clearPreview() {
    preview = const {};
    dragArea = null;
    floating = const {};
    floatOffset = const TileCoord(0, 0);
  }

  /// Forgets everything that belonged to the scene: the map, the layer, the
  /// selection. The brush is kept — it is the author's, not the level's.
  void reset() {
    mapEntityId.value = null;
    layerId.value = null;
    selection.value = const {};
    hoverCell = null;
    hoverPoint = null;
    clearPreview();
  }

  /// Makes the map on [entity] the one being painted.
  void selectMap(Entity entity) {
    if (mapEntityId.value != entity.id) {
      mapEntityId.value = entity.id;
      selection.value = const {};
    }
    final target = _docs.resolve(entity);
    if (target != null && target.data.layerById(layerId.value ?? -1) == null) {
      layerId.value = target.data.layers.isEmpty
          ? null
          : target.data.layers.last.id;
    }
  }

  void _follow() {
    final selected = sceneState.selectedEntity.value;
    // A piece cut from a layer is a map too, but not one to paint: the
    // tools stay on the Level Map it belongs to.
    if (selected != null &&
        selected.hasComponent<LevelMapComponent>() &&
        !LevelMaps.isPiece(_docs.world, selected)) {
      selectMap(selected);
    }
  }

  /// The map being painted, if it is there and loaded — else the level's
  /// own map ([LevelMaps.primaryEntity]). Never a piece of a map.
  LevelMapTarget? target(World world) {
    final found = _chosen(world);
    if (found != null) return found;
    final primary = LevelMaps.primaryEntity(world);
    final resolved = _docs.resolve(primary);
    if (resolved != null) selectMap(primary!);
    return resolved;
  }

  /// The map [target] would find, without choosing it — for widgets, which
  /// must not change a signal while they build.
  LevelMapTarget? peek(World world) =>
      _chosen(world) ?? _docs.resolve(LevelMaps.primaryEntity(world));

  LevelMapTarget? _chosen(World world) {
    final id = mapEntityId.value;
    final entity = id == null ? null : world.getEntity(id);
    if (entity == null || LevelMaps.isPiece(world, entity)) return null;
    return _docs.resolve(entity);
  }

  /// The layer [layerOf] would pick, without choosing it.
  MapLayerData? peekLayer(LevelMapTarget target) =>
      target.data.layerById(layerId.value ?? -1) ??
      (target.data.layers.isEmpty ? null : target.data.layers.last);

  /// The layer being painted on [target]: the chosen one, or the top one.
  MapLayerData? layerOf(LevelMapTarget target) {
    final chosen = target.data.layerById(layerId.value ?? -1);
    if (chosen != null) return chosen;
    if (target.data.layers.isEmpty) return null;
    final top = target.data.layers.last;
    layerId.value = top.id;
    return top;
  }

  void dispose() {
    _unwatchScene();
    _unwatchSelection();
    _unwatchLayer();
    for (final s in <Signal<Object?>>[
      mapEntityId,
      layerId,
      slot,
      stamp,
      terrain,
      random,
      highlightLayer,
      showCollision,
      fillShape,
      selectMode,
      selection,
      hover,
      paletteZoom,
      paletteTerrains,
      collapsedTilesets,
    ]) {
      s.dispose();
    }
  }
}

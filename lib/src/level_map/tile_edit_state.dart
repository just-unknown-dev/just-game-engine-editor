import 'dart:ui';

import 'package:just_game_engine/just_game_engine.dart';

import 'package:just_editor_core/host.dart';
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

  /// Paints [layer] from now on and, given the designer's [controller],
  /// places what is placed at its depth: how a layer is chosen, from the
  /// Layers panel or a layer picker alike.
  void selectLayer(MapLayerData layer, {LevelDesignerController? controller}) {
    layerId.value = layer.id;
    controller?.activeLayerId.value = layer.sortLayerId;
  }

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

  // ── Which tilesets the brush paints from ────────────────────────────────
  //
  // A cell names its tileset by the slot its map keeps it in, and another
  // map numbers its tilesets its own way — or lacks one. The brush and the
  // clipboard outlive their map (they survive opening another scene, and a
  // tileset being taken off the map), so each keeps which tileset each of
  // its slots stood for, and is put back in the numbers of the map it
  // paints ([stampIn]) — or refused, when that map lacks one of them.

  TileStamp? _stampOfTable;
  Map<int, String> _stampTable = const {};
  TileStamp? _clipboardOfTable;
  Map<int, String> _clipboardTable = const {};

  /// The tileset paths [stamp]'s slots stand for, by slot; empty when the
  /// brush was filled without saying (it is painted as it is).
  Map<int, String> get stampTilesets =>
      identical(stamp.value, _stampOfTable) ? _stampTable : const {};

  /// The same for [clipboard].
  Map<int, String> get clipboardTilesets =>
      identical(clipboard, _clipboardOfTable) ? _clipboardTable : const {};

  /// Fills the brush with [value], whose slots stand for [tilesets] — a
  /// map's, from [tilesetsOf].
  void setStamp(TileStamp? value, {Map<int, String> tilesets = const {}}) {
    _stampOfTable = value;
    _stampTable = Map.unmodifiable(tilesets);
    stamp.value = value;
  }

  /// Copies [value], whose slots stand for [tilesets], for Ctrl+V.
  void setClipboard(TileStamp? value, {Map<int, String> tilesets = const {}}) {
    _clipboardOfTable = value;
    _clipboardTable = Map.unmodifiable(tilesets);
    clipboard = value;
  }

  /// [map]'s tilesets by the slots it keeps them in.
  static Map<int, String> tilesetsOf(LevelMapData map) => {
    for (var i = 0; i < map.tilesets.length; i++) i: ?map.tilesets[i],
  };

  (
    TileStamp,
    Map<int, String>,
    LevelMapData,
    int,
    ({TileStamp? stamp, String? missing}),
  )?
  _stampInCache;

  /// The brush in [map]'s numbering: its cells' slots moved to wherever
  /// [map] keeps the tilesets they stood for. `missing` names a tileset
  /// the brush paints from that [map] does not have, and `stamp` is then
  /// null. With no brush, both are null.
  ({TileStamp? stamp, String? missing}) stampIn(LevelMapData map) {
    final value = stamp.value;
    if (value == null) return (stamp: null, missing: null);
    final table = stampTilesets;
    final cached = _stampInCache;
    if (cached != null &&
        identical(cached.$1, value) &&
        identical(cached.$2, table) &&
        identical(cached.$3, map) &&
        cached.$4 == map.revision) {
      return cached.$5;
    }
    final result = remap(value, table, map);
    _stampInCache = (value, table, map, map.revision, result);
    return result;
  }

  /// [stamp], whose slots stand for [table], in [map]'s numbering; see
  /// [stampIn]. A slot [table] does not name is left as it is.
  static ({TileStamp? stamp, String? missing}) remap(
    TileStamp stamp,
    Map<int, String> table,
    LevelMapData map,
  ) {
    if (table.isEmpty) return (stamp: stamp, missing: null);
    final used = <int>{
      for (final c in stamp.cells)
        if (!TileCell.isEmpty(c.cell)) TileCell.slotOf(c.cell),
      for (final c in stamp.choices)
        if (!TileCell.isEmpty(c)) TileCell.slotOf(c),
    };
    final moves = <int, int>{};
    for (final from in used) {
      final path = table[from];
      if (path == null) continue;
      final to = map.slotOf(path);
      if (to < 0) return (stamp: null, missing: path);
      if (to != from) moves[from] = to;
    }
    if (moves.isEmpty) return (stamp: stamp, missing: null);
    int move(int cell) {
      if (TileCell.isEmpty(cell)) return cell;
      final to = moves[TileCell.slotOf(cell)];
      return to == null
          ? cell
          : TileCell.make(to, TileCell.localIdOf(cell), TileCell.flagsOf(cell));
    }

    return (
      stamp: TileStamp(
        [for (final c in stamp.cells) StampCell(c.offset, move(c.cell))],
        choices: [for (final c in stamp.choices) move(c)],
        weights: stamp.weights,
      ),
      missing: null,
    );
  }

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

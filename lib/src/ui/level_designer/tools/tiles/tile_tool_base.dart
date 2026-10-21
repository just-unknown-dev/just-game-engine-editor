import 'dart:collection';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:just_game_engine/just_game_engine.dart';

import 'package:just_editor_core/host.dart';
import '../../../../core/level_map/tile_commands.dart';
import '../../../../core/level_map/tile_edit_state.dart';
import '../../../../core/level_map/level_map_documents.dart';
import '../../controls/designer_controls.dart';
import '../../state/map_placement.dart';
import '../../../../core/scope/editor_scope_services.dart';

/// Ids of the tile tools.
abstract final class TileTools {
  static const String stamp = 'tiles.stamp';
  static const String terrain = 'tiles.terrain';
  static const String fill = 'tiles.fill';
  static const String erase = 'tiles.erase';
  static const String select = 'tiles.select';
}

/// The map and layer a tile tool acts on.
typedef TileAim = ({LevelMapTarget target, MapLayerData layer});

/// What every tile tool shares.
///
/// Right-drag (or Alt-drag) over the map picks tiles up into the brush, as
/// in Tiled; X and Y mirror the brush and Z turns it (Shift+Z the other
/// way). Tools paint through a [TileStroke], so what they change shows at
/// once and becomes one undo step when the stroke ends.
abstract class TileTool extends LevelToolHandler {
  TileTool(this.scope, {this.switchTool});

  final EditorScope scope;

  /// Switches the designer's tool — a stamp picked up with the eraser goes
  /// straight to the stamp tool.
  final void Function(String toolId)? switchTool;

  TileEditState get state => scope.tiles;
  LevelMapDocuments get docs => scope.mapDocs;

  final math.Random random = math.Random();

  @override
  String get group => ToolGroups.tiles;

  @override
  bool get acceptsSecondaryButton => true;

  /// The layer being painted, the tool's own settings, then how the map is
  /// shown while painting.
  @override
  Widget? buildOptions(BuildContext context, ToolOptionsContext options) {
    final own = buildTileOptions(context, options);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        MapLayerPicker(
          scope: scope,
          world: options.world,
          controller: options.controller,
        ),
        if (own.isNotEmpty) ...[const OptionsDivider(), ...own],
        const OptionsDivider(),
        SignalToggle(
          signal: state.highlightLayer,
          icon: Icons.layers_outlined,
          tooltip: 'Highlight the layer being painted: fade the others',
        ),
        SignalToggle(
          signal: state.showCollision,
          icon: Icons.border_outer,
          tooltip: 'Show the tiles\' collision, coloured by kind',
        ),
      ],
    );
  }

  /// This tool's own settings, for the status bar; none by default.
  List<Widget> buildTileOptions(
    BuildContext context,
    ToolOptionsContext options,
  ) => const [];

  /// Paint one of the brush's tiles per cell at random.
  Widget randomToggle() => SignalToggle(
    signal: state.random,
    icon: Icons.casino_outlined,
    label: 'Random',
    tooltip:
        'Paint one of the brush\'s tiles per cell, as likely as each '
        'tile\'s probability says',
  );

  // ── Aim ──────────────────────────────────────────────────────────────────

  /// The map and layer to act on, or null — having said why, unless
  /// [quiet]. [forEdit] also refuses a locked layer and a Tiled map named
  /// directly, which can be looked at but not changed. With [create], a
  /// scene with no map yet gets its Level Map, for a painting press to
  /// draw on: kept when the gesture paints something ([commit]), taken away
  /// when it does not.
  TileAim? aim(
    ToolContext c, {
    bool forEdit = true,
    bool quiet = false,
    bool create = false,
  }) {
    void say(String message) {
      if (!quiet) c.controller.setStatus(message);
    }

    final target = create
        ? scope.mapProvision.ensure(c.world)
        : state.target(c.world);
    if (target == null) {
      // None yet, one still loading, or one whose file will not load.
      say(MapPlacement.whyNoMap(scope, c.world));
      return null;
    }
    final layer = state.layerOf(target);
    if (layer == null) {
      say('${target.entity.name ?? 'The map'} has no layers: add one');
      return null;
    }
    if (forEdit && target.isReadOnly) {
      say('${target.path} is a Tiled map: convert it to edit it');
      return null;
    }
    if (forEdit && layer.locked) {
      say('${layer.name} is locked');
      return null;
    }
    return (target: target, layer: layer);
  }

  /// The cell of [aim]'s layer under [world], parallax allowed for.
  TileCoord cellAt(TileAim aim, Offset world, ToolContext c) =>
      aim.target.geometry.cellAt(localPoint(aim, world, c));

  /// [world] in [aim]'s layer's own pixels, where the layer is drawn now.
  static Offset localPoint(TileAim aim, Offset world, ToolContext c) =>
      world - layerShift(aim.target, aim.layer, c.camera?.position);

  /// Where [layer] of [target] is drawn: the map's origin, the layer's
  /// offset, and how far its parallax has it lag behind [camera].
  static Offset layerShift(
    LevelMapTarget target,
    MapLayerData layer,
    Offset? camera,
  ) => target.layerShift(layer, camera);

  /// A stroke on [aim]'s layer.
  TileStroke strokeOn(TileAim aim) =>
      TileStroke(docs: docs, ref: aim.target.ref, layer: aim.layer);

  /// Ends [stroke] as one undo step — with the making of the Level Map,
  /// when the gesture made it.
  void commit(TileStroke? stroke, String label) =>
      scope.mapProvision.commit(label, stroke?.finish(label));

  // ── Picking tiles up ─────────────────────────────────────────────────────

  TileCoord? _pickStart;
  bool _picking = false;

  /// Whether a gesture of this tool is under way: keys pressed meanwhile
  /// change the brush, not what the gesture is about to paint.
  bool _down = false;

  bool _isPick(ToolContext c) =>
      c.button == ToolButton.secondary ||
      (c.button == ToolButton.primary && c.isAltDown);

  @override
  bool onPointerDown(ToolContext context) {
    final c = context;
    if (_isPick(c)) {
      final a = aim(c, forEdit: false);
      if (a == null) return true;
      _picking = true;
      _down = true;
      _pickStart = cellAt(a, c.worldPosition, c);
      state.dragArea = (_pickStart!, _pickStart!);
      return true;
    }
    return _down = onPaintDown(c);
  }

  @override
  void onPointerMove(ToolContext context) {
    final c = context;
    if (_picking) {
      final a = aim(c, forEdit: false, quiet: true);
      if (a != null) {
        state.dragArea = (_pickStart!, cellAt(a, c.worldPosition, c));
      }
      return;
    }
    onPaintMove(c);
  }

  @override
  void onPointerUp(ToolContext context) {
    final c = context;
    _down = false;
    if (_picking) {
      _finishPick(c);
      return;
    }
    onPaintUp(c);
    // A map made for a press that painted nothing goes again.
    scope.mapProvision.cancel();
  }

  @override
  void onCancel() {
    _down = false;
    if (_picking) {
      _picking = false;
      state.dragArea = null;
    }
    onPaintCancel();
    scope.mapProvision.cancel();
  }

  void _finishPick(ToolContext c) {
    _picking = false;
    final area = state.dragArea;
    state.dragArea = null;
    final a = aim(c, forEdit: false);
    if (a == null || area == null) return;
    if (areaOf(area.$1, area.$2) > maxRegion) {
      c.controller.setStatus(
        'Too much to pick up at once: at most $maxRegion cells',
      );
      return;
    }
    final cells = rectCells(area.$1, area.$2);
    final TileStamp stamp;
    if (cells.length == 1) {
      // One cell, even an empty one: an empty stamp erases, as in Tiled.
      stamp = TileStamp.single(
        a.layer.cells.cellAt(cells.single.x, cells.single.y),
      );
    } else {
      stamp = TileStamp.capture(
        a.layer.cells,
        cells,
        a.target.geometry,
        skipEmpty: true,
      );
    }
    if (stamp.isEmpty) {
      c.controller.setStatus('Nothing there to pick up');
      return;
    }
    state.setStamp(stamp, tilesets: TileEditState.tilesetsOf(a.target.data));
    c.controller.setStatus(
      stamp.isSingle
          ? (TileCell.isEmpty(stamp.cells.single.cell)
                ? 'Picked up an empty cell: the brush erases'
                : 'Picked up a tile')
          : 'Picked up ${stamp.cells.length} tiles',
    );
    afterPick();
  }

  /// [layers] in the order they are drawn, back to front: by depth
  /// ([MapLayerData.sortLayer]), then [MapLayerData.zOrder], then their
  /// place in the map — what the renderer sorts them by. The order of the
  /// list alone is not it: a layer added at a depth is appended.
  static List<MapLayerData> drawOrder(List<MapLayerData> layers) {
    final indexed = [for (var i = 0; i < layers.length; i++) (i, layers[i])];
    indexed.sort((a, b) {
      final byDepth = a.$2.sortLayer.compareTo(b.$2.sortLayer);
      if (byDepth != 0) return byDepth;
      final byZ = a.$2.zOrder.compareTo(b.$2.zOrder);
      return byZ != 0 ? byZ : a.$1.compareTo(b.$1);
    });
    return [for (final (_, layer) in indexed) layer];
  }

  /// How many cells the box from [a] to [b] holds, without listing them.
  static int areaOf(TileCoord a, TileCoord b) =>
      ((a.x - b.x).abs() + 1) * ((a.y - b.y).abs() + 1);

  /// Every cell of the box from [a] to [b], in map coordinates.
  static List<TileCoord> rectCells(TileCoord a, TileCoord b) => [
    for (var y = math.min(a.y, b.y); y <= math.max(a.y, b.y); y++)
      for (var x = math.min(a.x, b.x); x <= math.max(a.x, b.x); x++)
        TileCoord(x, y),
  ];

  // ── Hover ────────────────────────────────────────────────────────────────

  @override
  void onPointerHover(ToolContext context) {
    final c = context;
    final a = aim(c, forEdit: false, quiet: true);
    if (a == null) {
      state.hoverCell = null;
      state.preview = const {};
      return;
    }
    final at = cellAt(a, c.worldPosition, c);
    state
      ..hoverCell = at
      ..hoverPoint = c.worldPosition
      ..preview = previewAt(a, at);
  }

  @override
  void onPointerExit() {
    state
      ..hoverCell = null
      ..preview = const {};
  }

  @override
  void onDeactivate() {
    state.clearPreview();
    state.hoverCell = null;
  }

  /// What a click at [at] would paint, for the brush overlay.
  Map<TileCoord, int> previewAt(TileAim aim, TileCoord at) => const {};

  // ── Keys ─────────────────────────────────────────────────────────────────

  @override
  bool onKey(LogicalKeyboardKey key, ToolContext context) {
    final c = context;
    final m = c.modifiers;
    if (m.control &&
        !m.alt &&
        !m.shift &&
        !m.other &&
        key == LogicalKeyboardKey.keyV) {
      // Kept even with nothing copied: Ctrl+V (Cmd+V) with a tile tool in
      // hand must not paste entities instead.
      final copied = state.clipboard;
      if (copied == null) {
        c.controller.setStatus(
          'Nothing copied: select tiles and press '
          '${EditorKeys.withPrimary('C')}',
        );
        return true;
      }
      state.setStamp(copied, tilesets: state.clipboardTilesets);
      c.controller.setStatus('Copied tiles are in the brush');
      if (id != TileTools.stamp) switchTool?.call(TileTools.stamp);
      return true;
    }
    if (m.control || m.alt || m.other) return false;
    final stamp = state.stamp.value;
    final target = state.target(c.world);
    if (stamp == null || target == null) return false;
    final g = target.geometry;
    final (TileStamp? next, String? said) = switch (key) {
      LogicalKeyboardKey.keyX => (
        stamp.flippedH(g),
        'Brush mirrored left to right',
      ),
      LogicalKeyboardKey.keyY => (
        stamp.flippedV(g),
        'Brush mirrored top to bottom',
      ),
      LogicalKeyboardKey.keyZ => (
        stamp.turned(g, clockwise: !m.shift),
        'Brush turned ${m.shift ? 'anticlockwise' : 'clockwise'}',
      ),
      _ => (null, null),
    };
    if (next == null) return false;
    // The same tiles, turned: their slots still stand for what they did.
    state.setStamp(next, tilesets: state.stampTilesets);
    c.controller.setStatus(said!);
    // The brush under the pointer shows it — not mid-gesture, when what is
    // shown is what the gesture is about to paint.
    if (!_down) onPointerHover(c);
    return true;
  }

  // ── Painting ─────────────────────────────────────────────────────────────

  /// The brush in [aim]'s map's numbering of its tilesets
  /// ([TileEditState.stampIn]) — or null: no brush, or one that paints from
  /// a tileset the map does not have, which is said unless [quiet].
  TileStamp? brushFor(TileAim aim, ToolContext c, {bool quiet = false}) {
    final (:stamp, :missing) = state.stampIn(aim.target.data);
    if (missing != null && !quiet) {
      c.controller.setStatus(
        'The brush paints from $missing, which this map does not use: add '
        'it in the Tileset panel (+) first',
      );
    }
    return stamp;
  }

  /// The value to paint where [stamp] says [value]: in random mode, one of
  /// the stamp's tiles by probability.
  int paintValue(TileAim aim, TileStamp stamp, int value) {
    if (stamp.isRandom) return stamp.pick(random);
    if (!state.random.value || stamp.cells.length < 2) return value;
    return _randomOf(aim, stamp)?.pick(random) ?? value;
  }

  (TileStamp, LevelMapData, TileStamp?)? _random;

  /// [stamp]'s tiles as a random pick, weighted by their probability on
  /// [aim]'s map: made once per brush and map, not once per cell. Null
  /// when the stamp holds no tile.
  TileStamp? _randomOf(TileAim aim, TileStamp stamp) {
    final cached = _random;
    if (cached != null &&
        identical(cached.$1, stamp) &&
        identical(cached.$2, aim.target.data)) {
      return cached.$3;
    }
    final choices = [
      for (final c in stamp.cells)
        if (!TileCell.isEmpty(c.cell)) c.cell,
    ];
    final made = choices.isEmpty
        ? null
        : TileStamp.random(choices, [
            for (final c in choices)
              aim.target
                      .tilesetAt(TileCell.slotOf(c))
                      ?.tile(TileCell.localIdOf(c))
                      ?.probability ??
                  1,
          ]);
    _random = (stamp, aim.target.data, made);
    return made;
  }

  /// Paints [stamp] with its pointer cell at [at].
  void stampAt(TileStroke stroke, TileAim aim, TileCoord at, TileStamp stamp) {
    final random = state.random.value;
    for (final (cell, value) in stamp.placeAt(
      at,
      aim.target.geometry,
      this.random,
    )) {
      stroke.set(cell, random ? paintValue(aim, stamp, value) : value);
    }
  }

  /// The cells a drag passed over from [from] to [to] (not [from] itself),
  /// so a quick stroke leaves no gaps.
  static List<TileCoord> cellsAlong(
    MapGeometry g,
    TileCoord from,
    TileCoord to,
  ) {
    if (from == to) return const [];
    final a = g.cellCenter(from.x, from.y);
    final b = g.cellCenter(to.x, to.y);
    final step = math.max(1.0, math.min(g.tileWidth, g.tileHeight) / 3);
    final n = ((b - a).distance / step).ceil();
    final out = <TileCoord>[];
    for (var i = 1; i <= n; i++) {
      final c = g.cellAt(Offset.lerp(a, b, i / n)!);
      if (c != from && (out.isEmpty || out.last != c)) out.add(c);
    }
    if (out.isEmpty || out.last != to) out.add(to);
    return out;
  }

  // ── Regions ──────────────────────────────────────────────────────────────

  /// Past this, a flood stops, so one click on open ground cannot fill
  /// forever.
  static const int maxRegion = 100000;

  /// The cells joined to [start] by an edge that hold what it holds,
  /// within [limit].
  static Set<TileCoord> connected(
    MapGeometry g,
    TileChunkStore cells,
    TileCoord start,
    TileRange limit,
  ) {
    final wanted = cells.cellAt(start.x, start.y);
    final out = <TileCoord>{start};
    final queue = Queue<TileCoord>()..add(start);
    while (queue.isNotEmpty && out.length < maxRegion) {
      final at = queue.removeFirst();
      for (final n in g.neighbours(at)) {
        if (!limit.contains(n.x, n.y) || out.contains(n)) continue;
        if (cells.cellAt(n.x, n.y) != wanted) continue;
        out.add(n);
        queue.add(n);
      }
    }
    return out;
  }

  /// How far a flood may reach on [aim]'s layer: what is on screen, and one
  /// cell past everything painted — an infinite map has no edge to stop at.
  static TileRange floodLimit(TileAim aim, ToolContext c) {
    var limit = visibleRange(aim, c);
    final used = aim.layer.cells.usedBounds;
    if (used == null) return limit;
    return TileRange(
      math.min(limit.x0, used.left.toInt() - 1),
      math.min(limit.y0, used.top.toInt() - 1),
      math.max(limit.x1, used.right.toInt() + 1),
      math.max(limit.y1, used.bottom.toInt() + 1),
    );
  }

  /// The cells of [aim]'s layer on screen; without a camera, 64 cells
  /// around the origin.
  static TileRange visibleRange(TileAim aim, ToolContext c) {
    final camera = c.camera;
    if (camera == null || c.canvasSize == Size.zero) {
      return const TileRange(-64, -64, 65, 65);
    }
    final half =
        Offset(c.canvasSize.width, c.canvasSize.height) / (2 * camera.zoom);
    final shift = layerShift(aim.target, aim.layer, camera.position);
    final centre = camera.position - shift;
    return aim.target.geometry.cellRange(
      Rect.fromPoints(centre - half, centre + half),
    );
  }

  /// Pressed with the tool's own button: return true to claim the gesture.
  bool onPaintDown(ToolContext c);
  void onPaintMove(ToolContext c) {}
  void onPaintUp(ToolContext c) {}
  void onPaintCancel() {}

  /// Tiles were picked up into the brush.
  void afterPick() {}
}

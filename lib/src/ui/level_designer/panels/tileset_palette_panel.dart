import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:just_game_engine/just_game_engine.dart' as jge;
import 'package:just_signals/just_signals.dart';

import '../../../core/assets/package_asset_paths.dart';
import '../../../core/constants/editor_constants.dart';
import '../../../core/level_map/tile_commands.dart';
import '../../../core/level_map/tile_edit_state.dart';
import '../../../core/level_map/level_map_documents.dart';
import '../controls/designer_controls.dart';
import '../level_designer_session.dart';
import '../tools/level_tool.dart';
import '../tools/tiles/tile_tool_base.dart';
import '../../tileset/built_in_workspaces.dart';
import '../../widgets/editor_scrollbar.dart';

/// The tiles to paint with: the engine's basic shapes, then the map's own
/// tilesets, one under another, each with its tiles below its name.
///
/// Click a tile to put it in the brush, drag across several for a block,
/// Ctrl+click to gather tiles the brush picks between at random. The brush
/// is shared with the map: tiles picked up there show as chosen here. A
/// basic shape picked before the map has that tileset adds it — and makes
/// the Level Map, in a scene with none — in the same step.
class TilesetPalettePanel extends StatelessWidget {
  const TilesetPalettePanel({super.key, required this.session});

  final LevelDesignerSession session;

  @override
  Widget build(BuildContext context) {
    final tiles = session.scope.tiles;
    return SignalBuilder3<int, int?, int>(
      signal1: session.scope.mapDocs.revision,
      signal2: tiles.mapEntityId,
      signal3: session.sceneState.revision,
      builder: (context, _, _, _, _) =>
          SignalBuilder3<int, Set<String>, double>(
            signal1: tiles.slot,
            signal2: tiles.collapsedTilesets,
            signal3: tiles.paletteZoom,
            builder: (context, _, collapsed, zoom, _) =>
                _build(context, collapsed, zoom),
          ),
    );
  }

  Widget _build(BuildContext context, Set<String> collapsed, double zoom) {
    final target = session.scope.tiles.peek(session.world);
    final data = target?.data;
    final sections = <(String, int?)>[
      // The engine's own first, whether or not the map has them yet.
      for (final path in jge.BuiltInTilesets.all)
        (
          path,
          switch (data?.slotOf(path) ?? -1) {
            final s when s >= 0 => s,
            _ => null,
          },
        ),
      if (data != null)
        for (var i = 0; i < data.tilesets.length; i++)
          if (data.tilesets[i] case final path?
              when !jge.BuiltInTilesets.isBuiltIn(path))
            (path, i),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _TopRow(session: session, target: target),
        if (target == null)
          const TilePanelMessage(
            text:
                'No Level Map yet: picking a tile of the basic shapes makes '
                'it, or drop a tileset on the level.',
          ),
        Expanded(
          child: EditorScrollbar(
            builder: (_, scroll) => ListView(
              controller: scroll,
              padding: const EdgeInsets.only(bottom: 4),
              children: [
                for (final (path, slot) in sections)
                  _TilesetSection(
                    key: ValueKey(('tileset', path)),
                    session: session,
                    target: target,
                    path: path,
                    slot: slot,
                    collapsed: collapsed.contains(path),
                    zoom: zoom,
                  ),
                if (target != null &&
                    sections.every((s) => jge.BuiltInTilesets.isBuiltIn(s.$1)))
                  TilePanelMessage(
                    text: target.isReadOnly
                        ? 'This Tiled map has no tilesets of its own.'
                        : 'Add a tileset (+) to paint with its tiles too.',
                  ),
              ],
            ),
          ),
        ),
        _ZoomBar(zoom: zoom, onZoom: (steps) => _zoomBy(session, steps)),
      ],
    );
  }

  static const List<double> zooms = [0.5, 1, 1.5, 2, 3, 4];

  static void _zoomBy(LevelDesignerSession session, int steps) {
    final tiles = session.scope.tiles;
    final i = zooms.indexWhere((z) => z >= tiles.paletteZoom.value);
    final next = ((i < 0 ? zooms.length - 1 : i) + steps).clamp(
      0,
      zooms.length - 1,
    );
    tiles.paletteZoom.value = zooms[next];
  }
}

/// Tiles or terrains: what the panel lists.
class _ViewSwitch extends StatelessWidget {
  const _ViewSwitch({required this.session});

  final LevelDesignerSession session;

  @override
  Widget build(BuildContext context) => SignalBuilder<bool>(
    signal: session.scope.tiles.paletteTerrains,
    builder: (context, terrains, _) => Container(
      height: 24,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Row(
        children: [
          for (final (label, on) in [('Tiles', false), ('Terrains', true)])
            InkWell(
              onTap: () => session.scope.tiles.paletteTerrains.value = on,
              borderRadius: BorderRadius.circular(3),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: terrains == on
                        ? FontWeight.w600
                        : FontWeight.w400,
                    color: terrains == on
                        ? EditorTheme.textBright
                        : EditorTheme.textMuted,
                  ),
                ),
              ),
            ),
        ],
      ),
    ),
  );
}

/// A tileset's terrains, to paint with the terrain tool.
class _TerrainList extends StatelessWidget {
  const _TerrainList({
    required this.session,
    required this.target,
    required this.slot,
  });

  final LevelDesignerSession session;
  final LevelMapTarget target;
  final int slot;

  void _choose(TerrainChoice choice) {
    session.scope.tiles.terrain.value = choice;
    if (session.controller.toolId.value != TileTools.terrain) {
      session.setTool(TileTools.terrain);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ts = target.tilesetAt(slot);
    if (!target.geometry.hasLattice) {
      return const TilePanelMessage(
        text:
            'Terrain painting needs square-cornered cells; this '
            'hexagonal map has none. Paint it with the stamp.',
      );
    }
    if (ts == null) return const TilePanelMessage(text: 'Loading…');
    if (ts.wangSets.isEmpty) {
      return TilePanelMessage(
        text:
            'No terrains in ${tilesetLabel(target, slot)}. Give its tiles '
            'terrains in the Tileset Editor\'s Terrain mode.',
        action: (
          'Edit tileset',
          () => session.scope.openWorkspace(
            BuiltInWorkspaces.tileset,
            path: target.data.tilesets[slot],
          ),
        ),
      );
    }
    final image = target.component.runtime?.imageAt(slot);
    return SignalBuilder<TerrainChoice?>(
      signal: session.scope.tiles.terrain,
      builder: (context, chosen, _) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < ts.wangSets.length; i++) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 6, 10, 2),
                child: Text(
                  '${ts.wangSets[i].name.isEmpty ? 'Terrains' : ts.wangSets[i].name} '
                  '· ${ts.wangSets[i].type.name}',
                  style: TextStyle(fontSize: 10, color: EditorTheme.textMuted),
                ),
              ),
              for (var c = 0; c < ts.wangSets[i].colors.length; c++)
                _TerrainRow(
                  color: ts.wangSets[i].colors[c],
                  image: image,
                  tileset: ts,
                  isChosen:
                      chosen == TerrainChoice(slot: slot, set: i, color: c + 1),
                  onTap: () =>
                      _choose(TerrainChoice(slot: slot, set: i, color: c + 1)),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _TerrainRow extends StatelessWidget {
  const _TerrainRow({
    required this.color,
    required this.image,
    required this.tileset,
    required this.isChosen,
    required this.onTap,
  });

  final jge.WangColorData color;
  final ui.Image? image;
  final jge.TilesetData tileset;
  final bool isChosen;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tile = color.tile;
    return Material(
      color: isChosen ? EditorTheme.selectionBg : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          child: Row(
            children: [
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: Color(color.color),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 6),
              if (image != null && tileset.contains(tile))
                SizedBox(
                  width: 20,
                  height: 20,
                  child: CustomPaint(
                    painter: _ThumbPainter(image!, tileset.sourceRect(tile)),
                  ),
                ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  color.name.isEmpty ? 'Terrain' : color.name,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    color: isChosen
                        ? EditorTheme.textBright
                        : EditorTheme.textSecondary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ThumbPainter extends CustomPainter {
  _ThumbPainter(this.image, this.source);

  final ui.Image image;
  final Rect source;

  @override
  void paint(Canvas canvas, Size size) => canvas.drawImageRect(
    image,
    source,
    Offset.zero & size,
    Paint()..filterQuality = FilterQuality.none,
  );

  @override
  bool shouldRepaint(_ThumbPainter old) =>
      old.image != image || old.source != source;
}

/// Every `.tileset.json` under [root]/assets, project-relative, then those
/// installed packages ship (`packages/<name>/…`).
List<String> findTilesets(String root) {
  final dir = Directory('$root/assets');
  final out = <String>[];
  if (dir.existsSync()) {
    try {
      for (final f in dir.listSync(recursive: true)) {
        if (f is! File) continue;
        final p = f.path.replaceAll(r'\', '/');
        if (!p.toLowerCase().endsWith('.tileset.json')) continue;
        out.add(p.startsWith('$root/') ? p.substring(root.length + 1) : p);
      }
    } on FileSystemException {
      out.clear();
    }
  }
  out.sort();
  return out
    ..addAll(
      PackageAssetPaths.of(root).packageFiles(endings: const ['.tileset.json']),
    );
}

/// What the list calls the tileset in [slot].
String tilesetLabel(LevelMapTarget target, int slot) {
  final ts = target.tilesetAt(slot);
  if (ts != null && ts.name.isNotEmpty) return ts.name;
  final path = target.data.tilesets[slot] ?? '';
  var name = path.substring(path.lastIndexOf('/') + 1);
  if (name.endsWith('.tileset.json')) {
    name = name.substring(0, name.length - '.tileset.json'.length);
  }
  return name;
}

/// Above the tilesets: tiles or terrains, and a tileset to add.
class _TopRow extends StatelessWidget {
  const _TopRow({required this.session, required this.target});

  final LevelDesignerSession session;
  final LevelMapTarget? target;

  void _add(String path) {
    final target = this.target;
    if (target == null) return;
    final scope = session.scope;
    var added = -1;
    final command = MapStructureCommand.record(
      label: 'Add tileset',
      docs: scope.mapDocs,
      ref: target.ref,
      change: (map) => added = map.addTileset(path),
    );
    if (command == null) return;
    scope.history.pushApplied(command);
    scope.tiles.slot.value = added;
    // Shown open, where it can be seen.
    scope.tiles.collapsedTilesets.value = {
      ...scope.tiles.collapsedTilesets.value,
    }..remove(path);
  }

  @override
  Widget build(BuildContext context) {
    final target = this.target;
    return Container(
      height: 26,
      padding: const EdgeInsets.only(left: 2, right: 6),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: EditorTheme.border)),
      ),
      child: Row(
        children: [
          Expanded(child: _ViewSwitch(session: session)),
          if (target != null && !target.isReadOnly)
            PopupMenuButton<String>(
              tooltip: 'Add a tileset to the map',
              color: EditorTheme.menuBg,
              position: PopupMenuPosition.under,
              onSelected: _add,
              itemBuilder: (context) {
                final used = target.data.tilesets.toSet();
                final files = findTilesets(
                  session.scope.mapDocs.projectRoot,
                ).where((p) => !used.contains(p)).toList();
                if (files.isEmpty) {
                  return [
                    PopupMenuItem(
                      enabled: false,
                      height: 28,
                      child: Text(
                        'No other .tileset.json files under assets/',
                        style: TextStyle(
                          fontSize: 11,
                          color: EditorTheme.textMuted,
                        ),
                      ),
                    ),
                  ];
                }
                return [
                  for (final path in files)
                    PopupMenuItem(
                      value: path,
                      height: 28,
                      child: Text(
                        path,
                        style: TextStyle(
                          fontSize: 11,
                          color: EditorTheme.textSecondary,
                        ),
                      ),
                    ),
                ];
              },
              child: Padding(
                padding: EdgeInsets.all(4),
                child: Icon(
                  Icons.add,
                  size: 15,
                  color: EditorTheme.textSecondary,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// One tileset of the list: its name — a click folds it away — and its
/// tiles, or its terrains.
class _TilesetSection extends StatelessWidget {
  const _TilesetSection({
    super.key,
    required this.session,
    required this.target,
    required this.path,
    required this.slot,
    required this.collapsed,
    required this.zoom,
  });

  final LevelDesignerSession session;

  /// The map painted, if there is one.
  final LevelMapTarget? target;
  final String path;

  /// Where the map has it; null for a built-in tileset it has not yet.
  final int? slot;
  final bool collapsed;
  final double zoom;

  bool get _builtIn => jge.BuiltInTilesets.isBuiltIn(path);

  jge.TilesetData? get _tileset {
    if (_builtIn) return session.scope.context.tiles.loadedTileset(path);
    final slot = this.slot;
    return slot == null ? null : target?.tilesetAt(slot);
  }

  ui.Image? _image(jge.TilesetData? ts) {
    if (ts == null) return null;
    final drawn = session.scope.context.tiles.builtInImage(ts.image);
    if (drawn != null) return drawn;
    final slot = this.slot;
    return slot == null ? null : target?.component.runtime?.imageAt(slot);
  }

  String get _label {
    final ts = _tileset;
    if (ts != null && ts.name.isNotEmpty) return ts.name;
    final slot = this.slot;
    final target = this.target;
    if (slot != null && target != null) return tilesetLabel(target, slot);
    return path;
  }

  void _toggle() {
    final tiles = session.scope.tiles;
    final next = {...tiles.collapsedTilesets.value};
    if (!next.remove(path)) next.add(path);
    tiles.collapsedTilesets.value = next;
  }

  /// The slot this tileset is in, adding it to the map — making the map,
  /// in a scene with none — when it is not there yet. Null when it cannot
  /// be, having said why.
  int? _ensureSlot() {
    final existing = slot;
    if (existing != null) return existing;
    final scope = session.scope;
    final provision = scope.mapProvision;
    final target = provision.ensure(session.world);
    if (target == null) {
      session.controller.setStatus('The Level Map is still loading');
      return null;
    }
    if (target.isReadOnly) {
      provision.cancel();
      session.controller.setStatus(
        '${target.path} is a Tiled map: convert it to paint on it',
      );
      return null;
    }
    final label = 'Add tileset $_label';
    int added;
    if (provision.isPending) {
      added = target.data.addTileset(path);
      provision.keep(label);
    } else {
      var made = -1;
      final command = MapStructureCommand.record(
        label: label,
        docs: scope.mapDocs,
        ref: target.ref,
        change: (map) => made = map.addTileset(path),
      );
      if (command == null) return null;
      scope.history.pushApplied(command);
      added = made;
    }
    scope.tiles.slot.value = added;
    return added;
  }

  void _remove(LevelMapTarget target, int slot) {
    final scope = session.scope;
    if (target.data.usesSlot(slot)) {
      session.controller.setStatus(
        '$_label is still painted on the map: erase its tiles first',
      );
      return;
    }
    final command = MapStructureCommand.record(
      label: 'Remove tileset',
      docs: scope.mapDocs,
      ref: target.ref,
      // The slot stays, empty, so the tiles of the tilesets after it keep
      // their numbers.
      change: (map) => map.tilesets[slot] = null,
    );
    if (command != null) scope.history.pushApplied(command);
  }

  @override
  Widget build(BuildContext context) {
    final target = this.target;
    final slot = this.slot;
    final ts = _tileset;
    final editable = target != null && !target.isReadOnly;
    final chosen = slot != null && session.scope.tiles.slot.value == slot;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: _toggle,
            child: Container(
              height: 24,
              padding: const EdgeInsets.only(left: 2, right: 2),
              child: Row(
                children: [
                  Icon(
                    collapsed ? Icons.chevron_right : Icons.expand_more,
                    size: 15,
                    color: EditorTheme.textMuted,
                  ),
                  const SizedBox(width: 2),
                  Flexible(
                    child: Tooltip(
                      message: path,
                      child: Text(
                        _label,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: chosen
                              ? EditorTheme.textBright
                              : EditorTheme.textSecondary,
                        ),
                      ),
                    ),
                  ),
                  if (_builtIn) ...[
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        slot == null ? 'built in · not on the map' : 'built in',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 10,
                          color: EditorTheme.textMuted,
                        ),
                      ),
                    ),
                  ],
                  const Spacer(),
                  if (editable && slot != null)
                    PopupMenuButton<String>(
                      tooltip: 'More',
                      color: EditorTheme.menuBg,
                      position: PopupMenuPosition.under,
                      onSelected: (action) {
                        if (action == 'remove') _remove(target, slot);
                        if (action == 'edit') {
                          session.scope.openWorkspace(
                            BuiltInWorkspaces.tileset,
                            path: path,
                          );
                        }
                      },
                      itemBuilder: (context) => [
                        // Drawn in code: nothing to edit.
                        if (!_builtIn)
                          PopupMenuItem(
                            value: 'edit',
                            height: 28,
                            child: Text(
                              'Edit tileset…',
                              style: TextStyle(
                                fontSize: 11,
                                color: EditorTheme.textSecondary,
                              ),
                            ),
                          ),
                        PopupMenuItem(
                          value: 'remove',
                          height: 28,
                          child: Text(
                            'Remove from the map',
                            style: TextStyle(
                              fontSize: 11,
                              color: EditorTheme.textSecondary,
                            ),
                          ),
                        ),
                      ],
                      child: Padding(
                        padding: EdgeInsets.all(5),
                        child: Icon(
                          Icons.more_vert,
                          size: 14,
                          color: EditorTheme.textSecondary,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
        if (!collapsed)
          SignalBuilder<bool>(
            signal: session.scope.tiles.paletteTerrains,
            builder: (context, terrains, _) {
              if (ts == null) {
                return TilePanelMessage(text: 'Loading $path…');
              }
              if (terrains) {
                return target == null || slot == null
                    ? const TilePanelMessage(text: 'No terrains.')
                    : _TerrainList(
                        session: session,
                        target: target,
                        slot: slot,
                      );
              }
              return _TilesetGrid(
                key: ValueKey(('grid', path, slot)),
                session: session,
                tileset: ts,
                image: _image(ts),
                slot: slot,
                ensureSlot: editable || target == null ? _ensureSlot : null,
                geometry: target?.geometry,
                clockMs: target?.component.runtime?.animationMs ?? 0,
                zoom: zoom,
              );
            },
          ),
      ],
    );
  }
}

/// One tileset's tiles, to pick from — at their full height: the list
/// around them scrolls.
class _TilesetGrid extends StatefulWidget {
  const _TilesetGrid({
    super.key,
    required this.session,
    required this.tileset,
    required this.image,
    required this.slot,
    required this.ensureSlot,
    required this.geometry,
    required this.clockMs,
    required this.zoom,
  });

  final LevelDesignerSession session;
  final jge.TilesetData tileset;
  final ui.Image? image;

  /// Where the map has it; null for a built-in one it has not yet.
  final int? slot;

  /// Adds it to the map, for a tile picked from it; null when it cannot be.
  final int? Function()? ensureSlot;

  /// The map's grid, which a block picked keeps the layout of.
  final jge.MapGeometry? geometry;
  final int clockMs;
  final double zoom;

  @override
  State<_TilesetGrid> createState() => _TilesetGridState();
}

class _TilesetGridState extends State<_TilesetGrid> {
  (int, int)? _dragStart;
  (int, int)? _dragEnd;
  bool _gathering = false;

  /// Redraws while the image loads and while animated tiles play.
  Timer? _tick;

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  void _keepTicking(bool needed) {
    if (!needed) {
      _tick?.cancel();
      _tick = null;
      return;
    }
    _tick ??= Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (mounted) setState(() {});
    });
  }

  jge.TilesetData get _tileset => widget.tileset;

  /// The column and row of the tile under [local], or null.
  (int, int)? _cellAt(Offset local, {bool clamp = false}) {
    final ts = _tileset;
    if (ts.columns <= 0) return null;
    final p = local / widget.zoom;
    var col = ((p.dx - ts.margin) / (ts.tileWidth + ts.spacing)).floor();
    var row = ((p.dy - ts.margin) / (ts.tileHeight + ts.spacing)).floor();
    if (clamp) {
      col = col.clamp(0, ts.columns - 1);
      row = row.clamp(0, ts.rows - 1);
    }
    if (col < 0 || row < 0 || col >= ts.columns || row >= ts.rows) return null;
    return ts.contains(row * ts.columns + col) ? (col, row) : null;
  }

  void _down(PointerDownEvent e) {
    if (e.buttons != kPrimaryButton) return;
    final at = _cellAt(e.localPosition);
    if (at == null) return;
    setState(() {
      _dragStart = at;
      _dragEnd = at;
      _gathering = HardwareKeyboard.instance.isControlPressed;
    });
  }

  void _move(PointerMoveEvent e) {
    if (_dragStart == null || _gathering) return;
    final at = _cellAt(e.localPosition, clamp: true);
    if (at != null && at != _dragEnd) setState(() => _dragEnd = at);
  }

  void _up() {
    final start = _dragStart;
    final end = _dragEnd;
    setState(() {
      _dragStart = null;
      _dragEnd = null;
    });
    if (start == null || end == null) return;
    // A tileset the map has not yet joins it now.
    final slot = widget.slot ?? widget.ensureSlot?.call();
    if (slot == null) return;
    final session = widget.session;
    final tiles = session.scope.tiles;
    int cellOf(int col, int row) =>
        jge.TileCell.make(slot, row * _tileset.columns + col);
    tiles.slot.value = slot;
    if (_gathering) {
      tiles.stamp.value = _toggleRandom(cellOf(start.$1, start.$2));
    } else {
      final geometry = widget.geometry ?? tiles.peek(session.world)?.geometry;
      if (geometry == null) return;
      tiles.stamp.value = blockStamp(geometry, start, end, cellOf);
    }
    // A tile picked is a tile to paint; the fill tool fills with it.
    final tool = session.controller.activeTool;
    if (tool?.group != ToolGroups.tiles ||
        tool?.id == TileTools.erase ||
        tool?.id == TileTools.select) {
      session.setTool(TileTools.stamp);
    }
  }

  /// The brush with [cell] added to (or taken from) its random choices.
  jge.TileStamp _toggleRandom(int cell) {
    final current = widget.session.scope.tiles.stamp.value;
    final choices = <int>[
      if (current != null && current.isRandom) ...current.choices,
      if (current != null && current.isSingle && !current.isRandom)
        current.cells.single.cell,
    ].where((c) => !jge.TileCell.isEmpty(c)).toList();
    if (choices.contains(cell)) {
      choices.remove(cell);
    } else {
      choices.add(cell);
    }
    if (choices.isEmpty) return jge.TileStamp.single(cell);
    if (choices.length == 1) return jge.TileStamp.single(choices.single);
    final target = widget.session.scope.tiles.peek(widget.session.world);
    return jge.TileStamp.random(choices, [
      for (final c in choices)
        target
                ?.tilesetAt(jge.TileCell.slotOf(c))
                ?.tile(jge.TileCell.localIdOf(c))
                ?.probability ??
            1,
    ]);
  }

  /// The tiles of this tileset in the brush, to show as chosen.
  Set<int> _chosen(jge.TileStamp? stamp) {
    final slot = widget.slot;
    if (stamp == null || slot == null) return const {};
    final cells = stamp.isRandom
        ? stamp.choices
        : [for (final c in stamp.cells) c.cell];
    return {
      for (final c in cells)
        if (!jge.TileCell.isEmpty(c) && jge.TileCell.slotOf(c) == slot)
          jge.TileCell.localIdOf(c),
    };
  }

  @override
  Widget build(BuildContext context) {
    final ts = _tileset;
    final image = widget.image;
    final zoom = widget.zoom;
    final hasAnimation = ts.tiles.values.any((t) => t.isAnimated);
    // An image still loading, or tiles that animate.
    _keepTicking((image == null && ts.image.isNotEmpty) || hasAnimation);
    final width = (image?.width ?? ts.imageWidth) * zoom;
    final height = (image?.height ?? ts.imageHeight) * zoom;
    return SignalBuilder<jge.TileStamp?>(
      signal: widget.session.scope.tiles.stamp,
      builder: (context, stamp, _) => SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        // The drag picks tiles: it is not the list's to scroll.
        child: GestureDetector(
          onVerticalDragStart: (_) {},
          onVerticalDragUpdate: (_) {},
          onHorizontalDragStart: (_) {},
          onHorizontalDragUpdate: (_) {},
          child: Listener(
            onPointerDown: _down,
            onPointerMove: _move,
            onPointerUp: (_) => _up(),
            onPointerCancel: (_) => setState(() {
              _dragStart = null;
              _dragEnd = null;
            }),
            onPointerSignal: (e) {
              if (e is PointerScrollEvent &&
                  HardwareKeyboard.instance.isControlPressed) {
                TilesetPalettePanel._zoomBy(
                  widget.session,
                  e.scrollDelta.dy < 0 ? 1 : -1,
                );
              }
            },
            child: CustomPaint(
              size: Size(width.toDouble(), height.toDouble()),
              painter: _TilesetPainter(
                tileset: ts,
                image: image,
                zoom: zoom,
                chosen: _chosen(stamp),
                drag: _dragStart == null
                    ? null
                    : (_dragStart!, _dragEnd ?? _dragStart!),
                clockMs: widget.clockMs,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The brush a block of a tileset makes, from tile column/row [a] to [b]:
/// laid out on the map as it is in the tileset, the pointer at its middle.
jge.TileStamp blockStamp(
  jge.MapGeometry g,
  (int, int) a,
  (int, int) b,
  int Function(int col, int row) cellOf,
) {
  final c0 = a.$1 < b.$1 ? a.$1 : b.$1;
  final c1 = a.$1 < b.$1 ? b.$1 : a.$1;
  final r0 = a.$2 < b.$2 ? a.$2 : b.$2;
  final r1 = a.$2 < b.$2 ? b.$2 : a.$2;
  if (c0 == c1 && r0 == r1) return jge.TileStamp.single(cellOf(c0, r0));
  final store = jge.TileChunkStore();
  final coords = <jge.TileCoord>[];
  for (var r = r0; r <= r1; r++) {
    for (var c = c0; c <= c1; c++) {
      store.setCell(c - c0, r - r0, cellOf(c, r));
      coords.add(jge.TileCoord(c - c0, r - r0));
    }
  }
  return jge.TileStamp.capture(store, coords, g);
}

class _ZoomBar extends StatelessWidget {
  const _ZoomBar({required this.zoom, required this.onZoom});

  final double zoom;
  final ValueChanged<int> onZoom;

  @override
  Widget build(BuildContext context) => Container(
    height: 24,
    padding: const EdgeInsets.symmetric(horizontal: 6),
    decoration: BoxDecoration(
      border: Border(top: BorderSide(color: EditorTheme.border)),
    ),
    child: Row(
      children: [
        Expanded(
          child: Text(
            'Ctrl+click: random set',
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 10, color: EditorTheme.textMuted),
          ),
        ),
        _SmallButton(
          icon: Icons.remove,
          tooltip: 'Smaller',
          onTap: () => onZoom(-1),
        ),
        SizedBox(
          width: 38,
          child: Text(
            '${(zoom * 100).round()}%',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 10, color: EditorTheme.textSecondary),
          ),
        ),
        _SmallButton(
          icon: Icons.add,
          tooltip: 'Larger',
          onTap: () => onZoom(1),
        ),
      ],
    ),
  );
}

class _SmallButton extends StatelessWidget {
  const _SmallButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: tooltip,
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(3),
      child: Padding(
        padding: const EdgeInsets.all(5.5),
        child: Icon(icon, size: 13, color: EditorTheme.textSecondary),
      ),
    ),
  );
}

class _TilesetPainter extends CustomPainter {
  _TilesetPainter({
    required this.tileset,
    required this.image,
    required this.zoom,
    required this.chosen,
    required this.drag,
    required this.clockMs,
  });

  final jge.TilesetData tileset;
  final ui.Image? image;
  final double zoom;
  final Set<int> chosen;
  final ((int, int), (int, int))? drag;
  final int clockMs;

  @override
  void paint(Canvas canvas, Size size) {
    final ts = tileset;
    canvas
      ..save()
      ..scale(zoom);
    final img = image;
    final pixels = Paint()..filterQuality = FilterQuality.none;
    if (img != null) {
      canvas.drawImage(img, Offset.zero, pixels);
    }
    final grid = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0
      ..color = const Color(0x33FFFFFF);
    final marker = Paint()..color = const Color(0xFFFFB74D);
    for (var id = 0; id < ts.tileCount; id++) {
      final r = ts.sourceRect(id);
      final def = ts.tile(id);
      if (img != null && def != null && def.isAnimated) {
        canvas.drawImageRect(
          img,
          ts.sourceRect(def.frameAt(id, clockMs)),
          r,
          pixels,
        );
        final s = r.width / 5;
        canvas.drawPath(
          Path()
            ..moveTo(r.right - s, r.top)
            ..lineTo(r.right, r.top)
            ..lineTo(r.right, r.top + s)
            ..close(),
          marker,
        );
      }
      canvas.drawRect(r, grid);
    }
    final pick = Paint()
      ..color = EditorTheme.primaryBright.withValues(alpha: 0.28);
    final edge = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2 / zoom
      ..color = EditorTheme.primaryBright;
    for (final id in chosen) {
      if (!ts.contains(id)) continue;
      final r = ts.sourceRect(id);
      canvas
        ..drawRect(r, pick)
        ..drawRect(r, edge);
    }
    final d = drag;
    if (d != null && ts.columns > 0) {
      final a = ts.sourceRect(d.$1.$2 * ts.columns + d.$1.$1);
      final b = ts.sourceRect(d.$2.$2 * ts.columns + d.$2.$1);
      canvas.drawRect(a.expandToInclude(b), edge..color = Colors.white);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_TilesetPainter old) => true;
}

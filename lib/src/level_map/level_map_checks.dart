import 'package:just_game_engine/just_game_engine.dart' as jge;

import 'package:just_editor_core/host.dart';

import '../problems/scene_checks.dart';

/// The checks of a scene's Level Map: tiles that cannot be drawn or
/// collide as painted, and map files the game would not find.
abstract final class LevelMapChecks {
  /// Tile maps, tilesets and tileset images the game would not find,
  /// because `pubspec.yaml` does not ship them: the editor reads the
  /// project's files, the game only what the asset bundle holds.
  static List<SceneProblem> unshippedTileAssets(ValidationContext context) {
    final shipped = SceneChecks.shippedAssets(context);
    if (shipped == null) return const [];
    final out = <SceneProblem>[];
    final seen = <String>{};
    void check(jge.Entity entity, String path, String what) {
      if (path.isEmpty || jge.TileAssets.isVirtual(path) || !seen.add(path)) {
        return;
      }
      // A package's asset ships when the package is a dependency and its
      // own pubspec lists the folder.
      final package = PackageAssetPaths.packageOf(path);
      if (package != null) {
        if (context.packages.ships(path) ?? true) return;
        final known = context.packages.packages.containsKey(package);
        out.add(
          SceneProblem(
            entity: entity,
            message:
                '${_nameOf(entity)} uses $what "$path", which the game will '
                'not find.',
            hint: known
                ? 'Package "$package" does not ship that folder: add it '
                      'under flutter: assets: in the package\'s pubspec.yaml.'
                : '"$package" is not a dependency of this project: install '
                      'it from the Asset Store.',
          ),
        );
        return;
      }
      if (SceneChecks.isShipped(path, shipped)) return;
      final folder = path.contains('/')
          ? path.substring(0, path.lastIndexOf('/') + 1)
          : path;
      out.add(
        SceneProblem(
          entity: entity,
          message:
              '${_nameOf(entity)} uses $what "$path", which pubspec.yaml does '
              'not ship: the game will not find it.',
          hint: 'Add "- $folder" under flutter: assets: in pubspec.yaml.',
        ),
      );
    }

    for (final entity in context.world.query([jge.LevelMapComponent])) {
      final c = entity.getComponent<jge.LevelMapComponent>()!;
      if (c.usesFile) check(entity, c.mapPath.trim(), 'the map file');
      final data = c.usesFile
          ? (context.scope.context.tiles.loadedMap(c.mapPath.trim()) ??
                c.runtime?.base)
          : c.inline;
      if (data == null) continue;
      for (final path in data.tilesets.whereType<String>()) {
        // Built in, or inside a Tiled map: no file of its own to ship.
        if (jge.TileAssets.isVirtual(path)) continue;
        check(entity, path, 'the tileset');
        final image = context.readJson(path)?['image'];
        if (image is String) check(entity, image, 'the image');
      }
    }
    return out;
  }

  /// Tile maps whose tiles cannot be drawn or collide as painted: a missing
  /// tileset, tiles past the end of theirs (a tileset re-cut smaller),
  /// collision of a kind nobody registered, a turned or scaled map, and
  /// terrains that lack combinations a terrain brush will need.
  static List<SceneProblem> levelMaps(ValidationContext context) {
    final out = <SceneProblem>[];
    final maps = [
      for (final e in context.world.query([jge.LevelMapComponent]))
        if (!e.hasComponent<jge.GeneratedEntityComponent>()) e,
    ];
    if (maps.length > 1) {
      final primary = jge.LevelMaps.primaryEntity(context.world);
      for (final extra in maps) {
        // A piece cut out of one of its layers is part of it, not a rival.
        if (extra == primary || jge.LevelMaps.isPiece(context.world, extra)) {
          continue;
        }
        out.add(
          SceneProblem(
            entity: extra,
            message:
                '${_nameOf(extra)} is a second map: a scene has one, the '
                '${jge.LevelMaps.primaryName}. It still draws and collides, '
                'but the tools paint ${_nameOf(primary!)}.',
            hint:
                'Move its layers into ${_nameOf(primary)}, or keep it in a '
                'file of its own.',
          ),
        );
      }
    }
    // What is on a map layer: under a map, one that has the layer.
    for (final e in context.world.query([jge.LayerComponent])) {
      if (e.getComponent<jge.LayerComponent>()!.mapLayer == null) continue;
      final owner = jge.LevelMaps.ownerOf(context.world, e);
      if (owner == null) {
        out.add(
          SceneProblem(
            entity: e,
            message:
                '${_nameOf(e)} names a map layer but is not on a map: it '
                'draws as any entity does.',
            hint: 'Drag it onto a layer of the Level Map in the scene tree.',
          ),
        );
      } else if (jge.LevelMaps.memberLayer(context.world, e) == null) {
        out.add(
          SceneProblem(
            entity: e,
            message:
                '${_nameOf(e)} is on a layer ${_nameOf(owner)} no longer '
                'has: it draws as any entity does.',
            hint: 'Drag it onto one of the map\'s layers in the scene tree.',
          ),
        );
      }
    }
    for (final entity in maps) {
      final c = entity.getComponent<jge.LevelMapComponent>()!;
      final name = _nameOf(entity);
      final t = entity.getComponent<jge.TransformComponent>();
      if (t != null && (t.angle != 0 || t.scale.x != 1 || t.scale.y != 1)) {
        out.add(
          SceneProblem(
            entity: entity,
            message:
                '$name: a level map is not turned or scaled with its entity.',
            hint: 'Set its rotation to 0 and its scale to 1.',
          ),
        );
      }
      final data = c.usesFile
          ? (context.scope.context.tiles.loadedMap(c.mapPath.trim()) ??
                c.runtime?.base)
          : c.inline;
      if (data == null) continue;
      if (data.layers.isEmpty) {
        out.add(
          SceneProblem(
            entity: entity,
            message: '$name has no layers to paint on.',
            hint: 'Add one in the Level Designer\'s LAYERS panel.',
          ),
        );
      }
      final tilesets = <int, jge.TilesetData?>{};
      for (var slot = 0; slot < data.tilesets.length; slot++) {
        final path = data.tilesets[slot];
        if (path == null) continue;
        if (!jge.TileAssets.isVirtual(path) && !context.fileExists(path)) {
          out.add(
            SceneProblem(
              severity: ProblemSeverity.error,
              entity: entity,
              message: '$name uses the tileset "$path", which does not exist.',
              hint:
                  'Restore it from .editor_trash/, or remove it from the map.',
            ),
          );
          continue;
        }
        // Not a file: loaded as it is — a built-in tileset, or one inside
        // a Tiled map. A file: as on disk, made once while it is unchanged.
        final tiles = context.scope.context.tiles;
        final json = jge.TileAssets.isVirtual(path)
            ? null
            : context.readJson(path);
        tilesets[slot] = json == null
            ? tiles.loadedTileset(path)
            : (_tilesetFromJson[json] ??= jge.TilesetData.fromJson(json));
      }
      // Tiles no tileset can draw, counted per layer — again only when the
      // layer's cells or the tilesets changed since the last run: a big
      // map has hundreds of thousands of cells, and the checks run every
      // second or so while it is painted.
      for (final layer in data.layers) {
        final (:orphans, :pastEnd) = _countCells(layer, data, tilesets);
        if (orphans > 0) {
          out.add(
            SceneProblem(
              severity: ProblemSeverity.error,
              entity: entity,
              message:
                  '$name / ${layer.name}: $orphans tile${orphans == 1 ? '' : 's'} '
                  'from a tileset the map no longer has.',
              hint: 'Erase them, or add the tileset back.',
            ),
          );
        }
        if (pastEnd > 0) {
          out.add(
            SceneProblem(
              severity: ProblemSeverity.error,
              entity: entity,
              message:
                  '$name / ${layer.name}: $pastEnd tile${pastEnd == 1 ? '' : 's'} '
                  'past the end of their tileset — was its image cut smaller?',
              hint: 'Re-cut the tileset to its old size, or repaint them.',
            ),
          );
        }
      }
      for (final MapEntry(key: slot, value: ts) in tilesets.entries) {
        if (ts == null) continue;
        final label = ts.name.isEmpty ? data.tilesets[slot]! : ts.name;
        final kinds = <String>{};
        var badShapes = 0;
        for (final def in ts.tiles.values) {
          final collision = def.collision;
          if (collision == null) continue;
          if (context.scope.context.collisionKinds.byId(collision.kind) ==
              null) {
            kinds.add(collision.kind);
          }
          for (final shape in collision.shapes) {
            if (jge.PolygonDecompose.convexPieces(shape.outline()).isEmpty) {
              badShapes++;
            }
          }
        }
        if (kinds.isNotEmpty) {
          out.add(
            SceneProblem(
              entity: entity,
              message:
                  'Tileset "$label" uses collision kind${kinds.length == 1 ? '' : 's'} '
                  '${kinds.map((k) => '"$k"').join(', ')} that this game does '
                  'not register; they collide as solid.',
              hint:
                  'Register them with MapCollisionKinds, or pick another kind.',
            ),
          );
        }
        if (badShapes > 0) {
          out.add(
            SceneProblem(
              entity: entity,
              message:
                  'Tileset "$label" has $badShapes collision shape'
                  '${badShapes == 1 ? '' : 's'} with no area; they do nothing.',
              hint: 'Redraw them in the Tileset Editor.',
            ),
          );
        }
        for (final set in ts.wangSets) {
          final missing = _missingTerrainCombinations(set);
          if (missing > 0) {
            out.add(
              SceneProblem(
                entity: entity,
                message:
                    'Terrain "${set.name}" in "$label" lacks $missing '
                    'combination${missing == 1 ? '' : 's'} of its corners or edges; '
                    'the terrain brush will use the nearest tile there.',
                hint:
                    'Assign more tiles in the Tileset Editor, or allow flips '
                    'and turns there.',
              ),
            );
          }
        }
      }
    }
    return out;
  }

  // The tileset each decoded file makes, made once per decoding (which
  // the context keeps while the file is unchanged).
  static final Expando<jge.TilesetData> _tilesetFromJson = Expando();

  // Each layer's last count, by its cells.
  static final Expando<_CellCount> _cellCounts = Expando();

  /// Tiles of [layer] from a slot [data] no longer has (orphans), and past
  /// the end of their tileset; counted again only when the cells or the
  /// tilesets are not what they were at the last count.
  static ({int orphans, int pastEnd}) _countCells(
    jge.MapLayerData layer,
    jge.LevelMapData data,
    Map<int, jge.TilesetData?> tilesets,
  ) {
    final cells = layer.cells;
    final paths = List<String?>.of(data.tilesets);
    final sets = [for (var i = 0; i < paths.length; i++) tilesets[i]];
    final revisions = [for (final ts in sets) ts?.revision];
    final last = _cellCounts[cells];
    if (last != null && last.matches(cells.revision, paths, sets, revisions)) {
      return (orphans: last.orphans, pastEnd: last.pastEnd);
    }
    var orphans = 0;
    var pastEnd = 0;
    for (final (_, _, cell) in cells.cells) {
      final slot = jge.TileCell.slotOf(cell);
      if (slot >= paths.length || paths[slot] == null) {
        orphans++;
        continue;
      }
      final ts = sets[slot];
      if (ts != null && !ts.contains(jge.TileCell.localIdOf(cell))) {
        pastEnd++;
      }
    }
    _cellCounts[cells] = _CellCount(
      cells.revision,
      paths,
      sets,
      revisions,
      orphans,
      pastEnd,
    );
    return (orphans: orphans, pastEnd: pastEnd);
  }

  /// How many of a two-or-more-colour Wang set's combinations no tile has
  /// (corner and edge sets; a mixed set's 8-slot space is too big to ask
  /// for in full, so it is not checked).
  static int _missingTerrainCombinations(jge.WangSetData set) {
    if (set.type == jge.WangType.mixed || set.wangIds.isEmpty) return 0;
    final colors = set.colors.length;
    if (colors < 1) return 0;
    // One terrain (a road) meets nothing: 0 is one of its values. Two or
    // more meet each other and nothing else.
    final values = colors == 1
        ? const [0, 1]
        : [for (var c = 1; c <= colors; c++) c];
    final slots = set.slots;
    final have = <String>{
      for (final id in set.wangIds.values)
        [for (final s in slots) id[s]].join(','),
    };
    var missing = 0;
    final total = _pow(values.length, slots.length);
    for (var n = 0; n < total; n++) {
      var k = n;
      final combo = <int>[];
      for (var i = 0; i < slots.length; i++) {
        combo.add(values[k % values.length]);
        k ~/= values.length;
      }
      if (!have.contains(combo.join(','))) missing++;
    }
    return missing;
  }

  static int _pow(int base, int exp) {
    var r = 1;
    for (var i = 0; i < exp; i++) {
      r *= base;
    }
    return r;
  }

  static String _nameOf(jge.Entity e) => e.name ?? 'Entity ${e.id}';
}

/// A layer's last count of tiles no tileset draws, and what it was made
/// against.
class _CellCount {
  _CellCount(
    this.revision,
    this.paths,
    this.sets,
    this.setRevisions,
    this.orphans,
    this.pastEnd,
  );

  final int revision;
  final List<String?> paths;
  final List<jge.TilesetData?> sets;
  final List<int?> setRevisions;
  final int orphans;
  final int pastEnd;

  bool matches(
    int revision,
    List<String?> paths,
    List<jge.TilesetData?> sets,
    List<int?> setRevisions,
  ) {
    if (revision != this.revision || paths.length != this.paths.length) {
      return false;
    }
    for (var i = 0; i < paths.length; i++) {
      if (paths[i] != this.paths[i] ||
          !identical(sets[i], this.sets[i]) ||
          setRevisions[i] != this.setRevisions[i]) {
        return false;
      }
    }
    return true;
  }
}

import 'dart:async';
import 'dart:convert';
import 'dart:ui';

import 'package:just_editor_core/io.dart';
import 'package:just_game_engine/just_game_engine.dart';

import 'package:just_editor_core/host.dart';
import 'tile_commands.dart';

/// A map a tile tool can edit, and where it is.
class LevelMapTarget {
  LevelMapTarget({
    required this.entity,
    required this.component,
    required this.data,
    this.path,
  });

  final Entity entity;
  final LevelMapComponent component;

  /// The map itself — what edits change.
  final LevelMapData data;

  /// The file it is kept in, or null for a map in the scene.
  final String? path;

  bool get isFile => path != null;

  /// A Tiled map named directly: shown, not edited — convert it first.
  bool get isReadOnly => _isTiledFile(path);

  LevelMapRef get ref =>
      LevelMapRef(entityId: entity.id, path: path, entityName: entity.name);

  /// The map's grid, kept current by the running map when there is one.
  MapGeometry get geometry =>
      component.runtime?.geometry ?? MapGeometry.of(data);

  /// Where the map's origin is in the world.
  Offset get origin {
    final p = entity.getComponent<TransformComponent>()?.position;
    return p == null ? Offset.zero : Offset(p.x, p.y);
  }

  /// Where [layer] is drawn: the map's origin, the layer's offset, and how
  /// far its parallax has it lag behind [camera]. What turns a point of the
  /// layer into a point on screen as the layer is drawn now.
  Offset layerShift(MapLayerData layer, Offset? camera) {
    final o = origin;
    var shift = o + Offset(layer.offsetX, layer.offsetY);
    if (camera != null && (layer.parallaxX != 1 || layer.parallaxY != 1)) {
      final rel = camera - o;
      shift += Offset(
        rel.dx * (1 - layer.parallaxX),
        rel.dy * (1 - layer.parallaxY),
      );
    }
    return shift;
  }

  /// [world] in [layer]'s own pixels.
  Offset toLocal(MapLayerData layer, Offset world) =>
      world - origin - Offset(layer.offsetX, layer.offsetY);

  /// The cell of [layer] under [world].
  TileCoord cellAt(MapLayerData layer, Offset world) =>
      geometry.cellAt(toLocal(layer, world));

  /// The tileset in [slot], as the running map loaded it.
  TilesetData? tilesetAt(int slot) =>
      component.runtime?.tilesetAt(slot) ??
      (slot >= 0 && slot < data.tilesets.length && data.tilesets[slot] != null
          ? entity.world?.context.tiles.loadedTileset(data.tilesets[slot]!)
          : null);
}

/// Whether [path] is a Tiled map (`.tmx`, `.tmj`): read by the editor,
/// never written by it — the editor's own map JSON over one would leave a
/// file neither Tiled nor the engine can open.
bool _isTiledFile(String? path) {
  final p = path?.trim().toLowerCase();
  return p != null && (p.endsWith('.tmx') || p.endsWith('.tmj'));
}

/// The tile maps the editor edits: in the scene, or in their own files.
///
/// A map in the scene is its component's `inline` data, saved with the
/// scene. A `.map.json` is loaded once, edited in place — the running
/// map draws from the same object, so an edit shows at once — and written
/// back when the scene is saved: one Ctrl+S saves both, and the scene's
/// unsaved mark covers both.
class LevelMapDocuments {
  LevelMapDocuments({
    required World Function() world,
    required this.sceneState,
    String? projectRoot,
  }) : _world = world,
       projectRoot = (projectRoot ?? Directory.current.path).replaceAll(
         r'\',
         '/',
       );

  final World Function() _world;
  final EditorSceneState sceneState;

  /// Where project-relative paths are resolved.
  final String projectRoot;

  World get world => _world();

  /// The edited engine's tilesets and map files (`world.context.tiles`).
  TileAssets get tiles => world.context.tiles;

  /// Map files edited since they were last saved.
  final Signal<Set<String>> dirtyPaths = Signal(
    const {},
    debugLabel: 'tileDirtyPaths',
  );

  /// Bumped on every edit to any map, for whatever shows one.
  final Signal<int> revision = Signal(0, debugLabel: 'tileRevision');

  bool get hasDirty => dirtyPaths.value.isNotEmpty;

  /// The map on [entity], if it has one that is loaded; starts loading a
  /// map file that is not.
  LevelMapTarget? resolve(Entity? entity) {
    if (entity == null || !entity.isAlive) return null;
    final c = entity.getComponent<LevelMapComponent>();
    if (c == null) return null;
    if (c.usesFile) {
      final path = c.mapPath.trim();
      final data = tiles.loadedMap(path) ?? c.runtime?.base;
      if (data == null) {
        unawaited(tiles.map(path).then<void>((_) => _bump(), onError: (_) {}));
        return null;
      }
      return LevelMapTarget(
        entity: entity,
        component: c,
        data: data,
        path: path,
      );
    }
    final data = c.inline;
    if (data == null) return null;
    return LevelMapTarget(entity: entity, component: c, data: data);
  }

  /// The map [ref] names now, or null when it is gone.
  ///
  /// An entity undone and redone comes back under a new id, so the entity
  /// is found by its name — names are unique in a scene, and the redone
  /// one keeps it — when the id is gone or now belongs to something else.
  /// A map that cannot be found is null, and the step does nothing: guessing
  /// (the scene's first map) wrote one map's cells into another.
  LevelMapData? dataFor(LevelMapRef ref) {
    final path = ref.path;
    if (path != null) return tiles.loadedMap(path);
    return mapEntityOf(ref)?.getComponent<LevelMapComponent>()!.inline;
  }

  /// The entity carrying the map [ref] names: by its id while that is
  /// still it, else by its name. Null when there is none.
  Entity? mapEntityOf(LevelMapRef ref) =>
      findMapEntity(world, entityId: ref.entityId, entityName: ref.entityName);

  /// The live entity with a [LevelMapComponent] that is [entityId] — and
  /// called [entityName], when given — else the one called [entityName].
  static Entity? findMapEntity(
    World world, {
    required int entityId,
    String? entityName,
  }) {
    bool isMap(Entity? e) =>
        e != null && e.isAlive && e.hasComponent<LevelMapComponent>();
    final own = world.getEntity(entityId);
    if (isMap(own) && (entityName == null || own!.name == entityName)) {
      return own;
    }
    if (entityName == null) return null;
    for (final e in world.query([LevelMapComponent])) {
      if (isMap(e) && e.name == entityName) return e;
    }
    return null;
  }

  /// Something changed in the map [ref] names. A Tiled map's file is
  /// never marked to be saved: the editor does not write one.
  void markEdited(LevelMapRef ref) {
    final path = ref.path;
    if (path != null &&
        !_isTiledFile(path) &&
        !dirtyPaths.value.contains(path)) {
      dirtyPaths.value = {...dirtyPaths.value, path};
    }
    sceneState.markDirty();
    _bump();
  }

  void _bump() => revision.value = revision.value + 1;

  /// [from] was renamed [to] on disk, and the files naming it rewritten:
  /// what is loaded names it the new way too. A map file keeps its unsaved
  /// edits under its new name. Returns how many places changed.
  int renamed(String from, String to) {
    var changed = 0;
    final moved = tiles.loadedMap(from);
    if (moved != null) {
      tiles.putMap(to, moved);
      if (dirtyPaths.value.contains(from)) {
        dirtyPaths.value = {
          for (final p in dirtyPaths.value) p == from ? to : p,
        };
      }
    }
    if (from.toLowerCase().endsWith('.tileset.json') || moved != null) {
      tiles.evict(from);
    }
    for (final e in world.query([LevelMapComponent])) {
      final c = e.getComponent<LevelMapComponent>()!;
      final data = c.usesFile ? tiles.loadedMap(c.mapPath.trim()) : c.inline;
      if (data != null) {
        for (var i = 0; i < data.tilesets.length; i++) {
          if (data.tilesets[i] != from) continue;
          data.tilesets[i] = to;
          data.touch();
          changed++;
        }
        // A layer drawn through a 2-D material.
        for (final layer in data.layers) {
          if (layer.material != from) continue;
          layer.material = to;
          data.touch();
          changed++;
        }
      }
      for (final ts in c.runtime?.tilesets ?? const <TilesetData?>[]) {
        if (ts == null || ts.image != from) continue;
        ts
          ..image = to
          ..touch();
        changed++;
      }
    }
    if (changed > 0 || moved != null) _bump();
    return changed;
  }

  int _assetsSeen = 0;

  /// Bumps [revision] when a map's tilesets or images have been (re)loaded
  /// — a tileset saved in the Tileset Editor — so what shows them draws
  /// again. Cheap; called every frame.
  void pollAssets() {
    var seen = tiles.revision;
    for (final e in world.query([LevelMapComponent])) {
      seen = Object.hash(
        seen,
        e.getComponent<LevelMapComponent>()?.runtime?.assetsRevision ?? -1,
      );
    }
    if (seen == _assetsSeen) return;
    _assetsSeen = seen;
    _bump();
  }

  /// Writes every edited map file. Called when the scene is saved. A
  /// Tiled map's file is left as it is.
  ///
  /// Each file is marked saved as it is written — one edited again while
  /// the save went on stays unsaved — and one that cannot be written stays
  /// unsaved and is returned, with why, by path; the rest are still written.
  Future<Map<String, Object>> saveDirty() async {
    final failed = <String, Object>{};
    for (final path in dirtyPaths.value.toList()) {
      final data = tiles.loadedMap(path);
      if (data == null || _isTiledFile(path)) {
        _markSaved(path);
        continue;
      }
      final revision = data.revision;
      try {
        await writeMap(path, data);
      } on Object catch (error) {
        failed[path] = error;
        continue;
      }
      // Edited while it was being written: what is on disk is older.
      if (data.revision == revision) _markSaved(path);
    }
    return failed;
  }

  void _markSaved(String path) {
    if (!dirtyPaths.value.contains(path)) return;
    dirtyPaths.value = {...dirtyPaths.value}..remove(path);
  }

  /// Throws away every edit to a map file that was not saved: each is read
  /// again from disk the next time it is drawn. What a scene closed without
  /// saving, or left for another, does with the maps it was editing — their
  /// edits live in the engine's shared map cache, and the next scene's save
  /// would otherwise write them.
  void discardUnsaved() {
    final paths = dirtyPaths.value;
    if (paths.isEmpty) return;
    dirtyPaths.value = const {};
    for (final path in paths) {
      tiles.evict(path);
    }
    for (final system in world.systems) {
      if (system is! LevelMapSystem) continue;
      for (final path in paths) {
        system.reload(path);
      }
    }
    _bump();
  }

  /// Writes [data] to the project file [path], whole or not at all.
  /// Refuses a Tiled map's file (`.tmx`, `.tmj`) with a
  /// [FileSystemException]: the editor's map JSON would replace the Tiled
  /// map.
  Future<void> writeMap(String path, LevelMapData data) async {
    if (_isTiledFile(path)) {
      throw FileSystemException(
        'A Tiled map is not written by the editor: convert it first',
        path,
      );
    }
    final file = PackageAssetPaths.of(projectRoot).file(path);
    await ProjectFiles.writeString(
      file.path,
      const JsonEncoder.withIndent('  ').convert(data.toJson()),
    );
  }

  /// Whether the project file [path] is there.
  bool exists(String path) =>
      PackageAssetPaths.of(projectRoot).file(path).existsSync();

  /// Moves [entity]'s map out of the scene into [path], which the entity
  /// then names. One undo step; the file stays written either way.
  ///
  /// Never over another file: throws a [FileSystemException] when [path] is
  /// taken — by another scene's map, say, which would then show this one —
  /// and an [ArgumentError] when it leaves the project.
  Future<EditorCommand?> extractToAsset(Entity entity, String path) async {
    final c = entity.getComponent<LevelMapComponent>();
    final data = c?.inline;
    if (c == null || data == null) return null;
    if (!ProjectFiles.isContained(path)) {
      throw ArgumentError.value(path, 'path', 'is outside the project');
    }
    if (exists(path) || tiles.loadedMap(path) != null) {
      throw FileSystemException('There is a map there already', path);
    }
    await writeMap(path, data);
    tiles.putMap(path, data);
    final command = MapSourceCommand(
      label: 'Move map to $path',
      docs: this,
      entityId: entity.id,
      entityName: entity.name,
      before: (path: '', inline: data.toJson()),
      after: (path: path, inline: null),
    )..redo();
    return command;
  }

  /// A free path for a map file named after [name] in [folder]: the name
  /// made safe for a file (letters, digits, `_` and `-`), `_2`, `_3`… added
  /// while one is taken.
  String freeMapPath(String folder, String name) {
    final safe = name
        .trim()
        .replaceAll(RegExp('[^A-Za-z0-9_-]+'), '_')
        .replaceAll(RegExp('^_+|_+\$'), '');
    final stem = safe.isEmpty ? 'map' : safe;
    for (var n = 1; ; n++) {
      final path = '$folder/$stem${n == 1 ? '' : '_$n'}${LevelMapFiles.suffix}';
      if (!exists(path) && tiles.loadedMap(path) == null) return path;
    }
  }

  void dispose() {
    dirtyPaths.dispose();
    revision.dispose();
  }

  /// Brings [entity]'s map file into the scene; the file is left as it
  /// is. One undo step.
  EditorCommand? embed(Entity entity) {
    final c = entity.getComponent<LevelMapComponent>();
    if (c == null || !c.usesFile) return null;
    final path = c.mapPath.trim();
    final data = tiles.loadedMap(path) ?? c.runtime?.base;
    if (data == null) return null;
    return MapSourceCommand(
      label: 'Keep map in the scene',
      docs: this,
      entityId: entity.id,
      entityName: entity.name,
      before: (path: path, inline: null),
      after: (path: '', inline: data.toJson()),
    )..redo();
  }
}

/// Where a map is kept: moved between the scene and a file.
class MapSourceCommand extends EditorCommand {
  MapSourceCommand({
    required this.label,
    required this.docs,
    required this.entityId,
    this.entityName,
    required this.before,
    required this.after,
  });

  @override
  final String label;
  final LevelMapDocuments docs;
  final int entityId;

  /// The map entity's name, which an undo and redo keep while its id
  /// changes; found by it when [entityId] is no longer the map's.
  final String? entityName;
  final ({String path, Map<String, dynamic>? inline}) before;
  final ({String path, Map<String, dynamic>? inline}) after;

  void _apply(({String path, Map<String, dynamic>? inline}) to) {
    final c = LevelMapDocuments.findMapEntity(
      docs.world,
      entityId: entityId,
      entityName: entityName,
    )?.getComponent<LevelMapComponent>();
    if (c == null) return;
    c
      ..mapPath = to.path
      ..inline = to.inline == null ? null : LevelMapData.fromJson(to.inline!);
    docs.sceneState.markDirty();
    docs._bump();
  }

  @override
  void redo() => _apply(after);

  @override
  void undo() => _apply(before);
}

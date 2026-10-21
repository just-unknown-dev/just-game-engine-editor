import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui';

import 'package:just_editor_core/io.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_tiled/just_tiled.dart' as tiled;

import 'package:just_editor_core/host.dart';

/// Reading and writing the project's files, relative to its folder — a
/// seam, so tests need no disk.
class TiledFiles {
  /// Files under [root], read and written on disk; a test passes [read],
  /// [write], [writeBytes] and [exists] to keep them in memory instead.
  /// Each path is relative to [root], `/`-separated.
  TiledFiles({
    required this.root,
    Future<String> Function(String path)? read,
    Future<void> Function(String path, String text)? write,
    Future<void> Function(String path, List<int> bytes)? writeBytes,
    bool Function(String path)? exists,
  }) : _read = read,
       _write = write,
       _writeBytes = writeBytes,
       _exists = exists;

  /// The project folder.
  final String root;

  final Future<String> Function(String path)? _read;
  final Future<void> Function(String path, String text)? _write;
  final Future<void> Function(String path, List<int> bytes)? _writeBytes;
  final bool Function(String path)? _exists;

  /// [path]'s file: a package's own folder for `packages/<name>/…`.
  File _file(String path) => PackageAssetPaths.of(root).file(path);

  /// The text of the file at [path].
  Future<String> read(String path) =>
      _read?.call(path) ?? _file(path).readAsString();

  /// Writes [text] to [path], making its folder when it is missing.
  Future<void> write(String path, String text) async {
    final w = _write;
    if (w != null) return w(path, text);
    final file = _file(path);
    await file.parent.create(recursive: true);
    await file.writeAsString(text);
  }

  /// Writes [bytes] — a picture, say — to [path].
  Future<void> writeBytes(String path, List<int> bytes) async {
    final w = _writeBytes;
    if (w != null) return w(path, bytes);
    final file = _file(path);
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes);
  }

  /// Whether there is a file at [path].
  bool exists(String path) => _exists?.call(path) ?? _file(path).existsSync();
}

class _Provider implements tiled.TsxProvider {
  _Provider(this.files, this.dir);
  final TiledFiles files;
  final String dir;

  @override
  Future<String> getTsx(String source) =>
      files.read(TileAssets.join(dir, source));

  @override
  Future<String> getTemplate(String source) =>
      files.read(TileAssets.join(dir, source));
}

/// A Tiled map read and converted, before anything is written.
class TiledImportPlan {
  /// What [TiledImporter.read] found. Nothing is written until the plan is
  /// given to [TiledImporter.writeMap] or [TiledImporter.writeTilesets].
  TiledImportPlan({
    required this.source,
    required this.result,
    required this.tilesetPaths,
    required this.newTilesets,
    required this.warnings,
  });

  /// The `.tmx` or `.tmj` read.
  final String source;

  /// What the conversion made. Its map names each tileset by the project
  /// `.tileset.json` it becomes.
  final TiledImport result;

  /// The `.tileset.json` each of the Tiled map's tilesets becomes, by slot;
  /// null for one the engine cannot draw.
  final List<String?> tilesetPaths;

  /// The tilesets to write: those not already in the project.
  final Map<String, TilesetData> newTilesets;

  /// What did not come across, and what was kept rather than overwritten.
  final List<String> warnings;

  /// The level map the Tiled map became ([result]'s).
  LevelMapData get map => result.map;

  /// The file's name without its folder or ending: what things are named
  /// after.
  String get stem => tiledStem(source);
}

/// [path]'s file name without its folder or its (last) ending.
String tiledStem(String path) {
  var name = path.substring(path.lastIndexOf('/') + 1);
  if (LevelMapFiles.isMapFile(name)) return LevelMapFiles.stem(name);
  for (final ending in const ['.tileset.json']) {
    if (name.toLowerCase().endsWith(ending)) {
      return name.substring(0, name.length - ending.length);
    }
  }
  final dot = name.lastIndexOf('.');
  if (dot > 0) name = name.substring(0, dot);
  return name;
}

String _safe(String name) {
  final s = name.trim().replaceAll(RegExp(r'[^A-Za-z0-9_\-]+'), '_');
  return s.isEmpty ? 'tileset' : s;
}

/// Brings Tiled's files into the project: a `.tmx`/`.tmj` map as a level
/// map (in the scene or in a `.map.json`) — its object layers layers of
/// it, their objects entities on them (see [TiledImporter.entities]) — and
/// a `.tsx`/`.tsj` tileset as a `.tileset.json`.
///
/// Tilesets become `.tileset.json` files in [tilesetFolder], named after
/// their TSX (or the map and their name, for one kept inside the map). One
/// already there that was cut from the same picture is used as it is, not
/// overwritten — it may have been edited since; one of another picture
/// (another folder's `terrain.tsx`) is left alone, and this one is named
/// `terrain_2`.
class TiledImporter {
  /// An importer that reads and writes through [files], and writes the
  /// tilesets it makes to [tilesetFolder].
  TiledImporter(this.files, {this.tilesetFolder = 'assets/tilesets'});

  /// Where the Tiled files are read from and the project's written to.
  final TiledFiles files;

  /// The project folder new `.tileset.json` files go in, relative to the
  /// project: `assets/tilesets` unless given another.
  final String tilesetFolder;

  /// Whether [path] is a Tiled map: a `.tmx` or `.tmj` file, in any case.
  static bool isTiledMap(String path) {
    final p = path.toLowerCase();
    return p.endsWith('.tmx') || p.endsWith('.tmj');
  }

  /// Whether [path] is a Tiled tileset: a `.tsx` or `.tsj` file, in any
  /// case.
  static bool isTiledTileset(String path) {
    final p = path.toLowerCase();
    return p.endsWith('.tsx') || p.endsWith('.tsj');
  }

  /// Reads and converts the map at [path].
  Future<TiledImportPlan> read(String path) async {
    final text = await files.read(path);
    final dir = TileAssets.directoryOf(path);
    final provider = _Provider(files, dir);
    final parsed = path.toLowerCase().endsWith('.tmj')
        ? await tiled.TmjParser.parse(text, tsxProvider: provider)
        : await tiled.TileMapParser.parse(text, tsxProvider: provider);
    final stem = tiledStem(path);
    final taken = <String>{};
    String pathFor(tiled.Tileset ts) {
      final name = ts.source != null
          ? _safe(tiledStem(ts.source!))
          : '${_safe(stem)}_${_safe(ts.name)}';
      var candidate = '$tilesetFolder/$name.tileset.json';
      for (var n = 2; !taken.add(candidate); n++) {
        candidate = '$tilesetFolder/${name}_$n.tileset.json';
      }
      return candidate;
    }

    final result = TiledInterop.importMap(
      parsed,
      tilesetPath: (_, ts) => pathFor(ts),
      imagePath: (ts) {
        // Relative to the tileset's own file when it has one.
        final base = ts.source == null
            ? dir
            : TileAssets.directoryOf(TileAssets.join(dir, ts.source!));
        return TileAssets.join(base, ts.imageSource ?? '');
      },
    );
    final warnings = [...result.warnings];
    final paths = [...result.map.tilesets];
    final fresh = <String, TilesetData>{};
    // The names the conversion gave, each slot's own.
    final claimed = {...paths.whereType<String>()};
    for (var i = 0; i < paths.length; i++) {
      final p = paths[i];
      final ts = result.tilesets[i];
      if (p == null || ts == null) continue;
      var candidate = p;
      var n = 2;
      while (true) {
        if (!files.exists(candidate)) {
          fresh[candidate] = ts;
          break;
        }
        if (await _sameTileset(candidate, ts)) {
          warnings.add(
            'Used $candidate as it is: it is already in the project',
          );
          break;
        }
        // Another tileset of the same name: this one beside it.
        do {
          candidate = _numbered(p, n++);
        } while (claimed.contains(candidate));
      }
      if (candidate != p) {
        claimed.add(candidate);
        paths[i] = candidate;
        result.map.tilesets[i] = candidate;
        warnings.add(
          'Saved the tileset as $candidate: $p in the project is another '
          'tileset',
        );
      }
    }
    if (result.images.isNotEmpty) {
      warnings.add(
        '${result.images.length} image layer'
        '${result.images.length == 1 ? ' was' : 's were'} not imported: '
        'place the images as sprites',
      );
    }
    return TiledImportPlan(
      source: path,
      result: result,
      tilesetPaths: paths,
      newTilesets: fresh,
      warnings: warnings,
    );
  }

  /// Whether the project's tileset at [path] is [ts] as converted: cut
  /// from the same picture. False when it cannot be read.
  Future<bool> _sameTileset(String path, TilesetData ts) async {
    try {
      final json = jsonDecode(await files.read(path));
      if (json is! Map<String, dynamic>) return false;
      return TilesetData.fromJson(json).image == ts.image;
    } on Object {
      return false;
    }
  }

  /// [path] (`…/name.tileset.json`) as `…/name_[n].tileset.json`.
  static String _numbered(String path, int n) {
    const ending = '.tileset.json';
    final stem = path.endsWith(ending)
        ? path.substring(0, path.length - ending.length)
        : path;
    return '${stem}_$n$ending';
  }

  /// Writes the tilesets [plan] needs that the project does not have.
  Future<List<String>> writeTilesets(TiledImportPlan plan) async {
    final written = <String>[];
    for (final e in plan.newTilesets.entries) {
      await files.write(e.key, '${_pretty(e.value.toJson())}\n');
      written.add(e.key);
    }
    return written;
  }

  /// Writes [plan]'s map as a `.map.json` at [to], with its tilesets.
  /// Returns every file written.
  Future<List<String>> writeMap(TiledImportPlan plan, String to) async {
    final written = await writeTilesets(plan);
    await files.write(to, '${_pretty(plan.map.toJson())}\n');
    return [...written, to];
  }

  /// Converts the Tiled tileset at [path] to a `.tileset.json` at [to] —
  /// by default beside the others, named after it. Overwrites.
  Future<String> convertTileset(String path, {String? to}) async {
    final text = await files.read(path);
    final ts = path.toLowerCase().endsWith('.tsj')
        ? tiled.TmjParser.parseTileset(text, source: path)
        : tiled.TileMapParser.parseTileset(text, source: path);
    final data = TiledInterop.importTileset(
      ts,
      image: TileAssets.join(
        TileAssets.directoryOf(path),
        ts.imageSource ?? '',
      ),
    );
    if (data == null) {
      throw UnsupportedError(
        '${ts.name} is a collection of separate images; the engine draws '
        'tilesets cut from one image',
      );
    }
    final target =
        to ?? '$tilesetFolder/${_safe(tiledStem(path))}.tileset.json';
    await files.write(target, '${_pretty(data.toJson())}\n');
    return target;
  }

  static String _pretty(Object json) =>
      const JsonEncoder.withIndent('  ').convert(json);

  // ── Into the scene ───────────────────────────────────────────────────────

  /// The entities [plan] becomes with the map's origin at [origin]: the
  /// map, then one per object — a child of the map, on the layer its object
  /// layer became. With [mapPath], the map entity uses that file rather
  /// than keeping the map in the scene.
  ///
  /// Objects go to the first of [mappers] that takes them, else to the
  /// prefab their class names — by its id, name or one of its aliases —
  /// else become a plain entity where they were. [uniqueName] names each
  /// entity; the map is called [mapName] when given.
  static List<EntitySpec> entities(
    TiledImportPlan plan, {
    required Offset origin,
    required SceneCodec codec,
    required String Function(String prefix) uniqueName,
    List<TiledObjectMapper> mappers = const [],
    PrefabRegistry? prefabs,
    String? mapPath,
    String? mapName,
  }) {
    final mapEntity = mapName ?? uniqueName(_safe(plan.stem));
    EntitySpec spec(String name, List<Component> components, {int? mapLayer}) {
      final kept = [
        for (final c in components)
          if (c is! ParentComponent && c is! ChildrenComponent) c,
      ];
      if (mapLayer != null) {
        final layer = kept.whereType<LayerComponent>().firstOrNull;
        if (layer == null) {
          kept.add(LayerComponent(mapLayer: mapLayer));
        } else {
          layer.mapLayer = mapLayer;
        }
      }
      return EntitySpec(
        name: name,
        componentsJson: [for (final c in kept) ?codec.encode(c)],
        codec: codec,
        parentName: mapLayer == null ? null : mapEntity,
      );
    }

    final out = <EntitySpec>[
      spec(mapEntity, [
        TransformComponent(position: Vector3(origin.dx, origin.dy, 0)),
        mapPath == null
            ? LevelMapComponent(inline: plan.map)
            : LevelMapComponent(mapPath: mapPath),
      ]),
    ];
    final ordered = [...mappers]..sort((a, b) => a.order.compareTo(b.order));
    for (final record in plan.result.objects) {
      final info = objectInfo(record, origin);
      final name = uniqueName(
        _safe(
          info.name.isNotEmpty
              ? info.name
              : (info.className.isNotEmpty ? info.className : 'Object'),
        ),
      );
      final layer = record.mapLayerId;
      final mapper = ordered.where((m) => m.matches(info)).firstOrNull;
      if (mapper != null) {
        out.add(spec(name, mapper.build(info), mapLayer: layer));
        continue;
      }
      final prefab = _prefabFor(prefabs, info.className);
      if (prefab != null) {
        final size = info.size.isEmpty ? prefab.defaultSize : info.size;
        final built = prefab.build(info.center, size);
        // Turned as the object was: a prefab builds upright.
        if (info.rotation != 0) {
          built.whereType<TransformComponent>().firstOrNull?.angle =
              info.rotation * math.pi / 180;
        }
        out.add(spec(name, built, mapLayer: layer));
        continue;
      }
      out.add(
        spec(name, [
          TransformComponent(
            position: Vector3(info.center.dx, info.center.dy, 0),
            angle: info.rotation * math.pi / 180,
          ),
        ], mapLayer: layer),
      );
    }
    return out;
  }

  static PrefabDefinition? _prefabFor(
    PrefabRegistry? prefabs,
    String className,
  ) {
    if (prefabs == null || className.isEmpty) return null;
    final wanted = className.toLowerCase();
    for (final p in prefabs.all) {
      final id = p.id.toLowerCase();
      if (id == wanted ||
          id.endsWith('.$wanted') ||
          p.name.toLowerCase() == wanted ||
          p.aliases.any((a) => a.toLowerCase() == wanted)) {
        return p;
      }
    }
    return null;
  }

  /// [record] as a mapper sees it, the map's origin at [origin].
  static TiledObjectInfo objectInfo(TiledObjectRecord record, Offset origin) {
    final o = record.object;
    final size = Size(o.width, o.height);
    final topLeft = origin + record.position;
    // Tiled turns an object about its corner — the top-left, or the
    // bottom-left a tile object hangs from — so its middle is that corner
    // plus half its size, turned with it.
    final half = o.gid != null
        ? Offset(o.width / 2, -o.height / 2)
        : Offset(o.width / 2, o.height / 2);
    final turn = o.rotation * math.pi / 180;
    final c = math.cos(turn), s = math.sin(turn);
    final center = o.isPoint
        ? topLeft
        : topLeft +
              Offset(half.dx * c - half.dy * s, half.dx * s + half.dy * c);
    // A shape's points, which Tiled keeps from the corner, from the middle
    // instead — before the turn, which the entity carries.
    List<Offset>? around(List<Offset>? points) =>
        points == null ? null : [for (final p in points) p - half];
    final props = TiledInterop.importProperties(o.properties);
    return TiledObjectInfo(
      id: o.id,
      name: o.name,
      className: o.type,
      layerName: record.layerName,
      center: center,
      size: size,
      rotation: o.rotation,
      isPoint: o.isPoint,
      isEllipse: o.isEllipse,
      polygon: around(o.polygon),
      polyline: around(o.polyline),
      gid: o.gid,
      properties: {for (final n in props.names) n: props[n]},
    );
  }
}

import 'dart:convert';
import 'dart:io';

import 'package:just_game_engine/just_game_engine.dart' as jge;

import '../assets/package_asset_paths.dart';
import '../scope/editor_scope.dart';
import '../serialization/unknown_components.dart';
import 'physics_3d_checks.dart';
import 'physics_checks.dart';
import 'tag_checks.dart';

export 'physics_checks.dart';
export 'tag_checks.dart';

enum ProblemSeverity { warning, error }

/// A way to put a problem right in one click — `Use "player"`. Each one is
/// an ordinary edit: it goes on the undo stack like any other.
class ProblemFix {
  const ProblemFix({required this.label, required this.apply});

  final String label;
  final void Function() apply;
}

/// Something wrong with the open scene, said in words an author can act on.
class SceneProblem {
  const SceneProblem({
    required this.message,
    this.severity = ProblemSeverity.warning,
    this.entity,
    this.hint,
    this.fixes = const [],
  });

  /// Ways to fix it in one click, best first.
  final List<ProblemFix> fixes;

  final String message;
  final ProblemSeverity severity;

  /// Who it is about; clicking the problem selects it.
  final jge.Entity? entity;

  /// What to do about it.
  final String? hint;
}

/// What a validator looks at. File access goes through here so a check can
/// be tested without a project on disk.
class ValidationContext {
  ValidationContext({
    required this.scope,
    String? projectRoot,
    bool Function(String path)? fileExists,
    String? Function(String path)? readText,
  }) : projectRoot = (projectRoot ?? Directory.current.path).replaceAll(
         r'\',
         '/',
       ),
       _fileExists = fileExists,
       _readText = readText;

  final EditorScope scope;
  final String projectRoot;
  final bool Function(String path)? _fileExists;
  final String? Function(String path)? _readText;

  jge.World get world => scope.world;

  /// Where the project's packages are, for `packages/<name>/…` paths.
  PackageAssetPaths get packages => PackageAssetPaths.of(projectRoot);

  /// Whether the project-relative [path] is a file. A `packages/<name>/…`
  /// path is looked for in that package's folder.
  bool fileExists(String path) =>
      _fileExists?.call(path) ?? packages.file(path).existsSync();

  /// The text of [path], or null when it cannot be read.
  String? readText(String path) {
    if (_readText != null) return _readText(path);
    try {
      return packages.file(path).readAsStringSync();
    } on FileSystemException {
      return null;
    }
  }

  Map<String, dynamic>? readJson(String path) {
    final text = readText(path);
    if (text == null) return null;
    try {
      final json = jsonDecode(text);
      return json is Map<String, dynamic> ? json : null;
    } on FormatException {
      return null;
    }
  }
}

/// One check over the scene. A module adds its own through
/// `EditorModule.validators`.
typedef SceneValidator = List<SceneProblem> Function(ValidationContext context);

/// The checks the editor makes of every scene.
abstract final class BuiltInValidators {
  static const List<SceneValidator> all = [
    missingAssets,
    unresolvedEntityReferences,
    animatorClips,
    timelines,
    camerasWithoutTargets,
    TagChecks.unknownTags,
    TagChecks.spawnPoints,
    TagChecks.unresolvedTargets,
    ...PhysicsChecks.all,
    Physics3DChecks.all,
    drawnWithoutTransform,
    levelMaps,
    unshippedTileAssets,
    unknownComponents,
  ];

  /// The asset paths `pubspec.yaml` lists under `flutter: assets:`, or
  /// null when there is no pubspec to read.
  static List<String>? shippedAssets(ValidationContext context) {
    final text = context.readText('pubspec.yaml');
    if (text == null) return null;
    return PackageAssetPaths.parseAssetEntries(text);
  }

  /// Whether [path] is shipped by one of [assets]: listed itself, or in a
  /// listed folder — directly, as Flutter's asset folders do not reach
  /// into the folders inside them.
  static bool isShipped(String path, List<String> assets) {
    final folder = path.contains('/')
        ? path.substring(0, path.lastIndexOf('/') + 1)
        : '';
    return assets.any((a) => a == path || (a.endsWith('/') && a == folder));
  }

  /// Tile maps, tilesets and tileset images the game would not find,
  /// because `pubspec.yaml` does not ship them: the editor reads the
  /// project's files, the game only what the asset bundle holds.
  static List<SceneProblem> unshippedTileAssets(ValidationContext context) {
    final shipped = shippedAssets(context);
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
      if (isShipped(path, shipped)) return;
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
        // a Tiled map.
        final tiles = context.scope.context.tiles;
        final json = jge.TileAssets.isVirtual(path)
            ? tiles.loadedTileset(path)?.toJson()
            : context.readJson(path);
        tilesets[slot] = json == null
            ? tiles.loadedTileset(path)
            : jge.TilesetData.fromJson(json);
      }
      // Tiles no tileset can draw, counted per layer.
      for (final layer in data.layers) {
        var orphans = 0;
        var pastEnd = 0;
        for (final (_, _, cell) in layer.cells.cells) {
          final slot = jge.TileCell.slotOf(cell);
          if (slot >= data.tilesets.length || data.tilesets[slot] == null) {
            orphans++;
            continue;
          }
          final ts = tilesets[slot];
          if (ts != null && !ts.contains(jge.TileCell.localIdOf(cell))) {
            pastEnd++;
          }
        }
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

  /// Runs [validators] and sorts errors first. A validator that throws is a
  /// problem of its own, not the end of validation.
  static List<SceneProblem> run(
    ValidationContext context,
    Iterable<SceneValidator> validators,
  ) {
    final out = <SceneProblem>[];
    for (final validate in validators) {
      try {
        out.addAll(validate(context));
      } catch (e) {
        out.add(SceneProblem(message: 'A scene check failed: $e'));
      }
    }
    out.sort((a, b) => b.severity.index.compareTo(a.severity.index));
    return out;
  }

  /// Every `assetRef` field that names a file which is not there.
  static List<SceneProblem> missingAssets(ValidationContext context) {
    final out = <SceneProblem>[];
    for (final entity in context.world.entities) {
      for (final component in entity.components) {
        final definition = context.scope.definitions.definitionFor(component);
        if (definition == null) continue;
        for (final field in definition.fields) {
          if (field.kind.id != jge.FieldTypes.assetRef.id) continue;
          final path = field.read(component);
          if (path is! String || path.trim().isEmpty) continue;
          if (context.fileExists(path.trim())) continue;
          out.add(
            SceneProblem(
              severity: ProblemSeverity.error,
              entity: entity,
              message:
                  '${_nameOf(entity)}: ${definition.hints.name ?? definition.type} '
                  'points at "$path", which does not exist.',
              hint: 'Pick the file again, or restore it from .editor_trash/.',
            ),
          );
        }
      }
    }
    return out;
  }

  /// Every `entityRef` field naming an entity (or tag) the scene lacks.
  static List<SceneProblem> unresolvedEntityReferences(
    ValidationContext context,
  ) {
    final names = <String>{};
    final tags = <String>{};
    for (final e in context.world.entities) {
      if (e.name != null) names.add(e.name!);
      tags.addAll(e.tags);
    }
    final out = <SceneProblem>[];
    for (final entity in context.world.entities) {
      for (final component in entity.components) {
        final definition = context.scope.definitions.definitionFor(component);
        if (definition == null) continue;
        for (final field in definition.fields) {
          if (field.kind.id != jge.FieldTypes.entityRef.id) continue;
          final target = field.read(component);
          if (target is! String || target.trim().isEmpty) continue;
          if (names.contains(target) || tags.contains(target)) continue;
          out.add(
            SceneProblem(
              entity: entity,
              message:
                  '${_nameOf(entity)}: ${definition.hints.name ?? definition.type} '
                  'refers to "$target", and nothing in the scene is called that.',
              hint:
                  'Fine if it is spawned when the game starts; otherwise '
                  'rename one or the other.',
            ),
          );
        }
      }
    }
    return out;
  }

  /// An animator graph whose states play clips its sprite's atlas lacks —
  /// the character shows a still frame and never says why.
  /// A timeline that would do nothing, or less than it says: a track bound
  /// to nobody in this scene, a field that is not there, and whatever the
  /// timeline finds wrong with itself.
  static List<SceneProblem> timelines(ValidationContext context) {
    final out = <SceneProblem>[];
    for (final entity in context.world.entities) {
      final player = entity.getComponent<jge.TimelinePlayerComponent>();
      if (player == null) continue;
      final path = player.timelinePath.trim();
      final jge.TimelineAsset asset;
      if (path.isEmpty) {
        final inline = player.inline;
        if (inline == null) continue;
        asset = inline;
      } else {
        final json = context.readJson(path);
        if (json == null) continue; // missingAssets
        asset = jge.TimelineAsset.fromJson(
          json,
          kinds: context.scope.context.trackKinds,
          migrations: context.scope.context.migrations,
        );
      }
      final what = path.isEmpty ? 'its timeline' : path;
      for (final problem in asset.validate()) {
        out.add(
          SceneProblem(
            entity: entity,
            message: '${_nameOf(entity)}, $what: $problem',
          ),
        );
      }
      final nobody = <String>{};
      for (final track in asset.tracks) {
        final bound = track.binding.resolve(
          context.world,
          entity,
          includeInactive: true,
        );
        if (bound == null) {
          if (nobody.add(track.binding.label)) {
            out.add(
              SceneProblem(
                entity: entity,
                message:
                    '${_nameOf(entity)}, $what: nothing in the scene answers '
                    'to ${track.binding.label}, which it animates.',
              ),
            );
          }
          continue;
        }
        if (track is jge.PropertyTrack &&
            jge.PropertyAccess.of(
                  bound,
                  track.component,
                  track.field,
                  track.channel,
                ) ==
                null) {
          out.add(
            SceneProblem(
              severity: ProblemSeverity.error,
              entity: entity,
              message:
                  '${_nameOf(entity)}, $what: ${_nameOf(bound)} has no '
                  '${track.path} to animate.',
              hint:
                  'Add the component, or remove the track in the Timeline '
                  'dock.',
            ),
          );
        }
      }
    }
    return out;
  }

  static List<SceneProblem> animatorClips(ValidationContext context) {
    final out = <SceneProblem>[];
    for (final entity in context.world.entities) {
      final animator = entity.getComponent<jge.AnimatorComponent>();
      final sprite = entity.getComponent<jge.SpriteAnimationComponent>();
      if (animator == null || animator.graphPath.trim().isEmpty) continue;
      if (sprite == null) {
        out.add(
          SceneProblem(
            entity: entity,
            message:
                '${_nameOf(entity)} has an Animator but no Sprite Animation '
                'for it to drive.',
          ),
        );
        continue;
      }
      final graphJson = context.readJson(animator.graphPath.trim());
      final atlasJson = context.readJson(sprite.atlasPath.trim());
      if (graphJson == null || atlasJson == null) continue; // missingAssets
      final graph = jge.AnimatorGraph.fromJson(graphJson);
      final meta = atlasJson['meta'];
      final tags = meta is Map ? meta['frameTags'] : null;
      final clips = <String>{
        if (tags is List)
          for (final t in tags)
            if (t is Map && t['name'] is String) t['name'] as String,
        if (atlasJson['clips'] case final Map legacy) ...legacy.keys.cast(),
      };
      final missing = [
        for (final s in graph.states)
          if (!clips.contains(s.clipName)) s.clipName,
      ];
      if (missing.isEmpty) continue;
      out.add(
        SceneProblem(
          severity: ProblemSeverity.error,
          entity: entity,
          message:
              '${_nameOf(entity)}: the animator plays '
              '${missing.map((c) => '"$c"').join(', ')}, but '
              '${sprite.atlasPath} has '
              '${clips.isEmpty ? 'no clips at all' : 'only ${clips.map((c) => '"$c"').join(', ')}'}.',
          hint:
              'In the sprite editor, tag the frames for each clip with those '
              'names, and save.',
        ),
      );
    }
    return out;
  }

  static List<SceneProblem> camerasWithoutTargets(ValidationContext context) =>
      [
        for (final e in context.world.entities)
          if (e.getComponent<jge.VirtualCameraComponent>() case final camera?
              when camera.follow.isNone &&
                  e.hasComponent<jge.CameraFramingComponent>())
            SceneProblem(
              entity: e,
              message:
                  '${_nameOf(e)} frames a target but follows nothing: it will '
                  'stay where it is.',
              hint: 'Pick an entity or a tag for it to follow.',
            ),
      ];

  /// Components the file names that nothing registered can read. They are
  /// kept and saved back as they were, but the game will refuse the scene
  /// until whatever defines them is registered there too.
  static List<SceneProblem> unknownComponents(ValidationContext context) => [
    for (final e in context.world.entities)
      if (e.getComponent<UnknownComponents>() case final unknown?)
        SceneProblem(
          entity: e,
          severity: ProblemSeverity.error,
          message:
              '${_nameOf(e)} has ${unknown.types.join(', ')}, which nothing '
              'registered can read. It is kept and saved as it was.',
          hint:
              'Register the module or package that defines it — the game '
              'will not load this scene until it does.',
        ),
  ];

  static List<SceneProblem> drawnWithoutTransform(ValidationContext context) =>
      [
        for (final e in context.world.entities)
          if (!e.hasComponent<jge.TransformComponent>() &&
              (e.hasComponent<jge.SpriteComponent>() ||
                  e.hasComponent<jge.SpriteAnimationComponent>() ||
                  e.hasComponent<jge.RenderableComponent>()))
            SceneProblem(
              entity: e,
              message:
                  '${_nameOf(e)} has something to draw but no Transform, so it '
                  'is drawn nowhere.',
              hint: 'Add a Transform.',
            ),
      ];
}

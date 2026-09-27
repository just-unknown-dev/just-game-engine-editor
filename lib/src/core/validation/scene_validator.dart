import 'dart:convert';
import 'dart:io';

import 'package:just_game_engine/just_game_engine.dart' as jge;

import '../scope/editor_scope.dart';

enum ProblemSeverity { warning, error }

/// Something wrong with the open scene, said in words an author can act on.
class SceneProblem {
  const SceneProblem({
    required this.message,
    this.severity = ProblemSeverity.warning,
    this.entity,
    this.hint,
  });

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

  /// Whether the project-relative [path] is a file.
  bool fileExists(String path) =>
      _fileExists?.call(path) ?? File('$projectRoot/$path').existsSync();

  /// The text of [path], or null when it cannot be read.
  String? readText(String path) {
    if (_readText != null) return _readText(path);
    try {
      return File('$projectRoot/$path').readAsStringSync();
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
    drawnWithoutTransform,
    uiScreens,
    levelMaps,
    unshippedTileAssets,
  ];

  /// The asset paths `pubspec.yaml` lists under `flutter: assets:`, or
  /// null when there is no pubspec to read.
  static List<String>? shippedAssets(ValidationContext context) {
    final text = context.readText('pubspec.yaml');
    if (text == null) return null;
    final out = <String>[];
    var inFlutter = false;
    var inAssets = false;
    var assetsIndent = 0;
    for (final raw in text.split('\n')) {
      final line = raw.replaceAll('\r', '');
      final trimmed = line.trim();
      if (trimmed.isEmpty || trimmed.startsWith('#')) continue;
      final indent = line.length - line.trimLeft().length;
      if (indent == 0) {
        inFlutter = trimmed == 'flutter:';
        inAssets = false;
        continue;
      }
      if (!inFlutter) continue;
      if (trimmed == 'assets:') {
        inAssets = true;
        assetsIndent = indent;
        continue;
      }
      if (inAssets && indent <= assetsIndent) inAssets = false;
      if (inAssets && trimmed.startsWith('-')) {
        var entry = trimmed.substring(1).trim();
        if (entry.startsWith('"') || entry.startsWith("'")) {
          entry = entry.substring(1, entry.length - 1);
        }
        out.add(entry);
      }
    }
    return out;
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
          ? (jge.TileAssets.loadedMap(c.mapPath.trim()) ?? c.runtime?.base)
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
      if (t != null && (t.rotation != 0 || t.scale.x != 1 || t.scale.y != 1)) {
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
          ? (jge.TileAssets.loadedMap(c.mapPath.trim()) ?? c.runtime?.base)
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
        final json = jge.TileAssets.isVirtual(path)
            ? jge.TileAssets.loadedTileset(path)?.toJson()
            : context.readJson(path);
        tilesets[slot] = json == null
            ? jge.TileAssets.loadedTileset(path)
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
          if (jge.MapCollisionKinds.byId(collision.kind) == null) {
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
      final tag = e.getComponent<jge.TagComponent>()?.tag;
      if (tag != null) tags.add(tag);
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
        asset = jge.TimelineAsset.fromJson(json);
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
              when camera.followName.trim().isEmpty &&
                  camera.followTag.trim().isEmpty &&
                  e.hasComponent<jge.CameraFramingComponent>())
            SceneProblem(
              entity: e,
              message:
                  '${_nameOf(e)} frames a target but follows nothing: it will '
                  'stay where it is.',
              hint: 'Give it an entity name or a tag to follow.',
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

  /// The interface: actions that go nowhere, screens nobody can use, and
  /// elements outside any canvas.
  ///
  /// What a game registered is only known while that game is running in
  /// the editor, so the checks that need the registries stay quiet when
  /// they are empty — an empty registry means "we cannot tell", not
  /// "nothing is registered".
  static List<SceneProblem> uiScreens(ValidationContext context) {
    final out = <SceneProblem>[];
    final world = context.world;
    final knownBindings = jge.UiBindings.names.toSet();
    final knownActions = jge.UiActions.customNames.toSet();
    final knownWidgets = {for (final w in jge.UiWidgets.all) w.id};

    for (final entity in world.entities) {
      if (!entity.isAlive) continue;
      final canvas = entity.getComponent<jge.UiCanvasComponent>();
      final slot = entity.getComponent<jge.UiSlotComponent>();
      // World-space text and buttons are interface too: what they do and
      // what they read is checked the same way. Only where a thing *sits*
      // is about the screen.
      if (canvas == null && slot == null && !_carriesUi(entity)) continue;
      final name = _nameOf(entity);

      // A slot says "screen space", and outside a canvas that is never
      // drawn, however right it looks in the inspector.
      if (slot != null &&
          canvas == null &&
          _canvasAbove(world, entity) == null) {
        out.add(
          SceneProblem(
            entity: entity,
            severity: ProblemSeverity.error,
            message: '$name is interface but sits under no UI Canvas.',
            hint: 'Move it under a canvas, or add one above it.',
          ),
        );
      }

      // What a button does.
      for (final actions in _actionListsOf(entity)) {
        for (final action in actions.actions) {
          final custom = action.customName;
          if (custom != null) {
            if (knownActions.isNotEmpty && !knownActions.contains(custom)) {
              out.add(
                SceneProblem(
                  entity: entity,
                  message:
                      '$name does "custom:$custom", which this game does '
                      'not register.',
                ),
              );
            }
            continue;
          }
          if (!jge.UiActions.builtIns.containsKey(action.kind)) {
            out.add(
              SceneProblem(
                entity: entity,
                severity: ProblemSeverity.error,
                message: '$name does "${action.kind}", which is not an action.',
              ),
            );
          }
        }
      }

      // A control nothing happens with.
      if (_isInteractive(entity) &&
          _actionListsOf(entity).every((a) => a.isEmpty)) {
        out.add(
          SceneProblem(
            entity: entity,
            message: '$name can be used, but nothing happens when it is.',
            hint: 'Give it an action, or make it a plain element.',
          ),
        );
      }

      // What the text reads.
      final text = entity.getComponent<jge.TextComponent>();
      if (text != null && knownBindings.isNotEmpty) {
        for (final binding in jge.UiBindings.namesIn(text.text)) {
          if (knownBindings.contains(binding)) continue;
          out.add(
            SceneProblem(
              entity: entity,
              message: '$name reads {$binding}, which the game does not offer.',
            ),
          );
        }
      }

      // A widget the game brought.
      final custom = entity.getComponent<jge.UiCustomComponent>();
      if (custom != null && knownWidgets.isNotEmpty) {
        if (!knownWidgets.contains(custom.widgetId)) {
          out.add(
            SceneProblem(
              entity: entity,
              severity: ProblemSeverity.error,
              message:
                  '$name is the widget "${custom.widgetId}", which this game '
                  'does not register.',
            ),
          );
        }
      }

      if (canvas == null) continue;

      // A screen nobody can reach without a pointer.
      if (canvas.isScreen) {
        final under = _descendantsOf(world, entity);
        final focusable = [
          for (final e in under)
            if (_isFocusable(e)) e,
        ];
        if (focusable.isEmpty) {
          out.add(
            SceneProblem(
              entity: entity,
              message:
                  '$name is a screen with nothing to focus: it cannot be '
                  'used without a pointer.',
            ),
          );
        } else if (canvas.initialFocus.isEmpty) {
          out.add(
            SceneProblem(
              entity: entity,
              message: '$name does not say what takes focus when it opens.',
              hint: 'Set "First focus" to one of the controls under it.',
            ),
          );
        } else if (!focusable.any((e) => e.name == canvas.initialFocus)) {
          out.add(
            SceneProblem(
              entity: entity,
              severity: ProblemSeverity.error,
              message:
                  '$name focuses "${canvas.initialFocus}" when it opens, '
                  'which is not a control under it.',
            ),
          );
        } else if (focusable.any(
          (e) => e.name == canvas.initialFocus && !e.isActive,
        )) {
          // Switched off in the scene: the screen opens with the focus
          // on something the game never builds.
          out.add(
            SceneProblem(
              entity: entity,
              severity: ProblemSeverity.error,
              message:
                  '$name focuses "${canvas.initialFocus}" when it opens, '
                  'which is switched off.',
              hint: 'Switch it back on, or focus something else.',
            ),
          );
        }
      }
    }
    return out;
  }

  /// The canvas [entity] is under, or null when it is under none.
  static jge.Entity? _canvasAbove(jge.World world, jge.Entity entity) {
    var current = entity;
    for (var step = 0; step < 32; step++) {
      final parentId = current.getComponent<jge.ParentComponent>()?.parentId;
      if (parentId == null) return null;
      final parent = world.getEntity(parentId);
      if (parent == null) return null;
      if (parent.getComponent<jge.UiCanvasComponent>() != null) return parent;
      current = parent;
    }
    return null;
  }

  static List<jge.Entity> _descendantsOf(jge.World world, jge.Entity entity) {
    final out = <jge.Entity>[];
    final children = entity.getComponent<jge.ChildrenComponent>();
    if (children == null) return out;
    for (final id in children.childIds) {
      final child = world.getEntity(id);
      if (child == null) continue;
      out
        ..add(child)
        ..addAll(_descendantsOf(world, child));
    }
    return out;
  }

  /// Every list of actions an entity holds, whatever holds them.
  static List<jge.UiActionList> _actionListsOf(jge.Entity entity) => [
    ?entity.getComponent<jge.ButtonComponent>()?.onPressed,
    ?entity.getComponent<jge.UiToggleComponent>()?.onChanged,
    ?entity.getComponent<jge.UiSliderComponent>()?.onChanged,
    ?entity.getComponent<jge.UiDropdownComponent>()?.onChanged,
    ?entity.getComponent<jge.UiTextFieldComponent>()?.onSubmitted,
    ?entity.getComponent<jge.UiTextFieldComponent>()?.onChanged,
  ];

  /// Whether an entity holds any interface component at all.
  static bool _carriesUi(jge.Entity entity) =>
      entity.getComponent<jge.TextComponent>() != null ||
      entity.getComponent<jge.UiCustomComponent>() != null ||
      entity.getComponent<jge.UiTextFieldComponent>() != null ||
      _isInteractive(entity);

  static bool _isInteractive(jge.Entity entity) =>
      entity.getComponent<jge.ButtonComponent>() != null ||
      entity.getComponent<jge.UiToggleComponent>() != null ||
      entity.getComponent<jge.UiSliderComponent>() != null ||
      entity.getComponent<jge.UiDropdownComponent>() != null;

  static bool _isFocusable(jge.Entity entity) =>
      _isInteractive(entity) ||
      entity.getComponent<jge.UiTextFieldComponent>() != null;
}

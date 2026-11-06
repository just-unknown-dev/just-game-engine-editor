import 'package:just_game_engine/just_game_engine.dart' as jge;

import 'package:just_editor_core/host.dart';

/// The checks the editor makes of every scene, the run that sorts what
/// they find, and what `pubspec.yaml` ships. Which checks run is the
/// modules' `validators` (the editor's own: `BuiltInEditorModule`'s).
abstract final class SceneChecks {
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
      if (e.getComponent<UnknownTypesComponent>() case final unknown?)
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

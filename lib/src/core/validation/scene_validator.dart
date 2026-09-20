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
    camerasWithoutTargets,
    drawnWithoutTransform,
  ];

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
}

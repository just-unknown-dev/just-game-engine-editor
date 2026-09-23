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

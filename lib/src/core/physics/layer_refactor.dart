/// Taking a collision layer out of use, its bodies moved to another first,
/// in every scene of the project.
library;

import 'package:just_debugger/just_debugger.dart' show DebuggerLogLevel;
import 'package:just_editor_core/io.dart';
import 'package:just_game_engine/just_game_engine.dart' as jge;

import 'package:just_editor_core/host.dart';

import '../prefabs/prefab_rewrites.dart';

/// One field putting something on a layer: a body's `layer`, or any field
/// of the `physicsLayer` type.
class LayerUse {
  const LayerUse({required this.owner, required this.where});

  /// The entity's name.
  final String owner;

  /// What puts it there: `Physics Body › Layer`.
  final String where;

  @override
  String toString() => '$owner: $where';
}

/// What deleting a layer would change, listed before anything does.
class LayerChangePlan {
  const LayerChangePlan({
    required this.layer,
    required this.moveTo,
    required this.openScene,
    required this.openUses,
    required this.scenes,
    this.unreadable = const [],
    required this.prefabs,
  });

  /// The layer going out of use.
  final int layer;

  /// Where what is on it goes.
  final int moveTo;

  /// The scene being edited, whose changes go on the undo stack instead of
  /// straight to its file. Null when none is open.
  final String? openScene;
  final List<LayerUse> openUses;

  /// Every other scene with something on the layer, by name — instances of
  /// prefabs included, for what they change.
  final Map<String, List<LayerUse>> scenes;

  /// Scenes whose files could not be read: nothing in them is listed, and
  /// nothing in them moves. Said, not skipped.
  final List<String> unreadable;

  /// Every prefab file (`*.prefab.json`) with something on the layer, by
  /// project-relative path: what every instance of it puts there.
  final Map<String, List<LayerUse>> prefabs;

  /// Every use, wherever it is.
  Iterable<LayerUse> get all => [
    ...openUses,
    for (final uses in scenes.values) ...uses,
    for (final uses in prefabs.values) ...uses,
  ];

  /// This plan, what is on the layer going to [layer] instead.
  LayerChangePlan movingTo(int layer) => LayerChangePlan(
    layer: this.layer,
    moveTo: layer,
    openScene: openScene,
    openUses: openUses,
    scenes: scenes,
    prefabs: prefabs,
  );
}

/// What applying a [LayerChangePlan] did.
class LayerChangeResult {
  const LayerChangeResult({
    required this.openChanges,
    required this.filesWritten,
    required this.failures,
  });

  /// Fields changed in the open scene — one undo step.
  final int openChanges;

  /// Scene and prefab files rewritten.
  final List<String> filesWritten;

  /// Scenes and prefabs that could not be read or written, and why.
  final Map<String, String> failures;
}

/// Deletes a collision layer: what is on it moves to another layer in every
/// scene and prefab of the project, then the layer is cleared — no name,
/// colour or description, and colliding with everything, for whatever is
/// made there next.
///
/// * **Prefab files** are rewritten on disk first, each backed up (to
///   `.editor_backups/.prefabs/`), and the open scene's instances of them
///   made again from them.
/// * The **open scene** changes through the undo stack, as one step, and is
///   saved when you save it.
/// * **Other scenes** are rewritten on disk, each backed up first (to
///   `.editor_backups/`, like an autosave) — what their instances of
///   prefabs change included.
///
/// When a file cannot be rewritten, the layer is not cleared: what that
/// file puts on it is still there, and keeps the layer's name and grid.
///
/// Bodies refer to a layer by its number, so a rename needs none of this.
class LayerRefactor {
  LayerRefactor(this.scope, {String? projectRoot})
    : root = (projectRoot ?? Directory.current.path).replaceAll(r'\', '/');

  final EditorScope scope;

  /// The project: where `assets/` is.
  final String root;

  late final PrefabRewrites _prefabs = PrefabRewrites(scope, root: root);

  String? get _openScene => scope.sceneState.activeScene.value?.name;

  static bool _isLayerField(jge.SchemaField field) =>
      field.kind.id == jge.FieldTypes.physicsLayer.id;

  /// What deleting [layer], its contents going to [moveTo], would change.
  LayerChangePlan plan(int layer, {int moveTo = 0}) {
    final open = _openScene;
    final openUses = <LayerUse>[];
    if (open != null) {
      for (final entity in scope.world.entities) {
        final owner = entity.name ?? 'Entity ${entity.id}';
        for (final component in entity.components) {
          final definition = scope.definitions.definitionFor(component);
          if (definition == null) continue;
          for (final field in definition.fields.where(_isLayerField)) {
            if (field.read(component) == layer) {
              openUses.add(_use(owner, definition, field));
            }
          }
        }
      }
    }
    final scenes = <String, List<LayerUse>>{};
    final unreadable = <String>[];
    for (final name in scope.scenes.listSceneNames()) {
      if (name == open) continue;
      try {
        // Listed from the files on disk: null is a file that is not a
        // scene, not one that is missing.
        final raw = scope.scenes.readRawSync(name);
        if (raw == null) {
          unreadable.add(name);
          continue;
        }
        final uses = _inScene(
          jge.SceneFormat.migrate(raw, hooks: scope.context.migrations),
          layer,
        );
        if (uses.isNotEmpty) scenes[name] = uses;
      } on Object {
        unreadable.add(name);
      }
    }
    final prefabs = <String, List<LayerUse>>{};
    for (final path in _prefabs.files()) {
      final List<LayerUse> uses;
      try {
        uses = _inScene(_prefabs.read(path).json, layer);
      } on Object {
        continue;
      }
      if (uses.isNotEmpty) prefabs[path] = uses;
    }
    return LayerChangePlan(
      layer: layer,
      moveTo: moveTo,
      openScene: open,
      openUses: openUses,
      scenes: scenes,
      unreadable: unreadable,
      prefabs: prefabs,
    );
  }

  static LayerUse _use(
    String owner,
    jge.ComponentDefinition definition,
    jge.SchemaField field,
  ) => LayerUse(
    owner: owner,
    where:
        '${definition.hints.name ?? definition.type} › '
        '${definition.hints.fields[field.name]?.label ?? field.name}',
  );

  /// Every field in [scene] (current format) — or in a prefab file, whose
  /// entities are listed the same way — that puts something on [layer];
  /// with [moveTo], each is moved there as it is found. An instance of a
  /// prefab counts for what it changes: the fields it overrides and the
  /// components it adds.
  List<LayerUse> _inScene(
    Map<String, dynamic> scene,
    int layer, {
    int? moveTo,
  }) {
    final out = <LayerUse>[];
    final entities = scene['entities'];
    if (entities is! List) return out;
    for (final entity in entities.whereType<Map>()) {
      final owner = '${entity['name'] ?? '(unnamed)'}';
      final components = entity['components'];
      if (components is List) {
        for (final component in components.whereType<Map>()) {
          _inComponent(component, owner, layer, moveTo, out);
        }
      }
      final block = entity['prefab'];
      if (block is! Map) continue;
      final added = block['addedComponents'];
      if (added is List) {
        for (final entry in added.whereType<Map>()) {
          if (entry['component'] case final Map component) {
            _inComponent(component, owner, layer, moveTo, out);
          }
        }
      }
      final overrides = block['overrides'];
      if (overrides is! List) continue;
      for (final change in overrides.whereType<Map>()) {
        final definition = scope.definitions.definitionByType(
          '${change['component']}',
        );
        if (definition == null) continue;
        for (final field in definition.fields.where(_isLayerField)) {
          final value = change['value'];
          if (field.name != change['field'] ||
              value is! num ||
              value.toInt() != layer) {
            continue;
          }
          out.add(_use(owner, definition, field));
          if (moveTo != null) change['value'] = moveTo;
        }
      }
    }
    return out;
  }

  /// [_inScene] for one saved component.
  void _inComponent(
    Map component,
    String owner,
    int layer,
    int? moveTo,
    List<LayerUse> out,
  ) {
    final fields = component['fields'];
    if (fields is! Map) return;
    final definition = scope.definitions.definitionByType(
      '${component['type']}',
    );
    if (definition == null) return;
    for (final field in definition.fields.where(_isLayerField)) {
      // A body saved without one — or with something that is not a
      // number, which reads as none — is on layer 0.
      final saved = fields[field.name];
      final value = saved is num ? saved.toInt() : 0;
      if (value != layer) continue;
      out.add(_use(owner, definition, field));
      if (moveTo != null) fields[field.name] = moveTo;
    }
  }

  /// Carries [plan] out — not during a play-test: the open scene is the
  /// running game then, and Stop would put its bodies back on the deleted
  /// layer. Nothing changes, and that is said.
  Future<LayerChangeResult> apply(LayerChangePlan plan) async {
    final layers = scope.physicsLayers;
    final from = layers.value.labelOf(plan.layer);
    final to = layers.value.labelOf(plan.moveTo);
    final written = <String>[];
    final failures = <String, String>{};

    if (scope.isPlayTesting.value) {
      const why = 'Stop the play-test first: nothing was changed.';
      scope.log.log(
        'Did not delete the layer "$from": $why',
        source: 'editor',
        category: 'physics',
        level: DebuggerLogLevel.warning,
      );
      return const LayerChangeResult(
        openChanges: 0,
        filesWritten: [],
        failures: {'play-test': why},
      );
    }

    // The layers read are not the project's: nothing is moved for them.
    if (layers.isUnreadable) {
      final why = layers.error ?? 'The layer file cannot be read.';
      scope.log.log(
        'The layer "$from" was not deleted: $why',
        source: 'editor',
        category: 'physics',
        level: DebuggerLogLevel.warning,
      );
      return LayerChangeResult(
        openChanges: 0,
        filesWritten: const [],
        failures: {layers.path: why},
      );
    }
    for (final name in plan.unreadable) {
      failures[name] = 'could not be read, so its bodies stay on "$from"';
    }

    // The prefabs first, and the open scene's instances of them made again
    // from them: an instance's bodies then move with their prefab, and the
    // open scene's own change below finds nothing left to do there.
    final prefabsWritten = <String>[];
    for (final path in plan.prefabs.keys) {
      try {
        final (:json, :before) = _prefabs.read(path);
        if (_inScene(json, plan.layer, moveTo: plan.moveTo).isEmpty) continue;
        await _prefabs.write(path, json, before: before);
        prefabsWritten.add(path);
      } on Object catch (e) {
        failures[path] = '$e';
      }
    }
    written.addAll(prefabsWritten);
    try {
      await _prefabs.refresh(prefabsWritten);
    } on Object catch (e) {
      failures['the open scene\'s prefab instances'] = '$e';
    }

    final openChanges = _applyToOpenScene(plan.layer, plan.moveTo, from);

    for (final name in plan.scenes.keys) {
      try {
        final raw = scope.scenes.readRawSync(name);
        if (raw == null) continue;
        final before = scope.scenes.encodeRawText(raw);
        final migrated = jge.SceneFormat.migrate(
          raw,
          hooks: scope.context.migrations,
        );
        if (_inScene(migrated, plan.layer, moveTo: plan.moveTo).isEmpty) {
          continue;
        }
        await scope.scenes.writeBackup(name, before, keep: 20);
        await scope.scenes
            .writeSceneJson(name, EditorScene.fromJson(migrated), [
              for (final e in migrated['entities'] as List? ?? const [])
                (e as Map).cast<String, dynamic>(),
            ], editor: (migrated['editor'] as Map?)?.cast<String, dynamic>());
        written.add('${scope.scenes.scenesRoot}/$name.scene.json');
      } on Object catch (e) {
        failures[name] = '$e';
      }
    }

    // A file that could not be rewritten still puts something on the
    // layer, so it keeps its name and grid.
    if (failures.isEmpty) layers.clear(plan.layer);
    scope.log.log(
      failures.isEmpty
          ? 'Deleted the layer "$from": ${plan.all.length} moved to "$to"; '
                '${written.length} files rewritten.'
          : 'The layer "$from" was kept: ${failures.length} files could not '
                'be changed and still put something on it; '
                '${written.length} files rewritten.',
      source: 'editor',
      category: 'physics',
      level: failures.isEmpty
          ? DebuggerLogLevel.info
          : DebuggerLogLevel.warning,
      details: [
        ...written,
        for (final f in failures.entries) 'FAILED ${f.key}: ${f.value}',
      ].join('\n'),
    );
    return LayerChangeResult(
      openChanges: openChanges,
      filesWritten: written,
      failures: failures,
    );
  }

  /// The move in the open world, as one undoable step.
  int _applyToOpenScene(int layer, int moveTo, String label) {
    if (_openScene == null) return 0;
    final commands = <EditorCommand>[];
    for (final entity in scope.world.entities) {
      for (final component in entity.components) {
        final definition = scope.definitions.definitionFor(component);
        if (definition == null) continue;
        for (final field in definition.fields.where(_isLayerField)) {
          final write = field.write;
          if (write == null || field.read(component) != layer) continue;
          commands.add(
            ComponentFieldCommand(
              label: 'Layer ${field.name}',
              component: component,
              write: (c, v) => write(c, v),
              before: layer,
              after: moveTo,
              sceneState: scope.sceneState,
              entity: entity,
            ),
          );
        }
      }
    }
    if (commands.isEmpty) return 0;
    scope.history.push(
      CompositeCommand(label: 'Delete the layer "$label"', commands: commands),
    );
    return commands.length;
  }
}

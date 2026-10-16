/// Taking a collision layer out of use, its bodies moved to another first,
/// in every scene of the project.
library;

import 'package:just_game_engine/just_game_engine.dart' as jge;

import 'package:just_editor_core/host.dart';

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
  });

  /// The layer going out of use.
  final int layer;

  /// Where what is on it goes.
  final int moveTo;

  /// The scene being edited, whose changes go on the undo stack instead of
  /// straight to its file. Null when none is open.
  final String? openScene;
  final List<LayerUse> openUses;

  /// Every other scene with something on the layer, by name.
  final Map<String, List<LayerUse>> scenes;

  /// Every use, wherever it is.
  Iterable<LayerUse> get all => [
    ...openUses,
    for (final uses in scenes.values) ...uses,
  ];
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

  /// Scene files rewritten.
  final List<String> filesWritten;

  /// Scenes that could not be read or written, and why.
  final Map<String, String> failures;
}

/// Deletes a collision layer: what is on it moves to another layer in every
/// scene of the project, then the layer is cleared — no name, colour or
/// description, and colliding with everything, for whatever is made there
/// next.
///
/// * The **open scene** changes through the undo stack, as one step, and is
///   saved when you save it.
/// * **Other scenes** are rewritten on disk, each backed up first (to
///   `.editor_backups/`, like an autosave).
///
/// Bodies refer to a layer by its number, so a rename needs none of this.
class LayerRefactor {
  LayerRefactor(this.scope);

  final EditorScope scope;

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
    for (final name in scope.scenes.listSceneNames()) {
      if (name == open) continue;
      final raw = scope.scenes.readRawSync(name);
      if (raw == null) continue;
      final uses = _inScene(
        jge.SceneFormat.migrate(raw, hooks: scope.context.migrations),
        layer,
      );
      if (uses.isNotEmpty) scenes[name] = uses;
    }
    return LayerChangePlan(
      layer: layer,
      moveTo: moveTo,
      openScene: open,
      openUses: openUses,
      scenes: scenes,
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

  /// Every field in [scene] (current format) that puts something on
  /// [layer]; with [moveTo], each is moved there as it is found.
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
      if (components is! List) continue;
      for (final component in components.whereType<Map>()) {
        final fields = component['fields'];
        if (fields is! Map) continue;
        final definition = scope.definitions.definitionByType(
          '${component['type']}',
        );
        if (definition == null) continue;
        for (final field in definition.fields.where(_isLayerField)) {
          // A body saved without one is on layer 0.
          final value = (fields[field.name] as num?)?.toInt() ?? 0;
          if (value != layer) continue;
          out.add(_use(owner, definition, field));
          if (moveTo != null) fields[field.name] = moveTo;
        }
      }
    }
    return out;
  }

  /// Carries [plan] out.
  Future<LayerChangeResult> apply(LayerChangePlan plan) async {
    final layers = scope.physicsLayers;
    final from = layers.value.labelOf(plan.layer);
    final to = layers.value.labelOf(plan.moveTo);
    final written = <String>[];
    final failures = <String, String>{};

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

    layers.clear(plan.layer);
    scope.log.log(
      'Deleted the layer "$from": ${plan.all.length} moved to "$to"; '
      '${written.length} files rewritten.',
      source: 'editor',
      category: 'physics',
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

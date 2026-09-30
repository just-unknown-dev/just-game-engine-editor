/// The checks that catch a tag, a spawner or a target that points nowhere.
library;

import 'package:just_game_engine/just_game_engine.dart' as jge;

import '../../ui/level_designer/state/editor_commands.dart';
import '../scope/editor_scope.dart';
import '../tags/tag_edits.dart';
import 'scene_validator.dart';

/// Checks of the tags, spawn points and targets in the open scene.
///
/// A typo in any of these used to fail without a word: a camera that
/// followed nobody, a spawn point that spawned nothing. Each check says
/// what is wrong where it is, and offers the likely fix.
abstract final class TagChecks {
  static String _nameOf(jge.Entity e) => e.name ?? 'Entity ${e.id}';

  /// Tags carried, or named by a field, that the project does not know.
  static List<SceneProblem> unknownTags(ValidationContext context) {
    final scope = context.scope;
    final tags = scope.tags;
    final out = <SceneProblem>[];
    for (final entity in context.world.entities) {
      for (final tag in entity.tags) {
        if (tags.isKnown(tag)) continue;
        final closest = tags.closest(tag);
        out.add(
          SceneProblem(
            entity: entity,
            message:
                '${_nameOf(entity)} carries the tag "$tag", which is not in '
                "the project's tag list.",
            hint: closest != null
                ? 'Did you mean "$closest"?'
                : 'Add it to the tag list, or pick one that is there.',
            fixes: [
              if (closest != null)
                ProblemFix(
                  label: 'Use "$closest"',
                  apply: () => TagEdits.apply(
                    scope.history,
                    entity,
                    [for (final t in entity.tags) t == tag ? closest : t],
                    scope.sceneState,
                  ),
                ),
              ProblemFix(
                label: 'Add "$tag" to the list',
                apply: () => tags.adopt([tag]),
              ),
            ],
          ),
        );
      }
      _visitTagFields(scope, entity, (use) {
        if (use.tag.isEmpty || tags.isKnown(use.tag)) return;
        final closest = tags.closest(use.tag);
        out.add(
          SceneProblem(
            entity: entity,
            message:
                '${_nameOf(entity)}: ${use.where} names the tag '
                '"${use.tag}", which is not in the project\'s tag list — '
                'nothing will ever carry it.',
            hint: closest != null
                ? 'Did you mean "$closest"?'
                : 'Add it to the tag list if the game gives it out.',
            fixes: [
              if (closest != null)
                ProblemFix(
                  label: 'Use "$closest"',
                  apply: () => use.replace(closest),
                ),
              ProblemFix(
                label: 'Add "${use.tag}" to the list',
                apply: () => tags.adopt([use.tag]),
              ),
            ],
          ),
        );
      });
    }
    return out;
  }

  /// Spawn points that name a spawner the game did not register: Play
  /// creates nothing there, and says so only in the console.
  static List<SceneProblem> spawnPoints(ValidationContext context) {
    final scope = context.scope;
    final spawners = scope.spawners.value;
    final ids = [for (final s in spawners) s.id];
    final out = <SceneProblem>[];
    for (final entity in context.world.entities) {
      final spawn = entity.getComponent<jge.SpawnComponent>();
      if (spawn == null || ids.contains(spawn.spawner)) continue;
      if (spawners.isEmpty) {
        out.add(
          SceneProblem(
            entity: entity,
            message:
                '${_nameOf(entity)} is a spawn point, but the game told the '
                'editor about no spawners: Play will create nothing here.',
            hint:
                'Pass the game\'s spawners to JustGameEditorPlugin.register '
                '(spawners: …).',
          ),
        );
        continue;
      }
      final closest = jge.TagNames.closest(spawn.spawner, ids);
      out.add(
        SceneProblem(
          entity: entity,
          severity: ProblemSeverity.error,
          message: spawn.spawner.isEmpty
              ? '${_nameOf(entity)} is a spawn point that spawns nothing.'
              : '${_nameOf(entity)} spawns "${spawn.spawner}", and the game '
                    'has no spawner by that name: nothing will be created '
                    'here.',
          hint: closest != null
              ? 'Did you mean "$closest"?'
              : 'The game\'s spawners: ${ids.join(', ')}.',
          fixes: [
            for (final id in closest != null ? [closest] : ids.take(3))
              ProblemFix(
                label: 'Spawn "$id"',
                apply: () => scope.history.push(
                  ComponentFieldCommand(
                    label: 'Change what the spawn point spawns',
                    component: spawn,
                    write: (c, v) =>
                        (c as jge.SpawnComponent).spawner = v! as String,
                    before: spawn.spawner,
                    after: id,
                    sceneState: scope.sceneState,
                  ),
                ),
              ),
          ],
        ),
      );
    }
    return out;
  }

  /// Targets that name an entity nothing is called, or a tag nothing in
  /// the scene carries and no spawner gives.
  static List<SceneProblem> unresolvedTargets(ValidationContext context) {
    final scope = context.scope;
    final world = context.world;
    final names = <String>{
      for (final e in world.entities)
        if (e.name != null) e.name!,
    };
    final carried = <String>{
      for (final e in world.entities) ...e.tags,
      ...scope.tags.spawnedTags,
    };
    final out = <SceneProblem>[];
    for (final entity in world.entities) {
      _visitTargets(scope, entity, (use) {
        final target = use.target;
        if (target.isNone || target.isSelf) return;
        if (target.isName && !names.contains(target.value)) {
          final closest = jge.TagNames.closest(target.value, names);
          // "Players" beside a "player" tag: a name typed for a tag.
          final asTag = scope.tags.closest(target.value);
          out.add(
            SceneProblem(
              entity: entity,
              message:
                  '${_nameOf(entity)}: ${use.where} is the entity '
                  '"${target.value}", and nothing in the scene is called '
                  'that.',
              hint:
                  'Fine if the game spawns it by that name; otherwise pick '
                  'an entity, or a tag.',
              fixes: [
                if (closest != null)
                  ProblemFix(
                    label: 'Use "$closest"',
                    apply: () => use.replace(jge.EntityTarget.name(closest)),
                  ),
                if (asTag != null)
                  ProblemFix(
                    label: 'Use the tag "$asTag"',
                    apply: () => use.replace(jge.EntityTarget.tag(asTag)),
                  ),
              ],
            ),
          );
        } else if (target.isTag &&
            scope.tags.isKnown(target.value) &&
            !carried.contains(target.value)) {
          out.add(
            SceneProblem(
              entity: entity,
              message:
                  '${_nameOf(entity)}: ${use.where} is the tag '
                  '"${target.value}", but nothing in the scene carries it '
                  'and no spawner gives it.',
              hint: 'Fine if the game tags something with it while running.',
            ),
          );
        }
      });
    }
    return out;
  }

  // ── Walking an entity's fields ──────────────────────────────────────────

  /// Every tag named by [entity]'s fields — a tag field, a target naming a
  /// tag, a list item's — each with a way to replace it, undoably.
  static void _visitTagFields(
    EditorScope scope,
    jge.Entity entity,
    void Function(_TagFieldUse use) visit,
  ) {
    for (final component in entity.components) {
      final definition = scope.definitions.definitionFor(component);
      if (definition == null) continue;
      final label = definition.hints.name ?? definition.type;
      for (final field in definition.fields) {
        final write = field.write;
        if (write == null) continue;
        final hint = definition.hints.fields[field.name];
        final where = '$label › ${hint?.label ?? field.name}';
        void set(Object? value, String what) => scope.history.push(
          ComponentFieldCommand(
            label: 'Fix $what',
            component: component,
            write: (c, v) => write(c, v),
            before: field.read(component),
            after: value,
            sceneState: scope.sceneState,
          ),
        );
        final value = field.read(component);
        switch (field.kind.id) {
          case 'tagRef' when value is String:
            visit(_TagFieldUse(value, where, (t) => set(t, where)));
          case 'entityTarget' when value is jge.EntityTarget && value.isTag:
            visit(
              _TagFieldUse(
                value.value,
                where,
                (t) => set(jge.EntityTarget.tag(t), where),
              ),
            );
        }
        final kinds = hint?.itemKinds;
        if (kinds == null || value is! List) continue;
        for (var i = 0; i < value.length; i++) {
          final item = value[i];
          if (item is! Map) continue;
          for (final e in kinds.entries) {
            final raw = item[e.key];
            final tag = switch (e.value.id) {
              'tagRef' => raw is String ? raw : null,
              'entityTarget' => raw is Map ? raw['tag'] as String? : null,
              _ => null,
            };
            if (tag == null) continue;
            visit(
              _TagFieldUse(tag, '$where #${i + 1}', (t) {
                final next = [
                  for (final x in value)
                    x is Map ? Map<String, dynamic>.from(x) : x,
                ];
                (next[i] as Map)[e.key] = e.value.id == 'tagRef'
                    ? t
                    : {'tag': t};
                set(next, where);
              }),
            );
          }
        }
      }
    }
  }

  /// Every target [entity]'s fields hold, each with a way to replace it.
  static void _visitTargets(
    EditorScope scope,
    jge.Entity entity,
    void Function(_TargetUse use) visit,
  ) {
    for (final component in entity.components) {
      final definition = scope.definitions.definitionFor(component);
      if (definition == null) continue;
      final label = definition.hints.name ?? definition.type;
      for (final field in definition.fields) {
        final write = field.write;
        if (write == null) continue;
        final hint = definition.hints.fields[field.name];
        final where = '$label › ${hint?.label ?? field.name}';
        void set(Object? value) => scope.history.push(
          ComponentFieldCommand(
            label: 'Fix $where',
            component: component,
            write: (c, v) => write(c, v),
            before: field.read(component),
            after: value,
            sceneState: scope.sceneState,
          ),
        );
        final value = field.read(component);
        if (value is jge.EntityTarget) {
          visit(_TargetUse(value, where, set));
          continue;
        }
        final kinds = hint?.itemKinds;
        if (kinds == null || value is! List) continue;
        for (var i = 0; i < value.length; i++) {
          final item = value[i];
          if (item is! Map) continue;
          for (final e in kinds.entries) {
            if (e.value.id != 'entityTarget') continue;
            visit(
              _TargetUse(
                jge.EntityTarget.fromJson(item[e.key]),
                '$where #${i + 1}',
                (t) {
                  final next = [
                    for (final x in value)
                      x is Map ? Map<String, dynamic>.from(x) : x,
                  ];
                  (next[i] as Map)[e.key] = (t as jge.EntityTarget).toJson();
                  set(next);
                },
              ),
            );
          }
        }
      }
    }
  }
}

/// A tag some field names, and how to put another in its place.
class _TagFieldUse {
  const _TagFieldUse(this.tag, this.where, this.replace);

  final String tag;
  final String where;
  final void Function(String tag) replace;
}

/// A target some field holds, and how to put another in its place.
class _TargetUse {
  const _TargetUse(this.target, this.where, this.replace);

  final jge.EntityTarget target;
  final String where;
  final void Function(Object? target) replace;
}

/// What the editor itself draws at the end of a scene-tree row.
///
/// The same contribution point a module uses, filled in by the editor:
/// what is wrong with an entity, and whether anything animates it. A row
/// is the one place all of that is visible at a glance.
library;

import 'package:flutter/material.dart';
import 'package:just_game_engine/just_game_engine.dart' as jge;

import 'package:just_editor_core/host.dart';
import '../ui/overlay/docks/extra/extra_docks.dart';

abstract final class BuiltInRowDecorations {
  static List<SceneTreeRowDecoration> get all => [
    SceneTreeRowDecoration(id: problemsId, order: 20, build: _problems),
    SceneTreeRowDecoration(id: animatedId, order: 30, build: _animated),
    SceneTreeRowDecoration(id: prefabId, order: 10, build: _prefab),
  ];

  static const String problemsId = 'builtIn.problems';
  static const String animatedId = 'builtIn.animated';
  static const String prefabId = 'builtIn.prefab';

  /// Part of a prefab instance: a box on its top, a dot on the rest.
  static Widget? _prefab(BuildContext context, jge.Entity entity) {
    final instance = entity.getComponent<jge.PrefabInstanceComponent>();
    if (instance == null && !entity.hasComponent<jge.PrefabLink>()) return null;
    final colour = instance?.missing ?? false
        ? EditorTheme.warning
        : EditorTheme.primaryBright;
    return Tooltip(
      message: instance == null
          ? 'Part of a prefab instance'
          : instance.missing
          ? 'An instance of ${instance.path}, which could not be read'
          : 'An instance of ${instance.path}',
      child: Padding(
        padding: const EdgeInsets.only(right: 4),
        child: instance == null
            ? Container(
                width: 5,
                height: 5,
                decoration: BoxDecoration(
                  color: colour.withValues(alpha: 0.7),
                  shape: BoxShape.circle,
                ),
              )
            : Icon(Icons.inventory_2_outlined, size: 13, color: colour),
      ),
    );
  }

  /// How many scene checks this entity failed, and how badly.
  static Widget? _problems(BuildContext context, jge.Entity entity) {
    final scope = EditorScopeProvider.maybeOf(context);
    if (scope == null) return null;
    final mine = ProblemScan.of(
      scope,
    ).problems.where((p) => p.entity?.id == entity.id).toList();
    if (mine.isEmpty) return null;
    final worst = mine.any((p) => p.severity == ProblemSeverity.error);
    return Tooltip(
      message: mine.map((p) => p.message).join('\n'),
      child: Padding(
        padding: const EdgeInsets.only(right: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              worst ? Icons.error_outline : Icons.warning_amber_rounded,
              size: 12,
              color: worst ? EditorTheme.error : EditorTheme.warning,
            ),
            if (mine.length > 1)
              Text(
                ' ${mine.length}',
                style: TextStyle(
                  fontSize: 9,
                  color: worst ? EditorTheme.error : EditorTheme.warning,
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// Whether something moves this entity without anyone touching it.
  static Widget? _animated(BuildContext context, jge.Entity entity) {
    final timeline = entity.getComponent<jge.TimelinePlayerComponent>() != null;
    final animator = entity.getComponent<jge.AnimatorComponent>() != null;
    if (!timeline && !animator) return null;
    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: Icon(
        timeline ? Icons.movie_outlined : Icons.animation,
        size: 12,
        color: EditorTheme.textMuted,
      ),
    );
  }
}

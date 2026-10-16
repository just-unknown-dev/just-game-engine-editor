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
  ];

  static const String problemsId = 'builtIn.problems';
  static const String animatedId = 'builtIn.animated';

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

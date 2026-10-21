/// Tags in the scene tree: a dot per tag on each row, and selecting
/// everything that shares one.
library;

import 'package:flutter/material.dart';
import 'package:just_game_engine/just_game_engine.dart' as jge;

import 'package:just_editor_core/host.dart';

abstract final class BuiltInTagContributions {
  static const String tagsId = 'builtIn.tags';
  static const String selectTaggedId = 'builtIn.selectTagged';

  static List<SceneTreeRowDecoration> get rowDecorations => [
    SceneTreeRowDecoration(id: tagsId, order: 10, build: _dots),
  ];

  static List<SceneTreeAction> get sceneTreeActions => [
    SceneTreeAction(
      id: selectTaggedId,
      label: 'Select everything tagged like this',
      icon: Icons.label_outline,
      order: 40,
      isEnabled: (entity, _) => entity.tags.isNotEmpty,
      run: selectTaggedLike,
    ),
  ];

  /// Selects every entity sharing one of [entity]'s tags.
  static void selectTaggedLike(jge.Entity entity, EditorScope scope) {
    final wanted = entity.tags;
    final found = [
      for (final e in scope.world.entities)
        if (e.isAlive && wanted.any(e.hasTag) && scope.sceneState.canSelect(e))
          e,
    ];
    if (found.isEmpty) return;
    scope.sceneState.selectRange(
      found,
      anchor: found.contains(entity) ? entity : found.first,
    );
  }

  /// A coloured dot for each tag — three at most, then a count.
  static Widget? _dots(BuildContext context, jge.Entity entity) {
    final tags = entity.tags.toList();
    if (tags.isEmpty) return null;
    final scope = EditorScopeProvider.maybeOf(context);
    Color colour(String t) =>
        scope?.tags.colorOf(t) ?? jge.TagLibrary.colorFor(t);
    return Tooltip(
      message: tags.map((t) => '#$t').join('  '),
      child: Padding(
        padding: const EdgeInsets.only(right: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final t in tags.take(3))
              Container(
                width: 7,
                height: 7,
                margin: const EdgeInsets.only(left: 2),
                decoration: BoxDecoration(
                  color: colour(t),
                  shape: BoxShape.circle,
                ),
              ),
            if (tags.length > 3)
              Text(
                ' +${tags.length - 3}',
                style: const TextStyle(fontSize: 9, color: Colors.white54),
              ),
          ],
        ),
      ),
    );
  }
}

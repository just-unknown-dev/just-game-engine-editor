import 'package:flutter/material.dart';
import 'package:just_game_engine/just_game_engine.dart' as jge;

import '../core/constants/editor_constants.dart';
import '../core/scope/editor_scope.dart';
import '../ui/inspector/component_extras.dart';
import 'editor_contributions.dart';

/// What the editor itself contributes for cameras, through the same seams a
/// module uses: a scene-tree action and badge, and inspector extras.
abstract final class BuiltInCameraContributions {
  static const String soloActionId = 'camera.solo';
  static const String liveDecorationId = 'camera.live';

  /// Looks through one camera while working on it, whatever its priority.
  static void toggleSolo(jge.Entity camera, EditorScope scope) {
    final brain = scope.cameraBrain;
    if (brain == null) return;
    brain.soloEntity = brain.soloEntity == camera.id ? null : camera.id;
    // The brain is not a signal; the tree and the inspector redraw from this.
    scope.sceneState.refresh();
  }

  static List<SceneTreeAction> get sceneTreeActions => [
    SceneTreeAction(
      id: soloActionId,
      label: 'Solo camera',
      icon: Icons.center_focus_strong,
      order: 10,
      isEnabled: (entity, scope) =>
          scope.cameraBrain != null &&
          entity.hasComponent<jge.VirtualCameraComponent>(),
      run: toggleSolo,
    ),
  ];

  static List<SceneTreeRowDecoration> get rowDecorations => [
    SceneTreeRowDecoration(
      id: liveDecorationId,
      order: 10,
      build: (context, entity) {
        if (!entity.hasComponent<jge.VirtualCameraComponent>()) return null;
        final brain = EditorScopeProvider.maybeOf(context)?.cameraBrain;
        if (brain == null || brain.liveCamera?.id != entity.id) return null;
        return _Badge(brain.soloEntity == entity.id ? 'SOLO' : 'LIVE');
      },
    ),
  ];

  static List<ComponentEditorExtras> get extras => [
    ComponentEditorExtras(
      type: 'VirtualCameraComponent',
      summary: (c) {
        final vcam = c as jge.VirtualCameraComponent;
        return [
          'priority ${vcam.priority}',
          if (!vcam.follow.isNone) 'follows ${vcam.follow.label}',
          if (!vcam.enabled) 'off',
        ].join(' · ');
      },
      actions: [
        InspectorAction(
          id: soloActionId,
          label: 'Solo',
          icon: Icons.center_focus_strong,
          run: (context, component) async {
            final scope = EditorScopeProvider.maybeOf(context);
            if (scope == null) return;
            for (final entity in scope.world.query([
              jge.VirtualCameraComponent,
            ])) {
              if (entity.components.any((c) => identical(c, component))) {
                toggleSolo(entity, scope);
                return;
              }
            }
          },
        ),
      ],
    ),
  ];
}

class _Badge extends StatelessWidget {
  const _Badge(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Container(
    // Room after it, as the other row decorations leave, so the warning
    // or mark that follows does not touch its border.
    margin: const EdgeInsets.only(right: 8),
    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
    decoration: BoxDecoration(
      color: const Color(0xFF40E0D0).withValues(alpha: 0.18),
      borderRadius: BorderRadius.circular(3),
      border: Border.all(color: const Color(0xFF40E0D0), width: 1),
    ),
    child: Text(
      text,
      style: TextStyle(
        color: EditorTheme.textBright,
        fontSize: 8,
        fontWeight: FontWeight.w800,
        letterSpacing: 0.4,
      ),
    ),
  );
}

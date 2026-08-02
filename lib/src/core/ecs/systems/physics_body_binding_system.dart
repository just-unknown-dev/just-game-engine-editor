import 'package:just_game_engine/just_game_engine.dart';

import '../../state/editor_scene_state.dart';

/// Live gizmo-drag authoring override for physics bodies.
///
/// Body lifecycle (creation, property sync, stepping, and syncing results
/// back to [TransformComponent]) is entirely owned by the core
/// [PhysicsSystem] now — this system's only remaining job is making a
/// selected/dragged entity feel immediate: it zeroes residual
/// velocity/angular-velocity and wakes the body while the entity is being
/// authored, so momentum from gameplay/simulation doesn't fight the drag.
///
/// The actual position push happens for free: [EditorSceneState]'s
/// translate/rotate/scale operations mutate [TransformComponent] directly,
/// and [PhysicsSystem] already pushes `TransformComponent -> PhysicsBody`
/// unconditionally at the start of every step (that's how spawns/teleports
/// take effect) — dragging is just another such write.
class PhysicsBodyBindingSystem extends System {
  PhysicsBodyBindingSystem({
    this.sceneState,
    this.isAuthoringActive,
    this.isDraggingActive,
  });

  final EditorSceneState? sceneState;

  /// Optional gate to limit the drag override below.
  final bool Function()? isAuthoringActive;

  /// Reports whether a gizmo drag is actually in progress right now. Without
  /// this, [_shouldOverrideBody] would fire for any merely-selected entity —
  /// zeroing its velocity every frame just for being inspected, freezing it
  /// mid-fall/roll for as long as it stays selected.
  final bool Function()? isDraggingActive;

  // Runs after PhysicsSystem (priority 90) in the same frame, so every
  // dragged entity's PhysicsBodyRefComponent already exists by the time
  // this reads it.
  @override
  int get priority => SystemPriorities.physics - 3;

  @override
  List<Type> get requiredComponents => [PhysicsBodyRefComponent];

  @override
  void update(double deltaTime) {
    forEach((entity) {
      if (!_shouldOverrideBody(entity)) return;
      final body = entity.getComponent<PhysicsBodyRefComponent>()!.body;
      body.velocity.setZero();
      body.angularVelocity = 0.0;
      body.isAwake = true;
    });
  }

  bool _shouldOverrideBody(Entity entity) {
    final active = isAuthoringActive?.call() ?? true;
    if (!active) return false;
    final dragging = isDraggingActive?.call() ?? false;
    if (!dragging) return false;
    final scene = sceneState;
    if (scene == null) return false;
    if (scene.isInMultiSelection(entity.id)) return true;
    final selected = scene.selectedEntity;
    return selected != null && selected.id == entity.id;
  }
}

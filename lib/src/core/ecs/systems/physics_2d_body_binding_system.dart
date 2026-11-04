import 'package:just_game_engine/just_game_engine.dart';

import 'package:just_editor_core/host.dart';

/// Keeps a physics body still while the editor's gizmo drags it.
///
/// Body lifecycle (creation, property sync, stepping, and syncing results
/// back to [TransformComponent]) is entirely owned by the core
/// [Physics2DSystem] — this system's only job is making a dragged entity
/// feel immediate during a play-test, when bodies move: while a gizmo drag
/// is under way it zeroes the dragged bodies' velocity and angular velocity
/// and wakes them, so momentum and gravity do not fight the drag. While
/// authoring the game's time stands still and nothing steps, so it has
/// nothing to do then.
///
/// The actual position push happens for free: [EditorSceneState]'s
/// translate/rotate/scale operations mutate [TransformComponent] directly,
/// and [Physics2DSystem] already pushes `TransformComponent -> Physics2DBody`
/// unconditionally at the start of every step (that's how spawns/teleports
/// take effect) — dragging is just another such write.
class Physics2DBodyBindingSystem extends System {
  Physics2DBodyBindingSystem({
    this.sceneState,
    this.isAuthoringActive,
    this.isDraggingActive,
  });

  final EditorSceneState? sceneState;

  /// Optional gate to limit the drag override below: when it says false,
  /// nothing is done. Always on when null.
  final bool Function()? isAuthoringActive;

  /// Reports whether a gizmo drag is actually in progress right now. Without
  /// this, [_shouldOverrideBody] would fire for any merely-selected entity —
  /// zeroing its velocity every frame just for being inspected, freezing it
  /// mid-fall/roll for as long as it stays selected.
  final bool Function()? isDraggingActive;

  // Runs after Physics2DSystem (priority 90) in the same frame, so every
  // dragged entity's Physics2DBodyRefComponent already exists by the time
  // this reads it.
  @override
  int get priority => SystemPriorities.physics - 3;

  @override
  List<Type> get requiredComponents => [Physics2DBodyRefComponent];

  @override
  void update(double deltaTime) {
    forEach((entity) {
      if (!_shouldOverrideBody(entity)) return;
      final body = entity.getComponent<Physics2DBodyRefComponent>()!.body;
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
    final selected = scene.selectedEntity.value;
    return selected != null && selected.id == entity.id;
  }
}

import 'package:just_game_engine/just_game_engine.dart';

import '../state/editor_scene_state.dart';

/// Ensures editor [PhysicsBodyComponent] entities have runtime subsystem
/// [PhysicsBody] instances via [PhysicsBodyRefComponent].
class PhysicsBodyBindingSystem extends System {
  PhysicsBodyBindingSystem(
    this.physics, {
    this.sceneState,
    this.isAuthoringActive,
  });

  final PhysicsEngine physics;
  final EditorSceneState? sceneState;

  /// Optional gate to limit transform->body authoring pushes.
  final bool Function()? isAuthoringActive;

  final Map<int, PhysicsBody> _entityBodyMap = <int, PhysicsBody>{};

  @override
  int get priority => SystemPriorities.physics;

  @override
  List<Type> get requiredComponents => [
    TransformComponent,
    PhysicsBodyComponent,
  ];

  @override
  void update(double deltaTime) {
    final activeIds = <int>{};

    forEach((entity) {
      if (!entity.isActive) return;
      activeIds.add(entity.id);

      final transform = entity.getComponent<TransformComponent>()!;
      final comp = entity.getComponent<PhysicsBodyComponent>()!;
      var ref = entity.getComponent<PhysicsBodyRefComponent>();
      var body = _entityBodyMap[entity.id];

      if (body == null || ref == null) {
        body = PhysicsBody(
          position: Vector2(transform.position.x, transform.position.y),
          shape: comp.shape,
          mass: comp.isStatic ? 0.0 : comp.mass,
          restitution: comp.restitution,
          drag: comp.drag,
          useGravity: !comp.isStatic,
          isSensor: comp.isSensor,
          categoryBits: comp.categoryBits,
          maskBits: comp.maskBits,
          groupIndex: comp.groupIndex,
        );

        final vel = entity.getComponent<VelocityComponent>();
        if (vel != null) {
          body.velocity.setValues(vel.velocity.x, vel.velocity.y);
        }

        physics.addBody(body);
        _entityBodyMap[entity.id] = body;

        if (ref == null) {
          entity.addComponent(PhysicsBodyRefComponent(body));
        }
      } else {
        _syncBodyFromComponent(body, comp);
      }

      // During live editor manipulation, selected entities should feel
      // immediate under gizmo/text edits, so push Transform -> PhysicsBody.
      if (_shouldPushTransformToBody(entity)) {
        body.position.setValues(transform.position.x, transform.position.y);
        body.angle = transform.rotation;
        body.velocity.setZero();
        body.angularVelocity = 0.0;
        body.isAwake = true;
      }
    });

    final staleIds = _entityBodyMap.keys
        .where((entityId) => !activeIds.contains(entityId))
        .toList();

    for (final entityId in staleIds) {
      final body = _entityBodyMap.remove(entityId);
      if (body != null) {
        physics.removeBody(body);
      }
      final entity = world.getEntity(entityId);
      entity?.removeComponent<PhysicsBodyRefComponent>();
    }
  }

  @override
  void onRemovedFromWorld() {
    for (final body in _entityBodyMap.values) {
      physics.removeBody(body);
    }
    _entityBodyMap.clear();
  }

  void _syncBodyFromComponent(PhysicsBody body, PhysicsBodyComponent comp) {
    body.shape = comp.shape;
    body.mass = comp.isStatic ? 0.0 : comp.mass;
    body.restitution = comp.restitution;
    body.drag = comp.drag;
    body.useGravity = !comp.isStatic;
    body.isSensor = comp.isSensor;
    body.categoryBits = comp.categoryBits;
    body.maskBits = comp.maskBits;
    body.groupIndex = comp.groupIndex;
  }

  bool _shouldPushTransformToBody(Entity entity) {
    final active = isAuthoringActive?.call() ?? true;
    if (!active) return false;
    final scene = sceneState;
    if (scene == null) return false;
    if (scene.isInMultiSelection(entity.id)) return true;
    final selected = scene.selectedEntity;
    return selected != null && selected.id == entity.id;
  }
}

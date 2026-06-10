import 'package:flutter/painting.dart';
import 'package:just_game_engine/just_game_engine.dart';

import '../components/physics_joint_components.dart';
import '../components/simple_movement_component.dart';

/// A single entry in the component picker catalogue.
class ComponentEntry {
  const ComponentEntry({
    required this.name,
    required this.group,
    required this.description,
    required this.factory,
    this.componentTypeName,
  });

  final String name;
  final String group;
  final String description;
  final String? componentTypeName;

  /// Produces a new component instance with sensible editor defaults.
  final Component Function() factory;
}

/// Groups used to categorise the component list.
const List<String> kComponentGroups = [
  'Core',
  'Rendering',
  'Physics',
  'Gameplay',
  'Input',
  'Camera',
  'Audio',
  'Animation',
  'Hierarchy',
  'Effects',
  'UI',
];

/// The full catalogue of addable components.
///
/// Components that require externally constructed objects (ParticleEmitter,
/// FragmentProgram, TileLayer, etc.) are excluded — they cannot be
/// meaningfully constructed inside the editor without additional tooling.
const List<ComponentEntry> kComponentRegistry = [
  // ── Core ────────────────────────────────────────────────────────────────
  ComponentEntry(
    name: 'TransformComponent',
    group: 'Core',
    description: 'Position, rotation, and scale.',
    factory: _makeTransform,
  ),
  ComponentEntry(
    name: 'VelocityComponent',
    group: 'Core',
    description: 'Linear velocity with an optional max-speed cap.',
    factory: _makeVelocity,
  ),

  // ── Rendering ────────────────────────────────────────────────────────────
  ComponentEntry(
    name: 'RectangleComponent',
    group: 'Rendering',
    description: 'Filled or stroked rectangle.',
    factory: _makeRectangle,
  ),
  ComponentEntry(
    name: 'CircleComponent',
    group: 'Rendering',
    description: 'Filled or stroked circle.',
    factory: _makeCircle,
  ),
  ComponentEntry(
    name: 'CapsuleComponent',
    group: 'Rendering',
    description: 'Filled or stroked capsule (rounded rectangle).',
    factory: _makeCapsule,
  ),
  ComponentEntry(
    name: 'SpriteComponent',
    group: 'Rendering',
    description: 'Single sprite / texture frame. Set spritePath in inspector.',
    factory: _makeSprite,
  ),
  ComponentEntry(
    name: 'LineComponent',
    group: 'Rendering',
    description: 'A line segment between two points.',
    factory: _makeLine,
  ),
  ComponentEntry(
    name: 'PolygonComponent',
    group: 'Rendering',
    description: 'Convex polygon (default: square outline).',
    factory: _makePolygon,
  ),

  // ── Physics ──────────────────────────────────────────────────────────────
  ComponentEntry(
    name: 'PhysicsBodyCircle',
    group: 'Physics',
    description: 'Dynamic rigid body with a circular collision shape.',
    factory: _makePhysicsBodyCircle,
    componentTypeName: 'PhysicsBodyComponent',
  ),
  ComponentEntry(
    name: 'PhysicsBodyRectangle',
    group: 'Physics',
    description: 'Dynamic rigid body with a rectangle collision shape.',
    factory: _makePhysicsBodyRectangle,
    componentTypeName: 'PhysicsBodyComponent',
  ),
  ComponentEntry(
    name: 'PhysicsBodyPolygon',
    group: 'Physics',
    description: 'Dynamic rigid body with a convex polygon collision shape.',
    factory: _makePhysicsBodyPolygon,
    componentTypeName: 'PhysicsBodyComponent',
  ),
  ComponentEntry(
    name: 'PhysicsBodyCapsule',
    group: 'Physics',
    description: 'Dynamic rigid body with a capsule collision shape.',
    factory: _makePhysicsBodyCapsule,
    componentTypeName: 'PhysicsBodyComponent',
  ),
  ComponentEntry(
    name: 'PhysicsBodySegment',
    group: 'Physics',
    description: 'Static line segment collider, useful for ramps/platforms.',
    factory: _makePhysicsBodySegment,
    componentTypeName: 'PhysicsBodyComponent',
  ),
  ComponentEntry(
    name: 'PhysicsBodyChain',
    group: 'Physics',
    description: 'Static chain collider for terrain-like collision paths.',
    factory: _makePhysicsBodyChain,
    componentTypeName: 'PhysicsBodyComponent',
  ),
  ComponentEntry(
    name: 'PhysicsBodyRoundedRect',
    group: 'Physics',
    description: 'Dynamic rigid body with rounded rectangle collision.',
    factory: _makePhysicsBodyRoundedRect,
    componentTypeName: 'PhysicsBodyComponent',
  ),
  ComponentEntry(
    name: 'PhysicsSensorCircle',
    group: 'Physics',
    description: 'Static circular sensor body (overlap detection only).',
    factory: _makePhysicsSensorCircle,
    componentTypeName: 'PhysicsBodyComponent',
  ),
  ComponentEntry(
    name: 'PhysicsSensorRectangle',
    group: 'Physics',
    description: 'Static rectangle sensor body (overlap detection only).',
    factory: _makePhysicsSensorRectangle,
    componentTypeName: 'PhysicsBodyComponent',
  ),
  ComponentEntry(
    name: 'PhysicsSensorCapsule',
    group: 'Physics',
    description: 'Static capsule sensor body (overlap detection only).',
    factory: _makePhysicsSensorCapsule,
    componentTypeName: 'PhysicsBodyComponent',
  ),
  ComponentEntry(
    name: 'DistanceJointComponent',
    group: 'Physics',
    description:
        'Distance/spring joint descriptor linking this entity to targetEntityName.',
    factory: _makeDistanceJoint,
  ),
  ComponentEntry(
    name: 'WeldJointComponent',
    group: 'Physics',
    description: 'Rigid weld joint descriptor linking to targetEntityName.',
    factory: _makeWeldJoint,
  ),
  ComponentEntry(
    name: 'PrismaticJointComponent',
    group: 'Physics',
    description: 'Slider joint descriptor with optional limits/motor.',
    factory: _makePrismaticJoint,
  ),
  ComponentEntry(
    name: 'WheelJointComponent',
    group: 'Physics',
    description: 'Wheel suspension + motor joint descriptor.',
    factory: _makeWheelJoint,
  ),

  // ── Gameplay ─────────────────────────────────────────────────────────────
  ComponentEntry(
    name: 'HealthComponent',
    group: 'Gameplay',
    description: 'Hit-points with max-health = 100.',
    factory: _makeHealth,
  ),
  ComponentEntry(
    name: 'TagComponent',
    group: 'Gameplay',
    description: 'String tag for entity categorisation.',
    factory: _makeTag,
  ),
  ComponentEntry(
    name: 'LifetimeComponent',
    group: 'Gameplay',
    description: 'Auto-destroys the entity after 3 seconds.',
    factory: _makeLifetime,
  ),
  // ── Input ────────────────────────────────────────────────────────────────
  ComponentEntry(
    name: 'InputComponent',
    group: 'Input',
    description: 'Marks entity as the keyboard/gamepad input receiver.',
    factory: _makeInput,
  ),
  ComponentEntry(
    name: 'JoystickInputComponent',
    group: 'Input',
    description: 'Virtual joystick input state.',
    factory: _makeJoystick,
  ),
  ComponentEntry(
    name: 'SimpleMovementComponent',
    group: 'Input',
    description:
        'Moves Transform from keyboard/joystick direction with a speed scalar.',
    factory: _makeSimpleMovement,
  ),

  // ── Camera ───────────────────────────────────────────────────────────────
  ComponentEntry(
    name: 'CameraFollowComponent',
    group: 'Camera',
    description: 'Camera smoothly follows this entity.',
    factory: _makeCameraFollow,
  ),

  // ── Audio ─────────────────────────────────────────────────────────────────
  ComponentEntry(
    name: 'AudioSourceComponent',
    group: 'Audio',
    description: 'Looping audio source. Set clipPath in inspector.',
    factory: _makeAudioSource,
  ),
  ComponentEntry(
    name: 'AudioStreamComponent',
    group: 'Audio',
    description: 'Streaming music track. Set path in inspector.',
    factory: _makeAudioStream,
  ),

  // ── Animation ─────────────────────────────────────────────────────────────
  ComponentEntry(
    name: 'AnimationStateComponent',
    group: 'Animation',
    description: 'Sprite-sheet animation state (idle, 4 frames).',
    factory: _makeAnimationState,
  ),

  // ── Hierarchy ─────────────────────────────────────────────────────────────
  ComponentEntry(
    name: 'ChildrenComponent',
    group: 'Hierarchy',
    description: 'Marks entity as a parent that can have child entities.',
    factory: _makeChildren,
  ),
  ComponentEntry(
    name: 'ParentComponent',
    group: 'Hierarchy',
    description: 'Attaches entity to a parent entity.',
    factory: _makeParent,
  ),

  // ── Effects ───────────────────────────────────────────────────────────────
  ComponentEntry(
    name: 'EffectComponent',
    group: 'Effects',
    description: 'Marker for deterministic tween effects.',
    factory: _makeEffect,
  ),

  // ── UI ────────────────────────────────────────────────────────────────────
  ComponentEntry(
    name: 'UIComponent',
    group: 'UI',
    description: 'Base UI element (100×40).',
    factory: _makeUI,
  ),
  ComponentEntry(
    name: 'TextComponent',
    group: 'UI',
    description: 'Text label (200×40).',
    factory: _makeText,
  ),
  ComponentEntry(
    name: 'ButtonComponent',
    group: 'UI',
    description: 'Clickable button (120×40).',
    factory: _makeButton,
  ),
  ComponentEntry(
    name: 'LinearProgressComponent',
    group: 'UI',
    description: 'Horizontal progress bar (200×20).',
    factory: _makeLinearProgress,
  ),
  ComponentEntry(
    name: 'CircularProgressComponent',
    group: 'UI',
    description: 'Circular progress indicator (radius 30).',
    factory: _makeCircularProgress,
  ),
];

// ── Factories ─────────────────────────────────────────────────────────────────

Component _makeTransform() => TransformComponent();
Component _makeVelocity() => VelocityComponent(maxSpeed: 500);

Component _makeRectangle() => RectangleComponent(width: 64, height: 64);
Component _makeCircle() => CircleComponent(radius: 32);
Component _makeCapsule() => CapsuleComponent(width: 32, height: 64);
Component _makeSprite() => SpriteComponent(spritePath: '');
Component _makeLine() => LineComponent(end: const Offset(100, 0));
Component _makePolygon() => PolygonComponent(
  vertices: const [
    Offset(-32, -32),
    Offset(32, -32),
    Offset(32, 32),
    Offset(-32, 32),
  ],
);

Component _makePhysicsBodyCircle() => PhysicsBodyComponent(
  shape: CircleShape(24),
  mass: 1.0,
  isStatic: false,
  restitution: 0.6,
  drag: 0.98,
);

Component _makePhysicsBodyRectangle() => PhysicsBodyComponent(
  shape: RectangleShape(64, 40),
  mass: 1.2,
  isStatic: false,
  restitution: 0.4,
  drag: 0.98,
);

Component _makePhysicsBodyPolygon() => PhysicsBodyComponent(
  shape: PolygonShape([
    const Offset(0, -30),
    const Offset(28, -8),
    const Offset(18, 28),
    const Offset(-18, 28),
    const Offset(-28, -8),
  ]),
  mass: 1.1,
  isStatic: false,
  restitution: 0.45,
  drag: 0.98,
);

Component _makePhysicsBodyCapsule() => PhysicsBodyComponent(
  shape: CapsuleShape(
    center1: const Offset(0, -16),
    center2: const Offset(0, 16),
    radius: 10,
  ),
  mass: 1.2,
  isStatic: false,
  restitution: 0.5,
  drag: 0.98,
);

Component _makePhysicsBodySegment() => PhysicsBodyComponent(
  shape: SegmentShape(
    const Offset(-48, 0),
    const Offset(48, -20),
    thickness: 3,
  ),
  mass: 0,
  isStatic: true,
  restitution: 0.3,
  drag: 0.98,
);

Component _makePhysicsBodyChain() => PhysicsBodyComponent(
  shape: ChainShape(const [
    Offset(-60, 8),
    Offset(-30, -14),
    Offset(0, 8),
    Offset(30, -14),
    Offset(60, 8),
  ], thickness: 3),
  mass: 0,
  isStatic: true,
  restitution: 0.3,
  drag: 0.98,
);

Component _makePhysicsBodyRoundedRect() => PhysicsBodyComponent(
  shape: RoundedPolygonShape.rect(width: 56, height: 36, cornerRadius: 8),
  mass: 1.3,
  isStatic: false,
  restitution: 0.5,
  drag: 0.98,
);

Component _makePhysicsSensorCircle() => PhysicsBodyComponent(
  shape: CircleShape(48),
  mass: 0,
  isStatic: true,
  isSensor: true,
  restitution: 0.0,
  drag: 0.98,
);

Component _makePhysicsSensorRectangle() => PhysicsBodyComponent(
  shape: RectangleShape(96, 48),
  mass: 0,
  isStatic: true,
  isSensor: true,
  restitution: 0.0,
  drag: 0.98,
);

Component _makePhysicsSensorCapsule() => PhysicsBodyComponent(
  shape: CapsuleShape(
    center1: const Offset(0, -20),
    center2: const Offset(0, 20),
    radius: 14,
  ),
  mass: 0,
  isStatic: true,
  isSensor: true,
  restitution: 0.0,
  drag: 0.98,
);

Component _makeDistanceJoint() => DistanceJointComponent();
Component _makeWeldJoint() => WeldJointComponent();
Component _makePrismaticJoint() => PrismaticJointComponent();
Component _makeWheelJoint() => WheelJointComponent();

Component _makeHealth() => HealthComponent(maxHealth: 100);
Component _makeTag() => TagComponent('entity');
Component _makeLifetime() => LifetimeComponent(3.0);
Component _makeInput() => InputComponent();
Component _makeJoystick() => JoystickInputComponent();
Component _makeSimpleMovement() => SimpleMovementComponent(speed: 220);
Component _makeCameraFollow() => CameraFollowComponent();

Component _makeAudioSource() => AudioSourceComponent(clipPath: '');
Component _makeAudioStream() => AudioStreamComponent(path: '');

Component _makeAnimationState() => AnimationStateComponent(
  currentAnimation: 'idle',
  frameCount: 4,
  frameDuration: 0.1,
);

Component _makeChildren() => ChildrenComponent();
Component _makeParent() => ParentComponent();
Component _makeEffect() => EffectComponent();

Component _makeUI() => UIComponent(size: const Size(100, 40));
Component _makeText() => TextComponent(text: 'Text', size: const Size(200, 40));
Component _makeButton() =>
    ButtonComponent(text: 'Button', size: const Size(120, 40));
Component _makeLinearProgress() =>
    LinearProgressComponent(size: const Size(200, 20));
Component _makeCircularProgress() => CircularProgressComponent(radius: 30);

import 'package:flutter/painting.dart';
import 'package:just_game_engine/just_game_engine.dart';

/// A single entry in the component picker catalogue.
class ComponentEntry {
  const ComponentEntry({
    required this.name,
    required this.group,
    required this.description,
    required this.factory,
  });

  final String name;
  final String group;
  final String description;

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
    name: 'PhysicsBodyComponent',
    group: 'Physics',
    description: 'Rigid-body physics with a 64×64 box shape by default.',
    factory: _makePhysicsBody,
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

Component _makePhysicsBody() => PhysicsBodyComponent(
  shape: PolygonShape([
    const Offset(-32, -32),
    const Offset(32, -32),
    const Offset(32, 32),
    const Offset(-32, 32),
  ]),
  mass: 1.0,
  isStatic: false,
);

Component _makeHealth() => HealthComponent(maxHealth: 100);
Component _makeTag() => TagComponent('entity');
Component _makeLifetime() => LifetimeComponent(3.0);
Component _makeInput() => InputComponent();
Component _makeJoystick() => JoystickInputComponent();
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

import 'package:flutter/painting.dart';
import 'package:just_game_engine/just_game_engine.dart';

import '../generator/component_registry.dart';
import '../../services/component_source_index.dart';

/// A single entry in the component picker catalogue.
class ComponentEntry {
  const ComponentEntry({
    required this.name,
    required this.group,
    required this.description,
    required this.factory,
    this.componentTypeName,
    this.sourcePath,
    this.isCustom = false,
    this.isEditorComponent = false,
  });

  final String name;
  final String group;
  final String description;
  final String? componentTypeName;
  final String? sourcePath;
  final bool isCustom;
  final bool isEditorComponent;

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

class _BuiltInComponentDefinition {
  const _BuiltInComponentDefinition({
    required this.componentTypeName,
    required this.factory,
  });

  final String componentTypeName;
  final Component Function() factory;
}

final Map<String, _BuiltInComponentDefinition> _builtInComponentDefinitions =
    <String, _BuiltInComponentDefinition>{
      'TransformComponent': _BuiltInComponentDefinition(
        componentTypeName: 'TransformComponent',
        factory: _makeTransform,
      ),
      'VelocityComponent': _BuiltInComponentDefinition(
        componentTypeName: 'VelocityComponent',
        factory: _makeVelocity,
      ),
      'RectangleComponent': _BuiltInComponentDefinition(
        componentTypeName: 'RectangleComponent',
        factory: _makeRectangle,
      ),
      'CircleComponent': _BuiltInComponentDefinition(
        componentTypeName: 'CircleComponent',
        factory: _makeCircle,
      ),
      'CapsuleComponent': _BuiltInComponentDefinition(
        componentTypeName: 'CapsuleComponent',
        factory: _makeCapsule,
      ),
      'SpriteComponent': _BuiltInComponentDefinition(
        componentTypeName: 'SpriteComponent',
        factory: _makeSprite,
      ),
      'LineComponent': _BuiltInComponentDefinition(
        componentTypeName: 'LineComponent',
        factory: _makeLine,
      ),
      'PolygonComponent': _BuiltInComponentDefinition(
        componentTypeName: 'PolygonComponent',
        factory: _makePolygon,
      ),
      'PhysicsBodyCircle': _BuiltInComponentDefinition(
        componentTypeName: 'PhysicsBodyComponent',
        factory: _makePhysicsBodyCircle,
      ),
      'PhysicsBodyRectangle': _BuiltInComponentDefinition(
        componentTypeName: 'PhysicsBodyComponent',
        factory: _makePhysicsBodyRectangle,
      ),
      'PhysicsBodyPolygon': _BuiltInComponentDefinition(
        componentTypeName: 'PhysicsBodyComponent',
        factory: _makePhysicsBodyPolygon,
      ),
      'PhysicsBodyCapsule': _BuiltInComponentDefinition(
        componentTypeName: 'PhysicsBodyComponent',
        factory: _makePhysicsBodyCapsule,
      ),
      'PhysicsBodySegment': _BuiltInComponentDefinition(
        componentTypeName: 'PhysicsBodyComponent',
        factory: _makePhysicsBodySegment,
      ),
      'PhysicsBodyChain': _BuiltInComponentDefinition(
        componentTypeName: 'PhysicsBodyComponent',
        factory: _makePhysicsBodyChain,
      ),
      'PhysicsBodyRoundedRect': _BuiltInComponentDefinition(
        componentTypeName: 'PhysicsBodyComponent',
        factory: _makePhysicsBodyRoundedRect,
      ),
      'PhysicsSensorCircle': _BuiltInComponentDefinition(
        componentTypeName: 'PhysicsBodyComponent',
        factory: _makePhysicsSensorCircle,
      ),
      'PhysicsSensorRectangle': _BuiltInComponentDefinition(
        componentTypeName: 'PhysicsBodyComponent',
        factory: _makePhysicsSensorRectangle,
      ),
      'PhysicsSensorCapsule': _BuiltInComponentDefinition(
        componentTypeName: 'PhysicsBodyComponent',
        factory: _makePhysicsSensorCapsule,
      ),
      'HealthComponent': _BuiltInComponentDefinition(
        componentTypeName: 'HealthComponent',
        factory: _makeHealth,
      ),
      'TagComponent': _BuiltInComponentDefinition(
        componentTypeName: 'TagComponent',
        factory: _makeTag,
      ),
      'LifetimeComponent': _BuiltInComponentDefinition(
        componentTypeName: 'LifetimeComponent',
        factory: _makeLifetime,
      ),
      'InputComponent': _BuiltInComponentDefinition(
        componentTypeName: 'InputComponent',
        factory: _makeInput,
      ),
      'JoystickInputComponent': _BuiltInComponentDefinition(
        componentTypeName: 'JoystickInputComponent',
        factory: _makeJoystick,
      ),
      'CameraFollowComponent': _BuiltInComponentDefinition(
        componentTypeName: 'CameraFollowComponent',
        factory: _makeCameraFollow,
      ),
      'AudioSourceComponent': _BuiltInComponentDefinition(
        componentTypeName: 'AudioSourceComponent',
        factory: _makeAudioSource,
      ),
      'AudioStreamComponent': _BuiltInComponentDefinition(
        componentTypeName: 'AudioStreamComponent',
        factory: _makeAudioStream,
      ),
      'AnimationStateComponent': _BuiltInComponentDefinition(
        componentTypeName: 'AnimationStateComponent',
        factory: _makeAnimationState,
      ),
      'ChildrenComponent': _BuiltInComponentDefinition(
        componentTypeName: 'ChildrenComponent',
        factory: _makeChildren,
      ),
      'ParentComponent': _BuiltInComponentDefinition(
        componentTypeName: 'ParentComponent',
        factory: _makeParent,
      ),
      'EffectComponent': _BuiltInComponentDefinition(
        componentTypeName: 'EffectComponent',
        factory: _makeEffect,
      ),
      'UIComponent': _BuiltInComponentDefinition(
        componentTypeName: 'UIComponent',
        factory: _makeUI,
      ),
      'TextComponent': _BuiltInComponentDefinition(
        componentTypeName: 'TextComponent',
        factory: _makeText,
      ),
      'ButtonComponent': _BuiltInComponentDefinition(
        componentTypeName: 'ButtonComponent',
        factory: _makeButton,
      ),
      'LinearProgressComponent': _BuiltInComponentDefinition(
        componentTypeName: 'LinearProgressComponent',
        factory: _makeLinearProgress,
      ),
      'CircularProgressComponent': _BuiltInComponentDefinition(
        componentTypeName: 'CircularProgressComponent',
        factory: _makeCircularProgress,
      ),
    };

/// Returns editor catalogue entries driven purely by source-scanned
/// XxxEditorComponent classes. Registry descriptors are used only for
/// factory lookup — they never add extra picker rows.
List<ComponentEntry> getComponentRegistryEntries() {
  final entries = <ComponentEntry>[];
  final descriptorByType = <String, EditorComponentDescriptor>{
    for (final descriptor in CustomComponentRegistry.instance.descriptors)
      descriptor.type: descriptor,
  };

  for (final discovered in ComponentSourceIndex.instance.discoveredComponents) {
    final builtIn =
        _builtInComponentDefinitions[discovered.typeName] ??
        _builtInComponentDefinitions[discovered.displayName];

    // For XxxEditorComponent classes the descriptor is keyed by the base type.
    final baseTypeName = discovered.typeName.endsWith('EditorComponent')
        ? discovered.typeName.replaceFirst('EditorComponent', 'Component')
        : null;
    final runtimeDescriptor = descriptorByType[discovered.typeName] ??
        (baseTypeName != null ? descriptorByType[baseTypeName] : null);

    entries.add(
      ComponentEntry(
        name: discovered.displayName,
        group: discovered.group,
        description: discovered.description,
        factory:
            builtIn?.factory ??
            (runtimeDescriptor != null
                ? () => runtimeDescriptor.factory()
                : () => throw UnsupportedError(
                    'Custom component factory is unavailable until generation completes.',
                  )),
        componentTypeName: builtIn?.componentTypeName ??
            runtimeDescriptor?.type ??
            discovered.typeName,
        sourcePath: discovered.sourcePath,
        isCustom: builtIn == null,
        isEditorComponent: discovered.isEditorComponent,
      ),
    );
  }

  return entries;
}

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

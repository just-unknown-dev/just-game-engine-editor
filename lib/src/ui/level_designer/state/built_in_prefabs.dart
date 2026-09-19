import 'package:flutter/material.dart';
import 'package:just_game_engine/just_game_engine.dart' as jge;

import '../../../extension/designer_contributions.dart';
import 'prefab_registry.dart';

/// The palette the editor ships with.
///
/// Deliberately genre-neutral: a shape, a sprite, a label, a solid, a trigger,
/// a camera, a spawn point. Nothing here knows whether the game is a
/// platformer, a top-down shooter or a puzzle — those concepts arrive through
/// an [EditorModule].
///
/// This is the floor, not the ceiling. A project registers its own prefabs
/// alongside these, and can replace one outright by reusing its id.
abstract final class BuiltInPrefabs {
  /// Plain geometry and annotations.
  static const Color shapeColor = Color(0xFF6D8A99);

  /// Things that collide.
  static const Color solidColor = Color(0xFF546E7A);

  /// Things that detect without colliding.
  static const Color triggerColor = Color(0xFF26A69A);

  /// Scene infrastructure: cameras, spawn points, markers.
  static const Color sceneColor = Color(0xFF7E57C2);

  /// Ids of the prefabs the editor provides.
  static const String rectangleId = 'builtin.rectangle';
  static const String circleId = 'builtin.circle';
  static const String spriteId = 'builtin.sprite';
  static const String textId = 'builtin.text';
  static const String emptyId = 'builtin.empty';
  static const String solidId = 'builtin.solid';
  static const String triggerId = 'builtin.trigger';
  static const String cameraId = 'builtin.camera';
  static const String spawnId = 'builtin.spawn';
  static const String markerId = 'builtin.marker';

  /// The palette groups the built-ins use, in display order.
  static const List<PrefabCategory> categories = [
    PrefabCategory(label: 'Shapes', order: 0),
    PrefabCategory(label: 'Physics', order: 10),
    PrefabCategory(label: 'Scene', order: 20),
  ];

  /// Every built-in prefab, in palette order.
  static List<PrefabDefinition> get all => [
    _rectangle,
    _circle,
    _sprite,
    _text,
    _empty,
    _solid,
    _trigger,
    _camera,
    _spawn,
    _marker,
  ];

  /// Registers every built-in prefab into [registry].
  static void registerAll(PrefabRegistry registry) => registry.registerAll(all);

  /// Transform plus a layer — the minimum every placed entity carries.
  static List<jge.Component> _base(Offset position) => [
    jge.TransformComponent(position: jge.Vector3(position.dx, position.dy, 0)),
    jge.LayerComponent(),
  ];

  static jge.RectangleComponent _rect(
    Size size,
    Color color, {
    bool filled = true,
  }) => jge.RectangleComponent(
    width: size.width,
    height: size.height,
    filled: filled,
    fillStyle: jge.ShapePaintStyle(
      color: filled ? color : color.withValues(alpha: 0.12),
    ),
    strokeStyle: jge.ShapePaintStyle(
      color: Color.lerp(color, const Color(0xFFFFFFFF), 0.35)!,
    ),
    strokeWidth: 2,
  );

  // ── Shapes ────────────────────────────────────────────────────────────────

  static final _rectangle = PrefabDefinition(
    id: rectangleId,
    name: 'Rectangle',
    category: 'Shapes',
    icon: Icons.crop_16_9,
    color: shapeColor,
    description: 'A plain filled rectangle. No collider.',
    namePrefix: 'Rect',
    build: (position, size) => [..._base(position), _rect(size, shapeColor)],
  );

  static final _circle = PrefabDefinition(
    id: circleId,
    name: 'Circle',
    category: 'Shapes',
    icon: Icons.circle_outlined,
    color: shapeColor,
    defaultSize: const Size(64, 64),
    description: 'A plain filled circle. No collider.',
    namePrefix: 'Circle',
    build: (position, size) => [
      ..._base(position),
      // Sized by the smaller axis, so a drag that is not square still gives a
      // circle that fits inside what was drawn.
      jge.CircleComponent(
        radius: (size.width < size.height ? size.width : size.height) / 2,
        fillStyle: const jge.ShapePaintStyle(color: shapeColor),
        strokeWidth: 2,
      ),
    ],
  );

  static final _sprite = PrefabDefinition(
    id: spriteId,
    name: 'Sprite',
    category: 'Shapes',
    icon: Icons.image_outlined,
    color: shapeColor,
    defaultSize: const Size(64, 64),
    description: 'An image. Set its asset path in the inspector.',
    namePrefix: 'Sprite',
    build: (position, size) => [
      ..._base(position),
      // Placeholder outline so it is visible before an asset is chosen —
      // otherwise a freshly placed sprite is an invisible entity.
      _rect(size, shapeColor, filled: false),
      jge.SpriteComponent(spritePath: ''),
    ],
  );

  static final _text = PrefabDefinition(
    id: textId,
    name: 'Text',
    category: 'Shapes',
    icon: Icons.text_fields,
    color: shapeColor,
    placement: PrefabPlacement.point,
    defaultSize: const Size(160, 32),
    description: 'A text label.',
    namePrefix: 'Text',
    build: (position, size) => [
      ..._base(position),
      jge.TextComponent(text: 'Text', size: size),
    ],
  );

  // ── Physics ───────────────────────────────────────────────────────────────

  static final _solid = PrefabDefinition(
    id: solidId,
    name: 'Solid',
    category: 'Physics',
    icon: Icons.rectangle,
    color: solidColor,
    description: 'A static rectangular collider. Walls, floors, obstacles.',
    namePrefix: 'Solid',
    build: (position, size) => [
      ..._base(position),
      _rect(size, solidColor),
      jge.PhysicsBodyComponent(
        shape: jge.RectangleShape(size.width, size.height),
        isStatic: true,
        fixedRotation: true,
        restitution: 0,
      ),
    ],
  );

  static final _trigger = PrefabDefinition(
    id: triggerId,
    name: 'Trigger',
    category: 'Physics',
    icon: Icons.select_all,
    color: triggerColor,
    description: 'A sensor volume — detects overlap without blocking movement.',
    namePrefix: 'Trigger',
    build: (position, size) => [
      ..._base(position),
      // Outline only: a trigger is an authoring concept, and a solid fill
      // would read as geometry in the viewport.
      _rect(size, triggerColor, filled: false),
      jge.PhysicsBodyComponent(
        shape: jge.RectangleShape(size.width, size.height),
        isStatic: true,
        isSensor: true,
        fixedRotation: true,
      ),
    ],
  );

  // ── Scene ─────────────────────────────────────────────────────────────────

  static final _empty = PrefabDefinition(
    id: emptyId,
    name: 'Empty',
    category: 'Scene',
    icon: Icons.add_circle_outline,
    color: sceneColor,
    placement: PrefabPlacement.point,
    defaultSize: const Size(32, 32),
    description: 'A transform with nothing on it — a parent or an anchor.',
    namePrefix: 'Entity',
    build: (position, size) => [
      jge.TransformComponent(
        position: jge.Vector3(position.dx, position.dy, 0),
      ),
    ],
  );

  static final _camera = PrefabDefinition(
    id: cameraId,
    name: 'Camera',
    category: 'Scene',
    icon: Icons.videocam_outlined,
    color: sceneColor,
    placement: PrefabPlacement.point,
    defaultSize: const Size(48, 48),
    description: 'A camera. Set its zoom and bounds in the inspector.',
    namePrefix: 'Camera',
    build: (position, size) => [
      jge.TransformComponent(
        position: jge.Vector3(position.dx, position.dy, 0),
      ),
      jge.CameraComponent(),
    ],
  );

  static final _spawn = PrefabDefinition(
    id: spawnId,
    name: 'Spawn Point',
    category: 'Scene',
    icon: Icons.person_pin_circle_outlined,
    color: sceneColor,
    placement: PrefabPlacement.point,
    defaultSize: const Size(32, 32),
    description: 'Where a spawner places an entity. Tagged in the inspector.',
    namePrefix: 'Spawn',
    build: (position, size) => [..._base(position), jge.SpawnComponent()],
  );

  static final _marker = PrefabDefinition(
    id: markerId,
    name: 'Region',
    category: 'Scene',
    icon: Icons.crop_free,
    color: sceneColor,
    defaultSize: const Size(256, 256),
    description: 'An annotation rectangle. No collider, no rendering in game.',
    namePrefix: 'Region',
    build: (position, size) => [
      jge.TransformComponent(
        position: jge.Vector3(position.dx, position.dy, 0),
      ),
      jge.LayerComponent(),
      _rect(size, sceneColor, filled: false),
    ],
  );
}

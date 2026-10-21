import 'package:flutter/material.dart';
import 'package:just_game_engine/just_game_engine.dart' as jge;

import '../../../extension/built_in_audio_contributions.dart';
import '../../../extension/built_in_lighting_2d_contributions.dart';
import 'package:just_editor_core/host.dart';

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
  static const Color shapeColor = PrefabColours.shape;

  /// Things that collide.
  static const Color solidColor = PrefabColours.solid;

  /// Things that detect without colliding.
  static const Color triggerColor = PrefabColours.trigger;

  /// Scene infrastructure: cameras, spawn points, markers.
  static const Color sceneColor = PrefabColours.scene;

  /// Id of Rectangle: a plain filled rectangle, no collider.
  ///
  /// The ids below are the built-in prefabs'; a module's prefab with the
  /// same id takes that one's place.
  static const String rectangleId = 'builtin.rectangle';

  /// Id of Circle: a plain filled circle, no collider.
  static const String circleId = 'builtin.circle';

  /// Id of Sprite: an image, its asset set in the inspector.
  static const String spriteId = 'builtin.sprite';

  /// Id of Empty: a transform with nothing on it, a parent or an anchor.
  static const String emptyId = 'builtin.empty';

  /// Id of Solid: a static body matching its rectangle (walls, floors).
  static const String solidId = 'builtin.solid';

  /// Id of Trigger: a sensor that detects overlap without blocking.
  static const String triggerId = 'builtin.trigger';

  /// Id of Virtual camera: a shot the game can show; the
  /// highest-priority enabled camera is live.
  static const String cameraId = 'builtin.camera';

  /// Id of Camera zone: a shot of its own while its target is inside the
  /// rectangle.
  static const String cameraZoneId = 'builtin.camera_zone';

  /// Id of Camera bounds: the area a camera may show, named in a camera's
  /// Confiner.
  static const String cameraBoundsId = 'builtin.camera_bounds';

  /// Id of Target group: sits at the centre of its members, so a camera
  /// following it frames them all.
  static const String targetGroupId = 'builtin.target_group';

  /// Id of Dolly camera: a camera that rides a track to the point nearest
  /// what it follows.
  static const String dollyCameraId = 'builtin.dolly_camera';

  /// Id of Spawn Point: where a spawner places an entity when Play is
  /// pressed.
  static const String spawnId = 'builtin.spawn';

  /// Id of Region: an annotation rectangle, an outline with no collider.
  static const String markerId = 'builtin.marker';

  /// A new map: [tileSize]-square cells and one layer, `Ground`, whose
  /// tiles collide. What the scene's Level Map starts as.
  static jge.LevelMapData newLevelMap({int tileSize = 32}) {
    final map = jge.LevelMapData(tileWidth: tileSize, tileHeight: tileSize);
    map.addLayer(name: 'Ground').collides = true;
    return map;
  }

  /// The palette groups the built-ins use, in display order.
  static const List<PrefabCategory> categories = [
    PrefabCategory(label: 'Shapes', order: 0),
    PrefabCategory(label: 'Physics', order: 10),
    PrefabCategory(label: 'Scene', order: 20),
    PrefabCategory(label: 'Camera', order: 25),
    BuiltInAudioContributions.category,
    BuiltInLighting2DContributions.category,
  ];

  /// Every built-in prefab, in palette order.
  static List<PrefabDefinition> get all => [
    _rectangle,
    _circle,
    _sprite,
    _empty,
    _solid,
    _trigger,
    _camera,
    _cameraZone,
    _cameraBounds,
    _targetGroup,
    _dollyCamera,
    _spawn,
    _marker,
    ...BuiltInAudioContributions.prefabs,
    ...BuiltInLighting2DContributions.prefabs,
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

  static PrefabDefinition get _rectangle => PrefabDefinition(
    id: rectangleId,
    name: 'Rectangle',
    category: 'Shapes',
    icon: Icons.crop_16_9,
    color: shapeColor,
    description: 'A plain filled rectangle. No collider.',
    namePrefix: 'Rect',
    build: (position, size) => [..._base(position), _rect(size, shapeColor)],
  );

  static PrefabDefinition get _circle => PrefabDefinition(
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

  static PrefabDefinition get _sprite => PrefabDefinition(
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

  // ── Physics ───────────────────────────────────────────────────────────────

  static PrefabDefinition get _solid => PrefabDefinition(
    id: solidId,
    name: 'Solid',
    category: 'Physics',
    icon: Icons.rectangle,
    color: solidColor,
    description:
        'A static body matching its rectangle. Walls, floors, obstacles.',
    namePrefix: 'Solid',
    build: (position, size) => [
      ..._base(position),
      _rect(size, solidColor),
      jge.RigidBody2D(
        bodyType: jge.BodyType.static,
        lockRotation: true,
        restitution: 0,
      ),
      jge.Collider2D(shape: jge.ColliderShape2D.matchShape),
    ],
  );

  static PrefabDefinition get _trigger => PrefabDefinition(
    id: triggerId,
    name: 'Trigger',
    category: 'Physics',
    icon: Icons.select_all,
    color: triggerColor,
    description: 'A sensor volume — detects overlap without blocking movement.',
    namePrefix: 'Trigger',
    build: (position, size) => [
      ..._base(position),
      // Outline only: a solid fill would read as geometry. The outline
      // draws in the game too.
      _rect(size, triggerColor, filled: false),
      jge.RigidBody2D(
        bodyType: jge.BodyType.static,
        isSensor: true,
        lockRotation: true,
      ),
      jge.Collider2D(shape: jge.ColliderShape2D.matchShape),
    ],
  );

  // ── Scene ─────────────────────────────────────────────────────────────────

  static PrefabDefinition get _empty => PrefabDefinition(
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

  static const Color _cameraColor = Color(0xFF26C6DA);

  static PrefabDefinition get _camera => PrefabDefinition(
    id: cameraId,
    name: 'Virtual camera',
    category: 'Camera',
    icon: Icons.videocam_outlined,
    color: _cameraColor,
    placement: PrefabPlacement.point,
    defaultSize: const Size(48, 48),
    description:
        'A shot the game can show. Name what it follows in the inspector; '
        'the highest-priority enabled camera is live.',
    namePrefix: 'Camera',
    build: (position, size) => [
      jge.TransformComponent(
        position: jge.Vector3(position.dx, position.dy, 0),
      ),
      jge.VirtualCameraComponent(),
      jge.CameraFramingComponent(),
    ],
  );

  static PrefabDefinition get _cameraZone => PrefabDefinition(
    id: cameraZoneId,
    name: 'Camera zone',
    category: 'Camera',
    icon: Icons.sensors,
    color: const Color(0xFF7E57C2),
    defaultSize: const Size(640, 360),
    description:
        'A shot of its own while its target is inside the rectangle. Name '
        'the target, the zoom and the framing in the inspector.',
    namePrefix: 'CameraZone',
    build: (position, size) => [
      jge.TransformComponent(
        position: jge.Vector3(position.dx, position.dy, 0),
      ),
      // Off until the trigger turns it on, and above a level's main camera
      // so it wins while it is.
      jge.VirtualCameraComponent(priority: 20, enabled: false),
      jge.CameraFramingComponent(),
      jge.CameraTriggerComponent(
        width: size.width,
        height: size.height,
        target: jge.EntityTarget.none,
      ),
    ],
  );

  static PrefabDefinition get _cameraBounds => PrefabDefinition(
    id: cameraBoundsId,
    name: 'Camera bounds',
    category: 'Camera',
    icon: Icons.border_outer,
    color: const Color(0xFFFFB74D),
    defaultSize: const Size(1280, 720),
    description:
        'The area a camera may show. Name it in a camera\'s Confiner to keep '
        'that camera inside.',
    namePrefix: 'CameraBounds',
    build: (position, size) => [
      jge.TransformComponent(
        position: jge.Vector3(position.dx, position.dy, 0),
      ),
      jge.CameraBoundsComponent(width: size.width, height: size.height),
    ],
  );

  static PrefabDefinition get _targetGroup => PrefabDefinition(
    id: targetGroupId,
    name: 'Target group',
    category: 'Camera',
    icon: Icons.group_work_outlined,
    color: _cameraColor,
    placement: PrefabPlacement.point,
    defaultSize: const Size(48, 48),
    description:
        'Sits at the centre of its members, so a camera that follows it '
        'frames them all.',
    namePrefix: 'TargetGroup',
    build: (position, size) => [
      jge.TransformComponent(
        position: jge.Vector3(position.dx, position.dy, 0),
      ),
      jge.CameraTargetGroupComponent(),
    ],
  );

  static PrefabDefinition get _dollyCamera => PrefabDefinition(
    id: dollyCameraId,
    name: 'Dolly camera',
    category: 'Camera',
    icon: Icons.linear_scale,
    color: const Color(0xFF4FC3F7),
    placement: PrefabPlacement.point,
    defaultSize: const Size(48, 48),
    description:
        'A camera on a track: it rides to the point nearest what it follows. '
        'Edit the track with the Track tool.',
    namePrefix: 'DollyCamera',
    build: (position, size) => [
      jge.TransformComponent(
        position: jge.Vector3(position.dx, position.dy, 0),
      ),
      jge.VirtualCameraComponent(),
      jge.CameraDollyComponent(
        waypoints: [
          position - const Offset(320, 0),
          position + const Offset(320, 0),
        ],
      ),
    ],
  );

  static PrefabDefinition get _spawn => PrefabDefinition(
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

  static PrefabDefinition get _marker => PrefabDefinition(
    id: markerId,
    name: 'Region',
    category: 'Scene',
    icon: Icons.crop_free,
    color: sceneColor,
    defaultSize: const Size(256, 256),
    description:
        'An annotation rectangle: an outline with no collider. It draws in '
        'the game too.',
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

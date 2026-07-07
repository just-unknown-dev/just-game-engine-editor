import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart' show Colors;
import 'package:flutter/painting.dart';
import 'package:just_game_engine/just_game_engine.dart';

import '../ecs/generator/component_registry.dart';
import '../ecs/components/physics/physics_joint_components.dart';
import '../ecs/components/input/simple_movement_component.dart';

/// Writes and reads scene files inside the project's `lib/game/scenes/`
/// directory using [dart:io].
///
/// Each scene lives in its own sub-folder:
/// ```
/// lib/game/scenes/{name}/
///   {name}.level.dart   ← entity spawning code (build(World world))
///   {name}.data.dart    ← level metadata (bounds, playerStart, etc.)
///   {name}.scene.json   ← editor state sidecar (internal use only)
/// ```
///
/// Only usable on native desktop targets in debug mode.
class SceneFileGenerator {
  const SceneFileGenerator._();

  static String get _scenesRoot => '${Directory.current.path}/lib/game/scenes';

  static String _sceneDir(String name) => '$_scenesRoot/$name';
  static String _levelPath(String name) =>
      '${_sceneDir(name)}/$name.level.dart';
  static String _dataPath(String name) => '${_sceneDir(name)}/$name.data.dart';
  static String _jsonPath(String name) => '${_sceneDir(name)}/$name.scene.json';

  // ── Write ────────────────────────────────────────────────────────────────

  /// Creates `lib/game/scenes/{name}/` if it does not exist.
  static Future<void> _ensureDir(String name) async {
    final dir = Directory(_sceneDir(name));
    if (!dir.existsSync()) await dir.create(recursive: true);
  }

  /// Writes the initial stub files when a scene is first created.
  ///
  /// Each file is only written if it does not already exist, so opening
  /// an existing scene never overwrites saved content.
  static Future<void> writeInitialFiles(String sceneName) async {
    await _ensureDir(sceneName);
    final levelFile = File(_levelPath(sceneName));
    final dataFile = File(_dataPath(sceneName));
    final jsonFile = File(_jsonPath(sceneName));
    await Future.wait([
      if (!levelFile.existsSync())
        levelFile.writeAsString(_buildBlankLevel(sceneName)),
      if (!dataFile.existsSync())
        dataFile.writeAsString(_buildDataTemplate(sceneName)),
      // Bootstraps the scene camera entity into the editor's live authoring
      // world immediately — openScene() only spawns entities from this
      // sidecar, it never executes the generated .level.dart.
      if (!jsonFile.existsSync())
        jsonFile.writeAsString(_buildInitialSidecar(sceneName)),
    ]);
  }

  /// Builds the `.scene.json` sidecar for a brand-new scene: a single
  /// "MainCamera" entity, matching what [_buildBlankLevel] generates.
  static String _buildInitialSidecar(String sceneName) {
    final scene = Scene(name: sceneName);
    final transform = TransformComponent(position: Vector3(2000, 400, 0));
    final camera = CameraComponent(bounds: const Rect.fromLTWH(0, 0, 4000, 800));
    final entityJson = <String, dynamic>{
      'name': 'MainCamera',
      'parentName': null,
      'components': [componentToJson(transform), componentToJson(camera)]
          .whereType<Map<String, dynamic>>()
          .toList(),
    };
    final data = <String, dynamic>{
      ...scene.toJson(),
      'entities': [entityJson],
    };
    return const JsonEncoder.withIndent('  ').convert(data);
  }

  /// Regenerates `{name}.level.dart` from [entities] currently in the world.
  ///
  /// Call this on every "Save" press so the dart file stays in sync with the
  /// editor's entity list.
  static Future<void> writeLevelFromEntities(
    String sceneName,
    List<Entity> entities,
  ) async {
    await _ensureDir(sceneName);
    final code = _buildLevelDart(sceneName, entities);
    await File(_levelPath(sceneName)).writeAsString(code);
  }

  /// Serialises [scene] + [entities] as pretty JSON and writes the `.scene.json`
  /// sidecar.  The entity list is stored so the editor can rehydrate the world
  /// on the next `openScene` call without requiring a live level load.
  static Future<void> writeJsonSidecar(
    String sceneName,
    Scene scene,
    List<Entity> entities,
  ) async {
    await _ensureDir(sceneName);
    final activeEntities = entities.where((e) => e.isActive).toList();
    final entityNameMap = {
      for (final e in activeEntities) e.id: e.name ?? 'entity_${e.id}',
    };
    final entitiesJson = activeEntities.map((e) {
      final pc = e.getComponent<ParentComponent>();
      return {
        'name': e.name,
        'parentName': pc?.parentId != null ? entityNameMap[pc!.parentId] : null,
        'components': e.components
            .map(componentToJson)
            .whereType<Map<String, dynamic>>()
            .toList(),
      };
    }).toList();
    final data = <String, dynamic>{...scene.toJson(), 'entities': entitiesJson};
    final json = const JsonEncoder.withIndent('  ').convert(data);
    await File(_jsonPath(sceneName)).writeAsString(json);
  }

  // ── Read ─────────────────────────────────────────────────────────────────

  /// Loads the raw JSON map for [sceneName]'s sidecar, or `null` if missing.
  static Future<Map<String, dynamic>?> loadRawSidecar(String sceneName) async {
    final file = File(_jsonPath(sceneName));
    if (!file.existsSync()) return null;
    try {
      return jsonDecode(await file.readAsString()) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  /// Loads the `.scene.json` sidecar for [sceneName], or `null` if missing.
  static Future<Scene?> loadFromSidecar(String sceneName) async {
    final raw = await loadRawSidecar(sceneName);
    if (raw == null) return null;
    try {
      return Scene.fromJson(raw);
    } catch (_) {
      return null;
    }
  }

  /// Returns the names of all scene folders inside `lib/game/scenes/`.
  static List<String> listSceneNames() {
    final dir = Directory(_scenesRoot);
    if (!dir.existsSync()) return [];
    return dir
        .listSync()
        .whereType<Directory>()
        .map((d) => d.path.split(RegExp(r'[/\\]')).last)
        .where((name) => name.isNotEmpty)
        .toList();
  }

  // ── Code generation ───────────────────────────────────────────────────────

  static String _buildBlankLevel(String sceneName) {
    final cls = _toPascalCase(sceneName);
    return '''
// AUTO-GENERATED by Just Runtime Editor — do not edit the header.
// Scene folder: lib/game/scenes/$sceneName/
//
// The editor regenerates this file on every Save. Add entities via the
// editor panel and press Save, then hot-reload to see changes in-game.

import 'package:flutter/painting.dart';
import 'package:just_game_engine/just_game_engine.dart';

// ignore_for_file: unused_import

/// Spawns all entities for the "$sceneName" scene into [world].
class ${cls}Level {
  const ${cls}Level._();

  static void build(World world) {
    // Scene camera — auto-created for new scenes. CameraTransformSyncSystem
    // drives the main camera from this entity every frame; its CameraComponent
    // also defines world bounds for the boundary/death systems.
    world.createEntityWithComponents([
      TransformComponent(position: Vector3(2000, 400, 0)),
      CameraComponent(bounds: Rect.fromLTWH(0, 0, 4000, 800)),
    ], name: 'MainCamera');
  }
}
''';
  }

  static String _buildDataTemplate(String sceneName) {
    final cls = _toPascalCase(sceneName);
    return '''
// AUTO-GENERATED by Just Runtime Editor.
// Edit scene metadata (bounds, player start, etc.) here.

import 'package:flutter/painting.dart';
import 'package:just_game_engine/just_game_engine.dart';

/// Metadata for the "$sceneName" scene.
class ${cls}Data {
  const ${cls}Data._();

  static const String sceneName = '$sceneName';
  static const Rect bounds = Rect.fromLTWH(0, 0, 4000, 800);
  static final Vector3 playerStart = Vector3(200, 400, 0);
}
''';
  }

  static String _buildLevelDart(String sceneName, List<Entity> entities) {
    final cls = _toPascalCase(sceneName);
    final buf = StringBuffer();

    buf.writeln('''
// AUTO-GENERATED by Just Runtime Editor — do not edit the header.
// Scene folder: lib/game/scenes/$sceneName/
//
// Regenerated on save. Hot-reload after saving to see changes in-game.

import 'package:flutter/material.dart';
import 'package:flutter/painting.dart';
import 'package:just_game_engine/just_game_engine.dart';

// ignore_for_file: unused_import

/// Spawns all entities for the "$sceneName" scene into [world].
class ${cls}Level {
  const ${cls}Level._();

  static void build(World world) {''');

    for (final entity in entities) {
      if (!entity.isActive) continue;
      final components = entity.components.toList();
      if (components.isEmpty) continue;

      buf.writeln();
      buf.writeln('    // ${entity.name ?? "entity_${entity.id}"}');
      buf.writeln('    world.createEntityWithComponents([');
      for (final c in components) {
        final code = _componentToCode(c);
        buf.writeln('      $code,');
      }
      final nameStr = entity.name != null ? "'${entity.name}'" : 'null';
      buf.writeln('    ], name: $nameStr);');
    }

    // Emit parent-child linkage block so hierarchy is live after build().
    final childParentPairs = <(String, String)>[];
    for (final entity in entities) {
      if (!entity.isActive) continue;
      final pc = entity.getComponent<ParentComponent>();
      if (pc?.parentId == null) continue;
      final parentName = entities
          .where((e) => e.id == pc!.parentId!)
          .map((e) => e.name ?? 'entity_${e.id}')
          .firstOrNull;
      if (parentName != null) {
        childParentPairs.add((
          entity.name ?? 'entity_${entity.id}',
          parentName,
        ));
      }
    }
    if (childParentPairs.isNotEmpty) {
      buf.writeln();
      buf.writeln(
        '    // ── Hierarchy linkage ──────────────────────────────────────',
      );
      buf.writeln(
        '    final _nm = { for (final e in world.activeEntities) e.name: e };',
      );
      for (final (child, parent) in childParentPairs) {
        buf.writeln(
          "    _nm['$parent']?.getComponent<ChildrenComponent>()?.addChild(_nm['$child']!.id);",
        );
        buf.writeln(
          "    _nm['$child']?.getComponent<ParentComponent>()?.parentId = _nm['$parent']!.id;",
        );
      }
    }

    buf.writeln('  }');
    buf.writeln('}');

    return buf.toString();
  }

  // ── Component → Dart code ────────────────────────────────────────────────

  static String _componentToCode(Component c) {
    // Core
    if (c is TransformComponent) {
      final pos = 'Vector3.fromXY(${_d(c.position.x)}, ${_d(c.position.y)})';
      final rot = c.rotation != 0 ? ', rotation: ${_d(c.rotation)}' : '';
      final isDefaultScale = c.scale.x == 1.0 && c.scale.y == 1.0;
      final scl = isDefaultScale
          ? ''
          : ', scale: Vector3(${_d(c.scale.x)}, ${_d(c.scale.y)}, ${_d(c.scale.z)})';
      return 'TransformComponent(position: $pos$rot$scl)';
    }
    if (c is VelocityComponent) {
      final vel = (c.velocity.x != 0 || c.velocity.y != 0 || c.velocity.z != 0)
          ? 'velocity: Vector3(${_d(c.velocity.x)}, ${_d(c.velocity.y)}, ${_d(c.velocity.z)}), '
          : '';
      return 'VelocityComponent(${vel}maxSpeed: ${_d(c.maxSpeed)})';
    }

    // Shapes
    if (c is RectangleComponent) {
      final fillStyle = _shapeStyleArg(
        'fillStyle',
        c.fillStyle,
        defaultColor: Colors.white,
      );
      final strokeStyle = _shapeStyleArg(
        'strokeStyle',
        c.strokeStyle,
        defaultColor: const Color(0x73FFFFFF),
      );
      final fil = !c.filled ? ', filled: false' : '';
      final sw = c.strokeWidth != 1.0
          ? ', strokeWidth: ${_d(c.strokeWidth)}'
          : '';
      final cr = c.cornerRadius != 0.0
          ? ', cornerRadius: ${_d(c.cornerRadius)}'
          : '';
      return 'RectangleComponent(width: ${_d(c.width)}, height: ${_d(c.height)}$fillStyle$strokeStyle$fil$sw$cr)';
    }
    if (c is CircleComponent) {
      final fillStyle = _shapeStyleArg(
        'fillStyle',
        c.fillStyle,
        defaultColor: Colors.white,
      );
      final strokeStyle = _shapeStyleArg(
        'strokeStyle',
        c.strokeStyle,
        defaultColor: const Color(0x73FFFFFF),
      );
      final fil = !c.filled ? ', filled: false' : '';
      final sw = c.strokeWidth != 1.0
          ? ', strokeWidth: ${_d(c.strokeWidth)}'
          : '';
      return 'CircleComponent(radius: ${_d(c.radius)}$fillStyle$strokeStyle$fil$sw)';
    }
    if (c is CapsuleComponent) {
      final fillStyle = _shapeStyleArg(
        'fillStyle',
        c.fillStyle,
        defaultColor: Colors.white,
      );
      final strokeStyle = _shapeStyleArg(
        'strokeStyle',
        c.strokeStyle,
        defaultColor: const Color(0x73FFFFFF),
      );
      final fil = !c.filled ? ', filled: false' : '';
      final sw = c.strokeWidth != 1.0
          ? ', strokeWidth: ${_d(c.strokeWidth)}'
          : '';
      return 'CapsuleComponent(width: ${_d(c.width)}, height: ${_d(c.height)}$fillStyle$strokeStyle$fil$sw)';
    }
    if (c is LineComponent) {
      final strokeStyle = _shapeStyleArg(
        'strokeStyle',
        c.strokeStyle,
        defaultColor: Colors.white,
      );
      final st = 'start: Offset(${_d(c.start.dx)}, ${_d(c.start.dy)})';
      final en = 'end: Offset(${_d(c.end.dx)}, ${_d(c.end.dy)})';
      final sw = c.strokeWidth != 1.0
          ? ', strokeWidth: ${_d(c.strokeWidth)}'
          : '';
      final rc = c.roundCaps ? ', roundCaps: true' : '';
      return 'LineComponent($st, $en$strokeStyle$sw$rc)';
    }
    if (c is PolygonComponent) {
      final verts = c.vertices
          .map((v) => 'Offset(${_d(v.dx)}, ${_d(v.dy)})')
          .join(', ');
      final fillStyle = _shapeStyleArg(
        'fillStyle',
        c.fillStyle,
        defaultColor: Colors.white,
      );
      final strokeStyle = _shapeStyleArg(
        'strokeStyle',
        c.strokeStyle,
        defaultColor: const Color(0x73FFFFFF),
      );
      final fil = !c.filled ? ', filled: false' : '';
      final sw = c.strokeWidth != 1.0
          ? ', strokeWidth: ${_d(c.strokeWidth)}'
          : '';
      return 'PolygonComponent(vertices: [$verts]$fillStyle$strokeStyle$fil$sw)';
    }
    if (c is SpriteComponent) {
      return "SpriteComponent(spritePath: '${c.spritePath}')";
    }

    // Gameplay
    if (c is TagComponent) {
      return "TagComponent('${c.tag}')";
    }
    if (c is HealthComponent) {
      final hp = c.health != c.maxHealth ? ', health: ${_d(c.health)}' : '';
      final inv = c.isInvulnerable ? ', isInvulnerable: true' : '';
      return 'HealthComponent(maxHealth: ${_d(c.maxHealth)}$hp$inv)';
    }
    if (c is LifetimeComponent) {
      return 'LifetimeComponent(${_d(c.initialLifetime)})';
    }

    if (c is PhysicsBodyComponent) {
      return 'PhysicsBodyComponent('
          'shape: ${_physicsShapeCode(c.shape)}, '
          'mass: ${_d(c.mass)}, '
          'restitution: ${_d(c.restitution)}, '
          'drag: ${_d(c.drag)}, '
          'isStatic: ${c.isStatic}, '
          'layer: ${c.layer}, '
          'collisionMask: ${c.collisionMask}, '
          'isOneWay: ${c.isOneWay}, '
          'isSensor: ${c.isSensor}, '
          'categoryBits: ${c.categoryBits}, '
          'maskBits: ${c.maskBits}, '
          'groupIndex: ${c.groupIndex})';
    }
    if (c is DistanceJointComponent) {
      return "// TODO: DistanceJointComponent(target: '${c.targetEntityName}')";
    }
    if (c is WeldJointComponent) {
      return "// TODO: WeldJointComponent(target: '${c.targetEntityName}')";
    }
    if (c is PrismaticJointComponent) {
      return "// TODO: PrismaticJointComponent(target: '${c.targetEntityName}')";
    }
    if (c is WheelJointComponent) {
      return "// TODO: WheelJointComponent(target: '${c.targetEntityName}')";
    }

    // Input / Camera
    if (c is InputComponent) return 'InputComponent()';
    if (c is CameraFollowComponent) {
      final en = c.enabled ? '' : 'enabled: false, ';
      final la = c.lookaheadDistance != 80.0
          ? 'lookaheadDistance: ${_d(c.lookaheadDistance)}, '
          : '';
      return 'CameraFollowComponent($en$la)'.replaceAll(RegExp(r', \)$'), ')');
    }
    if (c is CameraComponent) {
      final z = c.zoom != 1.0 ? 'zoom: ${_d(c.zoom)}, ' : '';
      return 'CameraComponent(${z}bounds: Rect.fromLTWH(${_d(c.bounds.left)}, '
          '${_d(c.bounds.top)}, ${_d(c.bounds.width)}, ${_d(c.bounds.height)}))';
    }

    // Hierarchy
    if (c is InputComponent) return 'InputComponent()';
    if (c is ChildrenComponent) return 'ChildrenComponent()';
    if (c is ParentComponent) {
      final lo = c.localOffset;
      final loStr = (lo.x == 0 && lo.y == 0)
          ? ''
          : 'localOffset: Vector3(${_d(lo.x)}, ${_d(lo.y)}, 0), ';
      final lr = c.localRotation != 0
          ? 'localRotation: ${_d(c.localRotation)}, '
          : '';
      return 'ParentComponent($loStr$lr)'.replaceAll(RegExp(r', \)$'), ')');
    }

    if (c is EffectComponent) return 'EffectComponent()';

    if (c is AnimationStateComponent) {
      return "AnimationStateComponent(currentAnimation: '${c.currentAnimation}', "
          'frameCount: ${c.frameCount}, frameDuration: ${_d(c.frameDuration)})';
    }

    // UI
    if (c is TextComponent) {
      return "TextComponent(text: '${c.text}', "
          'size: Size(${_d(c.size.width)}, ${_d(c.size.height)}))';
    }
    if (c is ButtonComponent) {
      return "ButtonComponent(text: '${c.text}', "
          'size: Size(${_d(c.size.width)}, ${_d(c.size.height)}))';
    }
    if (c is LinearProgressComponent) {
      return 'LinearProgressComponent('
          'size: Size(${_d(c.size.width)}, ${_d(c.size.height)}))';
    }
    if (c is CircularProgressComponent) {
      return 'CircularProgressComponent(radius: ${_d(c.radius)})';
    }
    if (c is UIComponent) {
      return 'UIComponent(size: Size(${_d(c.size.width)}, ${_d(c.size.height)}))';
    }

    // Fallback — keep it compilable with a comment
    return '// TODO: ${c.runtimeType}()  — configure manually';
  }

  // ── Component JSON serialisation ─────────────────────────────────────────

  /// Deserialises one component from the JSON produced by [componentToJson].
  /// Returns `null` for unknown types so callers can use `whereType`.
  static Component? componentFromJson(Map<String, dynamic> j) {
    final type = j['type'] as String? ?? '';
    switch (type) {
      case 'TransformComponent':
        final p = j['position'] as Map<String, dynamic>;
        final s = j['scale'];
        final scale = s is Map<String, dynamic>
            ? Vector3(
                _n(s['dx']),
                _n(s['dy']),
                s.containsKey('dz') ? _n(s['dz']) : 1.0,
              )
            : Vector3(
                _n(s),
                _n(s),
                1.0,
              ); // backward compat: old single-value format
        return TransformComponent(
          position: Vector3.fromXY(_n(p['dx']), _n(p['dy'])),
          rotation: _n(j['rotation']),
          scale: scale,
        );
      case 'RectangleComponent':
        final legacyRectColor = j['color'];
        return RectangleComponent(
          width: _n(j['width']),
          height: _n(j['height']),
          fillStyle: _shapeStyleFromJson(
            j['fillStyle'],
            fallbackColor: legacyRectColor is int
                ? Color(legacyRectColor)
                : Colors.white,
          ),
          strokeStyle: _shapeStyleFromJson(
            j['strokeStyle'],
            fallbackColor: const Color(0x73FFFFFF),
          ),
          filled: j['filled'] as bool? ?? true,
          strokeWidth: _n(j['strokeWidth'] ?? 1.0),
          cornerRadius: _n(j['cornerRadius'] ?? 0.0),
        );
      case 'CircleComponent':
        final legacyCircleColor = j['color'];
        return CircleComponent(
          radius: _n(j['radius']),
          fillStyle: _shapeStyleFromJson(
            j['fillStyle'],
            fallbackColor: legacyCircleColor is int
                ? Color(legacyCircleColor)
                : Colors.white,
          ),
          strokeStyle: _shapeStyleFromJson(
            j['strokeStyle'],
            fallbackColor: const Color(0x73FFFFFF),
          ),
          filled: j['filled'] as bool? ?? true,
          strokeWidth: _n(j['strokeWidth'] ?? 1.0),
        );
      case 'CapsuleComponent':
        final legacyCapsuleColor = j['color'];
        return CapsuleComponent(
          width: _n(j['width']),
          height: _n(j['height']),
          fillStyle: _shapeStyleFromJson(
            j['fillStyle'],
            fallbackColor: legacyCapsuleColor is int
                ? Color(legacyCapsuleColor)
                : Colors.white,
          ),
          strokeStyle: _shapeStyleFromJson(
            j['strokeStyle'],
            fallbackColor: const Color(0x73FFFFFF),
          ),
          filled: j['filled'] as bool? ?? true,
          strokeWidth: _n(j['strokeWidth'] ?? 1.0),
        );
      case 'TagComponent':
        return TagComponent(j['tag'] as String);
      case 'VelocityComponent':
        final v = j['velocity'] as Map<String, dynamic>? ?? {};
        return VelocityComponent(
          velocity: Vector3(_n(v['dx'] ?? 0), _n(v['dy'] ?? 0), 0.0),
          maxSpeed: _n(j['maxSpeed'] ?? 500),
        );
      case 'HealthComponent':
        final c = HealthComponent(
          maxHealth: _n(j['maxHealth'] ?? 100),
          health: _n(j['health'] ?? j['maxHealth'] ?? 100),
        );
        c.isInvulnerable = j['isInvulnerable'] as bool? ?? false;
        return c;
      case 'LifetimeComponent':
        return LifetimeComponent(_n(j['initialLifetime'] ?? 3.0));
      case 'SpriteComponent':
        final s = SpriteComponent(spritePath: j['spritePath'] as String? ?? '');
        s.frame = j['frame'] as int? ?? 0;
        s.flipX = j['flipX'] as bool? ?? false;
        s.flipY = j['flipY'] as bool? ?? false;
        return s;
      case 'PhysicsBodyComponent':
        return PhysicsBodyComponent(
          shape: _shapeFromJson(j['shape']) ?? RectangleShape(64, 64),
          mass: _n(j['mass'] ?? 1.0),
          restitution: _n(j['restitution'] ?? 0.8),
          drag: _n(j['drag'] ?? 0.98),
          isStatic: j['isStatic'] as bool? ?? false,
          layer: j['layer'] as int? ?? 1,
          collisionMask: j['collisionMask'] as int? ?? -1,
          isOneWay: j['isOneWay'] as bool? ?? false,
          isSensor: j['isSensor'] as bool? ?? false,
          categoryBits: j['categoryBits'] as int? ?? 0x0001,
          maskBits: j['maskBits'] as int? ?? 0xFFFF,
          groupIndex: j['groupIndex'] as int? ?? 0,
        );
      case 'CameraFollowComponent':
        return CameraFollowComponent(
          enabled: j['enabled'] as bool? ?? true,
          lookaheadDistance: _n(j['lookaheadDistance'] ?? 80.0),
        );
      case 'CameraComponent':
        return CameraComponent(
          zoom: _n(j['zoom'] ?? 1.0),
          bounds: Rect.fromLTWH(
            _n(j['boundsLeft'] ?? 0.0),
            _n(j['boundsTop'] ?? 0.0),
            _n(j['boundsWidth'] ?? 4000.0),
            _n(j['boundsHeight'] ?? 800.0),
          ),
        );
      case 'InputComponent':
        return InputComponent();
      case 'SimpleMovementComponent':
        return SimpleMovementComponent(
          speed: _n(j['speed'] ?? 220.0),
          useKeyboard: j['useKeyboard'] as bool? ?? true,
          useJoystick: j['useJoystick'] as bool? ?? true,
          normalizeDiagonal: j['normalizeDiagonal'] as bool? ?? true,
          deadZone: _n(j['deadZone'] ?? 0.05),
        );
      case 'ChildrenComponent':
        return ChildrenComponent();
      // childIds re-linked by openScene hierarchy pass; don't restore raw IDs here
      case 'ParentComponent':
        final p2 = ParentComponent();
        // parentId is set by openScene hierarchy pass via parentName
        final lo = j['localOffset'] as Map<String, dynamic>?;
        if (lo != null) {
          p2.localOffset = Vector3(_n(lo['dx']), _n(lo['dy']), 0.0);
        }
        p2.localRotation = _n(j['localRotation'] ?? 0.0);
        return p2;
      case 'EffectComponent':
        return EffectComponent();
      case 'DistanceJointComponent':
        return DistanceJointComponent(
          targetEntityName: j['targetEntityName'] as String? ?? '',
          localAnchorA: _offsetFromJson(j['localAnchorA']),
          localAnchorB: _offsetFromJson(j['localAnchorB']),
          length: _n(j['length'] ?? 48.0),
          stiffness: _n(j['stiffness'] ?? 80.0),
          damping: _n(j['damping'] ?? 0.25),
          collideConnected: j['collideConnected'] as bool? ?? false,
        );
      case 'WeldJointComponent':
        return WeldJointComponent(
          targetEntityName: j['targetEntityName'] as String? ?? '',
          localAnchorA: _offsetFromJson(j['localAnchorA']),
          localAnchorB: _offsetFromJson(j['localAnchorB']),
          collideConnected: j['collideConnected'] as bool? ?? false,
        );
      case 'PrismaticJointComponent':
        return PrismaticJointComponent(
          targetEntityName: j['targetEntityName'] as String? ?? '',
          axis: _offsetFromJson(j['axis'], fallback: const Offset(1, 0)),
          enableLimit: j['enableLimit'] as bool? ?? false,
          lowerTranslation: _n(j['lowerTranslation'] ?? -20.0),
          upperTranslation: _n(j['upperTranslation'] ?? 20.0),
          enableMotor: j['enableMotor'] as bool? ?? false,
          motorSpeed: _n(j['motorSpeed'] ?? 0.0),
          maxMotorForce: _n(j['maxMotorForce'] ?? 200.0),
          collideConnected: j['collideConnected'] as bool? ?? false,
        );
      case 'WheelJointComponent':
        return WheelJointComponent(
          targetEntityName: j['targetEntityName'] as String? ?? '',
          suspensionAxis: _offsetFromJson(
            j['suspensionAxis'],
            fallback: const Offset(0, 1),
          ),
          stiffness: _n(j['stiffness'] ?? 45.0),
          damping: _n(j['damping'] ?? 0.65),
          enableMotor: j['enableMotor'] as bool? ?? true,
          motorSpeed: _n(j['motorSpeed'] ?? 12.0),
          maxMotorTorque: _n(j['maxMotorTorque'] ?? 250.0),
          collideConnected: j['collideConnected'] as bool? ?? false,
        );
      default:
        return CustomComponentRegistry.instance.componentFromJson(j);
    }
  }

  static double _n(dynamic v) => (v as num).toDouble();

  static Map<String, dynamic>? componentToJson(Component c) {
    if (c is TransformComponent) {
      return {
        'type': 'TransformComponent',
        'position': {'dx': c.position.x, 'dy': c.position.y},
        'rotation': c.rotation,
        'scale': {'dx': c.scale.x, 'dy': c.scale.y},
      };
    }
    if (c is RectangleComponent) {
      return {
        'type': 'RectangleComponent',
        'width': c.width,
        'height': c.height,
        'fillStyle': _shapeStyleToJson(c.fillStyle),
        'strokeStyle': _shapeStyleToJson(c.strokeStyle),
        'filled': c.filled,
        'strokeWidth': c.strokeWidth,
        'cornerRadius': c.cornerRadius,
      };
    }
    if (c is CircleComponent) {
      return {
        'type': 'CircleComponent',
        'radius': c.radius,
        'fillStyle': _shapeStyleToJson(c.fillStyle),
        'strokeStyle': _shapeStyleToJson(c.strokeStyle),
        'filled': c.filled,
        'strokeWidth': c.strokeWidth,
      };
    }
    if (c is CapsuleComponent) {
      return {
        'type': 'CapsuleComponent',
        'width': c.width,
        'height': c.height,
        'fillStyle': _shapeStyleToJson(c.fillStyle),
        'strokeStyle': _shapeStyleToJson(c.strokeStyle),
        'filled': c.filled,
        'strokeWidth': c.strokeWidth,
      };
    }
    if (c is TagComponent) return {'type': 'TagComponent', 'tag': c.tag};
    if (c is VelocityComponent) {
      return {
        'type': 'VelocityComponent',
        'velocity': {'dx': c.velocity.x, 'dy': c.velocity.y},
        'maxSpeed': c.maxSpeed,
      };
    }
    if (c is HealthComponent) {
      return {
        'type': 'HealthComponent',
        'health': c.health,
        'maxHealth': c.maxHealth,
        'isInvulnerable': c.isInvulnerable,
      };
    }
    if (c is LifetimeComponent) {
      return {
        'type': 'LifetimeComponent',
        'initialLifetime': c.initialLifetime,
      };
    }
    if (c is SpriteComponent) {
      return {
        'type': 'SpriteComponent',
        'spritePath': c.spritePath,
        'frame': c.frame,
        'flipX': c.flipX,
        'flipY': c.flipY,
      };
    }
    if (c is PhysicsBodyComponent) {
      return {
        'type': 'PhysicsBodyComponent',
        'shape': _shapeToJson(c.shape),
        'mass': c.mass,
        'restitution': c.restitution,
        'drag': c.drag,
        'isStatic': c.isStatic,
        'layer': c.layer,
        'collisionMask': c.collisionMask,
        'isOneWay': c.isOneWay,
        'isSensor': c.isSensor,
        'categoryBits': c.categoryBits,
        'maskBits': c.maskBits,
        'groupIndex': c.groupIndex,
      };
    }
    if (c is CameraFollowComponent) {
      return {
        'type': 'CameraFollowComponent',
        'enabled': c.enabled,
        'lookaheadDistance': c.lookaheadDistance,
      };
    }
    if (c is CameraComponent) {
      return {
        'type': 'CameraComponent',
        'zoom': c.zoom,
        'boundsLeft': c.bounds.left,
        'boundsTop': c.bounds.top,
        'boundsWidth': c.bounds.width,
        'boundsHeight': c.bounds.height,
      };
    }
    if (c is InputComponent) return {'type': 'InputComponent'};
    if (c is SimpleMovementComponent) {
      return {
        'type': 'SimpleMovementComponent',
        'speed': c.speed,
        'useKeyboard': c.useKeyboard,
        'useJoystick': c.useJoystick,
        'normalizeDiagonal': c.normalizeDiagonal,
        'deadZone': c.deadZone,
      };
    }
    if (c is ChildrenComponent) {
      return {'type': 'ChildrenComponent', 'childIds': c.childIds};
    }
    if (c is ParentComponent) {
      return {
        'type': 'ParentComponent',
        'parentId': c.parentId,
        'localOffset': {'dx': c.localOffset.x, 'dy': c.localOffset.y},
        'localRotation': c.localRotation,
      };
    }
    if (c is EffectComponent) return {'type': 'EffectComponent'};
    if (c is DistanceJointComponent) {
      return {
        'type': 'DistanceJointComponent',
        'targetEntityName': c.targetEntityName,
        'localAnchorA': _offsetToJson(c.localAnchorA),
        'localAnchorB': _offsetToJson(c.localAnchorB),
        'length': c.length,
        'stiffness': c.stiffness,
        'damping': c.damping,
        'collideConnected': c.collideConnected,
      };
    }
    if (c is WeldJointComponent) {
      return {
        'type': 'WeldJointComponent',
        'targetEntityName': c.targetEntityName,
        'localAnchorA': _offsetToJson(c.localAnchorA),
        'localAnchorB': _offsetToJson(c.localAnchorB),
        'collideConnected': c.collideConnected,
      };
    }
    if (c is PrismaticJointComponent) {
      return {
        'type': 'PrismaticJointComponent',
        'targetEntityName': c.targetEntityName,
        'axis': _offsetToJson(c.axis),
        'enableLimit': c.enableLimit,
        'lowerTranslation': c.lowerTranslation,
        'upperTranslation': c.upperTranslation,
        'enableMotor': c.enableMotor,
        'motorSpeed': c.motorSpeed,
        'maxMotorForce': c.maxMotorForce,
        'collideConnected': c.collideConnected,
      };
    }
    if (c is WheelJointComponent) {
      return {
        'type': 'WheelJointComponent',
        'targetEntityName': c.targetEntityName,
        'suspensionAxis': _offsetToJson(c.suspensionAxis),
        'stiffness': c.stiffness,
        'damping': c.damping,
        'enableMotor': c.enableMotor,
        'motorSpeed': c.motorSpeed,
        'maxMotorTorque': c.maxMotorTorque,
        'collideConnected': c.collideConnected,
      };
    }
    return CustomComponentRegistry.instance.componentToJson(c);
  }

  static CollisionShape? _shapeFromJson(dynamic raw) {
    if (raw is! Map<String, dynamic>) return null;
    switch (raw['kind'] as String? ?? '') {
      case 'circle':
        return CircleShape(_n(raw['radius'] ?? 16.0));
      case 'rectangle':
        return RectangleShape(
          _n(raw['width'] ?? 64.0),
          _n(raw['height'] ?? 64.0),
        );
      case 'polygon':
        final vertices = _offsetListFromJson(raw['vertices']);
        if (vertices.isEmpty) return null;
        return PolygonShape(vertices);
      case 'capsule':
        return CapsuleShape(
          center1: _offsetFromJson(raw['center1']),
          center2: _offsetFromJson(raw['center2']),
          radius: _n(raw['radius'] ?? 8.0),
        );
      case 'segment':
        return SegmentShape(
          _offsetFromJson(raw['point1']),
          _offsetFromJson(raw['point2']),
          thickness: _n(raw['thickness'] ?? 2.0),
        );
      case 'chain':
        final vertices = _offsetListFromJson(raw['vertices']);
        if (vertices.isEmpty) return null;
        return ChainShape(
          vertices,
          loop: raw['loop'] as bool? ?? false,
          thickness: _n(raw['thickness'] ?? 2.0),
        );
      case 'rounded_polygon':
        final vertices = _offsetListFromJson(raw['vertices']);
        if (vertices.isEmpty) return null;
        return RoundedPolygonShape(vertices, _n(raw['cornerRadius'] ?? 6.0));
      default:
        return null;
    }
  }

  static Map<String, dynamic> _shapeToJson(CollisionShape shape) {
    if (shape is CircleShape) {
      return {'kind': 'circle', 'radius': shape.radius};
    }
    if (shape is RectangleShape) {
      return {
        'kind': 'rectangle',
        'width': shape.width,
        'height': shape.height,
      };
    }
    if (shape is RoundedPolygonShape) {
      return {
        'kind': 'rounded_polygon',
        'vertices': _offsetListToJson(shape.vertices),
        'cornerRadius': shape.cornerRadius,
      };
    }
    if (shape is PolygonShape) {
      return {'kind': 'polygon', 'vertices': _offsetListToJson(shape.vertices)};
    }
    if (shape is CapsuleShape) {
      return {
        'kind': 'capsule',
        'center1': _offsetToJson(shape.center1),
        'center2': _offsetToJson(shape.center2),
        'radius': shape.radius,
      };
    }
    if (shape is SegmentShape) {
      return {
        'kind': 'segment',
        'point1': _offsetToJson(shape.point1),
        'point2': _offsetToJson(shape.point2),
        'thickness': shape.thickness,
      };
    }
    if (shape is ChainShape) {
      return {
        'kind': 'chain',
        'vertices': _offsetListToJson(shape.vertices),
        'loop': shape.loop,
        'thickness': shape.thickness,
      };
    }
    return {'kind': 'rectangle', 'width': 64.0, 'height': 64.0};
  }

  static String _physicsShapeCode(CollisionShape shape) {
    if (shape is CircleShape) {
      return 'CircleShape(${_d(shape.radius)})';
    }
    if (shape is RectangleShape) {
      return 'RectangleShape(${_d(shape.width)}, ${_d(shape.height)})';
    }
    if (shape is RoundedPolygonShape) {
      return 'RoundedPolygonShape([${shape.vertices.map((v) => 'Offset(${_d(v.dx)}, ${_d(v.dy)})').join(', ')}], ${_d(shape.cornerRadius)})';
    }
    if (shape is PolygonShape) {
      return 'PolygonShape([${shape.vertices.map((v) => 'Offset(${_d(v.dx)}, ${_d(v.dy)})').join(', ')}])';
    }
    if (shape is CapsuleShape) {
      return 'CapsuleShape(center1: Offset(${_d(shape.center1.dx)}, ${_d(shape.center1.dy)}), center2: Offset(${_d(shape.center2.dx)}, ${_d(shape.center2.dy)}), radius: ${_d(shape.radius)})';
    }
    if (shape is SegmentShape) {
      return 'SegmentShape(Offset(${_d(shape.point1.dx)}, ${_d(shape.point1.dy)}), Offset(${_d(shape.point2.dx)}, ${_d(shape.point2.dy)}), thickness: ${_d(shape.thickness)})';
    }
    if (shape is ChainShape) {
      return 'ChainShape([${shape.vertices.map((v) => 'Offset(${_d(v.dx)}, ${_d(v.dy)})').join(', ')}], loop: ${shape.loop}, thickness: ${_d(shape.thickness)})';
    }
    return 'RectangleShape(64, 64)';
  }

  static Offset _offsetFromJson(dynamic raw, {Offset fallback = Offset.zero}) {
    if (raw is Map<String, dynamic>) {
      return Offset(_n(raw['dx'] ?? 0), _n(raw['dy'] ?? 0));
    }
    return fallback;
  }

  static Map<String, dynamic> _offsetToJson(Offset value) {
    return {'dx': value.dx, 'dy': value.dy};
  }

  static List<Offset> _offsetListFromJson(dynamic raw) {
    if (raw is! List) return const [];
    return raw
        .whereType<Map<String, dynamic>>()
        .map((v) => Offset(_n(v['dx'] ?? 0), _n(v['dy'] ?? 0)))
        .toList();
  }

  static List<Map<String, dynamic>> _offsetListToJson(List<Offset> values) {
    return values.map(_offsetToJson).toList();
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  /// Formats a double, dropping the trailing `.0` when it's a whole number.
  static String _d(double v) {
    if (v == v.truncateToDouble() && !v.isInfinite && !v.isNaN) {
      return '${v.truncate()}';
    }
    // Round to 4 significant decimal places to avoid floating-point noise.
    final s = v.toStringAsFixed(4).replaceAll(RegExp(r'0+$'), '');
    return s.endsWith('.') ? '${s}0' : s;
  }

  /// Converts a [Color] to its `Color(0xAARRGGBB)` Dart literal.
  static String _color(Color c) =>
      'Color(0x${c.toARGB32().toRadixString(16).padLeft(8, '0').toUpperCase()})';

  static String _shapeStyleArg(
    String name,
    ShapePaintStyle style, {
    required Color defaultColor,
  }) {
    final isDefault =
        style.color == defaultColor &&
        style.gradient == null &&
        style.blendMode == BlendMode.modulate;
    if (isDefault) return '';
    return ', $name: ${_shapeStyleCode(style)}';
  }

  static String _shapeStyleCode(ShapePaintStyle style) {
    final g = style.gradient;
    final gradient = g == null ? '' : ', gradient: ${_shapeGradientCode(g)}';
    final blend = style.blendMode == BlendMode.modulate
        ? ''
        : ', blendMode: BlendMode.${style.blendMode.name}';
    return 'ShapePaintStyle(color: ${_color(style.color)}$gradient$blend)';
  }

  static String _shapeGradientCode(ShapeGradient g) {
    final colors = g.colors.map(_color).join(', ');
    final stops = g.stops == null
        ? ''
        : ', stops: [${g.stops!.map(_d).join(', ')}]';
    switch (g.kind) {
      case ShapeGradientKind.linear:
        return 'ShapeGradient.linear('
            'colors: [$colors]'
            '$stops'
            ', begin: ${_alignmentCode(g.begin)}'
            ', end: ${_alignmentCode(g.end)}'
            ', tileMode: TileMode.${g.tileMode.name}'
            ')';
      case ShapeGradientKind.radial:
        return 'ShapeGradient.radial('
            'colors: [$colors]'
            '$stops'
            ', center: ${_alignmentCode(g.center)}'
            ', radius: ${_d(g.radius)}'
            ', tileMode: TileMode.${g.tileMode.name}'
            ')';
      case ShapeGradientKind.sweep:
        return 'ShapeGradient.sweep('
            'colors: [$colors]'
            '$stops'
            ', center: ${_alignmentCode(g.center)}'
            ', startAngle: ${_d(g.startAngle)}'
            ', endAngle: ${_d(g.endAngle)}'
            ', tileMode: TileMode.${g.tileMode.name}'
            ')';
    }
  }

  static String _alignmentCode(AlignmentGeometry a) {
    if (a is Alignment) {
      return 'Alignment(${_d(a.x)}, ${_d(a.y)})';
    }
    return 'Alignment.center';
  }

  static Map<String, dynamic> _shapeStyleToJson(ShapePaintStyle style) => {
    'color': style.color.toARGB32(),
    'blendMode': style.blendMode.name,
    if (style.gradient != null)
      'gradient': _shapeGradientToJson(style.gradient!),
  };

  static ShapePaintStyle _shapeStyleFromJson(
    dynamic raw, {
    required Color fallbackColor,
  }) {
    if (raw is! Map<String, dynamic>) {
      return ShapePaintStyle(color: fallbackColor);
    }
    final blendName = raw['blendMode'] as String?;
    final blend = BlendMode.values.firstWhere(
      (m) => m.name == blendName,
      orElse: () => BlendMode.modulate,
    );
    final colorRaw = raw['color'];
    final color = colorRaw is int ? Color(colorRaw) : fallbackColor;
    return ShapePaintStyle(
      color: color,
      gradient: _shapeGradientFromJson(raw['gradient']),
      blendMode: blend,
    );
  }

  static Map<String, dynamic> _shapeGradientToJson(ShapeGradient gradient) => {
    'kind': gradient.kind.name,
    'colors': gradient.colors.map((c) => c.toARGB32()).toList(),
    if (gradient.stops != null) 'stops': gradient.stops,
    'begin': _alignmentToJson(gradient.begin),
    'end': _alignmentToJson(gradient.end),
    'center': _alignmentToJson(gradient.center),
    'radius': gradient.radius,
    'startAngle': gradient.startAngle,
    'endAngle': gradient.endAngle,
    'tileMode': gradient.tileMode.name,
  };

  static ShapeGradient? _shapeGradientFromJson(dynamic raw) {
    if (raw is! Map<String, dynamic>) return null;
    final kindName = raw['kind'] as String? ?? ShapeGradientKind.linear.name;
    final kind = ShapeGradientKind.values.firstWhere(
      (k) => k.name == kindName,
      orElse: () => ShapeGradientKind.linear,
    );
    final colorRaw = raw['colors'];
    final colors = colorRaw is List
        ? colorRaw.whereType<int>().map(Color.new).toList()
        : <Color>[];
    if (colors.isEmpty) return null;

    final stopsRaw = raw['stops'];
    final stops = stopsRaw is List
        ? stopsRaw.whereType<num>().map((v) => v.toDouble()).toList()
        : null;
    final tileName = raw['tileMode'] as String?;
    final tileMode = TileMode.values.firstWhere(
      (m) => m.name == tileName,
      orElse: () => TileMode.clamp,
    );

    switch (kind) {
      case ShapeGradientKind.linear:
        return ShapeGradient.linear(
          colors: colors,
          stops: stops,
          begin: _alignmentFromJson(
            raw['begin'],
            fallback: Alignment.centerLeft,
          ),
          end: _alignmentFromJson(raw['end'], fallback: Alignment.centerRight),
          tileMode: tileMode,
        );
      case ShapeGradientKind.radial:
        return ShapeGradient.radial(
          colors: colors,
          stops: stops,
          center: _alignmentFromJson(raw['center'], fallback: Alignment.center),
          radius: _n(raw['radius'] ?? 0.5),
          tileMode: tileMode,
        );
      case ShapeGradientKind.sweep:
        return ShapeGradient.sweep(
          colors: colors,
          stops: stops,
          center: _alignmentFromJson(raw['center'], fallback: Alignment.center),
          startAngle: _n(raw['startAngle'] ?? 0.0),
          endAngle: _n(raw['endAngle'] ?? 6.283185307179586),
          tileMode: tileMode,
        );
    }
  }

  static Map<String, double> _alignmentToJson(AlignmentGeometry alignment) {
    if (alignment is Alignment) {
      return {'x': alignment.x, 'y': alignment.y};
    }
    return {'x': 0.0, 'y': 0.0};
  }

  static Alignment _alignmentFromJson(
    dynamic raw, {
    required Alignment fallback,
  }) {
    if (raw is! Map<String, dynamic>) return fallback;
    final x = raw['x'];
    final y = raw['y'];
    if (x is! num || y is! num) return fallback;
    return Alignment(x.toDouble(), y.toDouble());
  }

  /// Converts `my_level_name` → `MyLevelName`.
  static String _toPascalCase(String name) => name
      .split(RegExp(r'[_\s]'))
      .map((w) => w.isEmpty ? '' : w[0].toUpperCase() + w.substring(1))
      .join();
}

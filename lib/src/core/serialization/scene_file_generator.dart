import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart' show Colors;
import 'package:flutter/painting.dart';
import 'package:just_game_engine/just_game_engine.dart';

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
    await Future.wait([
      if (!levelFile.existsSync())
        levelFile.writeAsString(_buildBlankLevel(sceneName)),
      if (!dataFile.existsSync())
        dataFile.writeAsString(_buildDataTemplate(sceneName)),
    ]);
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
    // No entities yet — create them in the editor.
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
      final col = c.color != Colors.white ? ', color: ${_color(c.color)}' : '';
      final fil = !c.filled ? ', filled: false' : '';
      final sw = c.strokeWidth != 1.0
          ? ', strokeWidth: ${_d(c.strokeWidth)}'
          : '';
      final cr = c.cornerRadius != 0.0
          ? ', cornerRadius: ${_d(c.cornerRadius)}'
          : '';
      return 'RectangleComponent(width: ${_d(c.width)}, height: ${_d(c.height)}$col$fil$sw$cr)';
    }
    if (c is CircleComponent) {
      final col = c.color != Colors.white ? ', color: ${_color(c.color)}' : '';
      final fil = !c.filled ? ', filled: false' : '';
      final sw = c.strokeWidth != 1.0
          ? ', strokeWidth: ${_d(c.strokeWidth)}'
          : '';
      return 'CircleComponent(radius: ${_d(c.radius)}$col$fil$sw)';
    }
    if (c is CapsuleComponent) {
      final col = c.color != Colors.white ? ', color: ${_color(c.color)}' : '';
      final fil = !c.filled ? ', filled: false' : '';
      return 'CapsuleComponent(width: ${_d(c.width)}, height: ${_d(c.height)}$col$fil)';
    }
    if (c is LineComponent) {
      final col = c.color != Colors.white ? ', color: ${_color(c.color)}' : '';
      final st = 'start: Offset(${_d(c.start.dx)}, ${_d(c.start.dy)})';
      final en = 'end: Offset(${_d(c.end.dx)}, ${_d(c.end.dy)})';
      return 'LineComponent($st, $en$col, strokeWidth: ${_d(c.strokeWidth)})';
    }
    if (c is PolygonComponent) {
      final verts = c.vertices
          .map((v) => 'Offset(${_d(v.dx)}, ${_d(v.dy)})')
          .join(', ');
      final col = c.color != Colors.white ? ', color: ${_color(c.color)}' : '';
      return 'PolygonComponent(vertices: [$verts]$col)';
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

    // Input / Camera
    if (c is InputComponent) return 'InputComponent()';
    if (c is CameraFollowComponent) {
      final en = c.enabled ? '' : 'enabled: false, ';
      final la = c.lookaheadDistance != 80.0
          ? 'lookaheadDistance: ${_d(c.lookaheadDistance)}, '
          : '';
      return 'CameraFollowComponent($en$la)'.replaceAll(RegExp(r', \)$'), ')');
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
        return RectangleComponent(
          width: _n(j['width']),
          height: _n(j['height']),
          color: Color(j['color'] as int),
          filled: j['filled'] as bool? ?? true,
          strokeWidth: _n(j['strokeWidth'] ?? 1.0),
          cornerRadius: _n(j['cornerRadius'] ?? 0.0),
        );
      case 'CircleComponent':
        return CircleComponent(
          radius: _n(j['radius']),
          color: Color(j['color'] as int),
          filled: j['filled'] as bool? ?? true,
          strokeWidth: _n(j['strokeWidth'] ?? 1.0),
        );
      case 'CapsuleComponent':
        return CapsuleComponent(
          width: _n(j['width']),
          height: _n(j['height']),
          color: Color(j['color'] as int),
          filled: j['filled'] as bool? ?? true,
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
      case 'CameraFollowComponent':
        return CameraFollowComponent(
          enabled: j['enabled'] as bool? ?? true,
          lookaheadDistance: _n(j['lookaheadDistance'] ?? 80.0),
        );
      case 'InputComponent':
        return InputComponent();
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
      default:
        return null;
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
        'color': c.color.toARGB32(),
        'filled': c.filled,
        'strokeWidth': c.strokeWidth,
        'cornerRadius': c.cornerRadius,
      };
    }
    if (c is CircleComponent) {
      return {
        'type': 'CircleComponent',
        'radius': c.radius,
        'color': c.color.toARGB32(),
        'filled': c.filled,
        'strokeWidth': c.strokeWidth,
      };
    }
    if (c is CapsuleComponent) {
      return {
        'type': 'CapsuleComponent',
        'width': c.width,
        'height': c.height,
        'color': c.color.toARGB32(),
        'filled': c.filled,
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
    if (c is CameraFollowComponent) {
      return {
        'type': 'CameraFollowComponent',
        'enabled': c.enabled,
        'lookaheadDistance': c.lookaheadDistance,
      };
    }
    if (c is InputComponent) return {'type': 'InputComponent'};
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
    return null;
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

  /// Converts `my_level_name` → `MyLevelName`.
  static String _toPascalCase(String name) => name
      .split(RegExp(r'[_\s]'))
      .map((w) => w.isEmpty ? '' : w[0].toUpperCase() + w.substring(1))
      .join();
}

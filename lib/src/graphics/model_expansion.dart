import 'dart:math' as math;
import 'dart:ui' show Color;

import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_editor_core/just_editor_core.dart';
import 'package:just_game_engine/graphics_3d.dart';

/// One entity a model expands into.
final class ModelPart {
  /// A part called [name] made of [components]; the model's root when
  /// [isRoot].
  const ModelPart(this.name, this.components, {this.isRoot = false});

  /// Its entity's name.
  final String name;

  /// What its entity is made of.
  final List<Component> components;

  /// Whether it is the model itself; every other part is its child.
  final bool isRoot;
}

/// A model made into entities once, with no link kept to the file after:
/// the model itself (playing its first animation, when it has any), and a
/// child for each light in the file and each node named as a socket
/// (`socket…`, `attach…`, `mount…`) — the parts a level then edits on their
/// own.
abstract final class ModelExpansion {
  static final RegExp _socket = RegExp(
    r'^(socket|attach|mount)',
    caseSensitive: false,
  );

  /// The parts of [data] (the file at [path]) placed at [at]: the root
  /// first. Children are placed in the world; their link to the root is
  /// made when they are placed ([place]).
  static List<ModelPart> partsOf(ModelData data, String path, Vector3 at) {
    final slash = path.lastIndexOf('/');
    final dot = path.lastIndexOf('.');
    final stem = path.substring(slash + 1, dot > slash ? dot : path.length);
    final parts = <ModelPart>[
      ModelPart(stem, [
        TransformComponent(position: Vector3.copy(at)),
        ModelComponent(model: path),
        if (data.animations.isNotEmpty)
          AnimationPlayerComponent(clip: data.animations.first.name),
      ], isRoot: true),
    ];
    final names = <String>{stem};
    String unique(String name) {
      var out = name;
      for (var i = 2; !names.add(out); i++) {
        out = '${name}_$i';
      }
      return out;
    }

    data.forEachNode((index, modelFromNode) {
      final node = data.nodes[index];
      final engineFromNode = gltfToEngine
          .multiplied(modelFromNode)
          .multiplied(gltfToEngine);
      final position = Vector3(
        engineFromNode.storage[12] + at.x,
        engineFromNode.storage[13] + at.y,
        engineFromNode.storage[14] + at.z,
      );
      final rotation = _rotationOf(engineFromNode);
      if (node.light case final l? when l < data.lights.length) {
        final light = data.lights[l];
        final transform = TransformComponent(position: position)
          ..setRotation(rotation);
        parts.add(
          ModelPart(unique(light.name ?? node.name ?? 'light'), [
            transform,
            LightComponent(
              kind: switch (light.type) {
                LightType.directional => LightKind.directional,
                LightType.point => LightKind.point,
                LightType.spot => LightKind.spot,
              },
              color: _srgb(light.color),
              intensity: light.intensity,
              range: light.range ?? 0,
              innerConeAngle: light.innerConeAngle,
              outerConeAngle: light.outerConeAngle,
            ),
          ]),
        );
      }
      final name = node.name;
      if (name != null && node.mesh == null && _socket.hasMatch(name)) {
        final transform = TransformComponent(position: position)
          ..setRotation(rotation);
        parts.add(
          ModelPart(unique(name), [transform, SocketComponent(node: name)]),
        );
      }
    });
    return parts;
  }

  /// Makes [parts] into entities in [scope]'s world, the rest children of
  /// the root, selects the root, and records it all as one undo step.
  static Entity place(EditorScope scope, List<ModelPart> parts) {
    final world = scope.world;
    final root = parts.firstWhere((p) => p.isRoot);
    final made = <Entity>[
      world.createEntityWithComponents(root.components, name: root.name),
    ];
    for (final part in parts) {
      if (identical(part, root)) continue;
      made.add(
        world.createEntityWithComponents([
          ...part.components,
          // No local values: each keeps the place it was given, and its local
          // one is worked out from it.
          ParentComponent(parentId: made.first.id),
        ], name: part.name),
      );
    }
    final state = scope.sceneState;
    state
      ..markDirty()
      ..refresh()
      ..selectEntity(made.first);
    scope.history.pushApplied(
      CreateEntitiesCommand.adopting(
        label: 'Place ${root.name}',
        world: world,
        sceneState: state,
        entities: made,
        codec: scope.codec,
      ),
    );
    return made.first;
  }

  // The rotation of [m]'s upper 3×3, its scale taken out.
  static Quaternion _rotationOf(Matrix4 m) {
    final s = m.storage;
    double len(int i) =>
        math.sqrt(s[i] * s[i] + s[i + 1] * s[i + 1] + s[i + 2] * s[i + 2]);
    final sx = len(0), sy = len(4), sz = len(8);
    if (sx < 1e-9 || sy < 1e-9 || sz < 1e-9) return Quaternion.identity();
    // Column-major: m<row><column>.
    final m00 = s[0] / sx, m10 = s[1] / sx, m20 = s[2] / sx;
    final m01 = s[4] / sy, m11 = s[5] / sy, m21 = s[6] / sy;
    final m02 = s[8] / sz, m12 = s[9] / sz, m22 = s[10] / sz;
    final trace = m00 + m11 + m22;
    final Quaternion q;
    if (trace > 0) {
      final k = math.sqrt(trace + 1) * 2;
      q = Quaternion(
        (m21 - m12) / k,
        (m02 - m20) / k,
        (m10 - m01) / k,
        0.25 * k,
      );
    } else if (m00 > m11 && m00 > m22) {
      final k = math.sqrt(1 + m00 - m11 - m22) * 2;
      q = Quaternion(
        0.25 * k,
        (m01 + m10) / k,
        (m02 + m20) / k,
        (m21 - m12) / k,
      );
    } else if (m11 > m22) {
      final k = math.sqrt(1 + m11 - m00 - m22) * 2;
      q = Quaternion(
        (m01 + m10) / k,
        0.25 * k,
        (m12 + m21) / k,
        (m02 - m20) / k,
      );
    } else {
      final k = math.sqrt(1 + m22 - m00 - m11) * 2;
      q = Quaternion(
        (m02 + m20) / k,
        (m12 + m21) / k,
        0.25 * k,
        (m10 - m01) / k,
      );
    }
    return q..normalize();
  }

  /// The rotation part of [m] (for tests).
  static Quaternion rotationOf(Matrix4 m) => _rotationOf(m);

  static Color _srgb((double, double, double) linear) {
    int c(double v) {
      final x = v.clamp(0.0, 1.0);
      final e = x <= 0.0031308
          ? x * 12.92
          : 1.055 * math.pow(x, 1 / 2.4) - 0.055;
      return (e * 255 + 0.5).floor().clamp(0, 255);
    }

    return Color.fromARGB(255, c(linear.$1), c(linear.$2), c(linear.$3));
  }
}

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_game_engine/graphics_3d.dart';

import 'package:just_editor_core/host.dart';

/// Pictures for the palette of any prefab made of a 3-D shape: the shape
/// seen from above at an angle, its faces lit from one side, in the
/// prefab's colour (a [PrefabPicture]).
abstract final class ShapePictures {
  static final Map<String, ModelGeometry?> _geometry = {};

  /// [prefab]'s picture, [size] pixels square; null for a prefab that
  /// is not a shape.
  static Widget? picture(PrefabDefinition prefab, double size) {
    final geometry = _geometry.putIfAbsent(prefab.id, () => _shapeOf(prefab));
    if (geometry == null) return null;
    return SizedBox.square(
      dimension: size,
      child: CustomPaint(
        painter: _ShapePainter(geometry, prefab.color),
      ),
    );
  }

  static ModelGeometry? _shapeOf(PrefabDefinition prefab) {
    if (!prefab.dimensions.allows(SceneMode.threeD)) return null;
    final buildAt = prefab.buildAt;
    if (buildAt == null) return null;
    final components = buildAt(SurfacePoint(Vector3.zero(), Placement3D.up));
    final shape = components.whereType<Primitive3D>().firstOrNull;
    if (shape == null) return null;
    final geometry = shape.buildMesh().geometry;
    return geometry.triangleCount == 0 ? null : geometry;
  }
}

class _ShapePainter extends CustomPainter {
  _ShapePainter(this.geometry, this.colour);

  final ModelGeometry geometry;
  final Color colour;

  // Turned a little and seen from a little above.
  static const double _yaw = 0.6, _pitch = 0.45;

  @override
  void paint(Canvas canvas, Size size) {
    final p = geometry.positions, idx = geometry.indices;
    final cy = math.cos(_yaw), sy = math.sin(_yaw);
    final cp = math.cos(_pitch), sp = math.sin(_pitch);
    final count = p.length ~/ 3;
    final view = List<Vector3>.generate(count, (i) {
      final x = p[i * 3], y = p[i * 3 + 1], z = p[i * 3 + 2];
      // About up, then tipped so the top (-Y) leans towards the viewer.
      final x1 = x * cy + z * sy, z1 = -x * sy + z * cy;
      return Vector3(x1, y * cp - z1 * sp, y * sp + z1 * cp);
    });
    var minX = double.infinity, maxX = -double.infinity;
    var minY = double.infinity, maxY = -double.infinity;
    for (final v in view) {
      minX = math.min(minX, v.x);
      maxX = math.max(maxX, v.x);
      minY = math.min(minY, v.y);
      maxY = math.max(maxY, v.y);
    }
    final extent = math.max(maxX - minX, maxY - minY);
    if (extent <= 0) return;
    final scale = size.shortestSide * 0.86 / extent;
    final centre = Offset((minX + maxX) / 2, (minY + maxY) / 2);
    Offset screen(Vector3 v) => size.center(Offset.zero) + (Offset(v.x, v.y) - centre) * scale;

    final toLight = Vector3(-0.45, -0.75, -0.5)..normalize();
    final faces = <(double, Path, double)>[];
    for (var i = 0; i + 2 < idx.length; i += 3) {
      final a = view[idx[i]], b = view[idx[i + 1]], c = view[idx[i + 2]];
      final n = (b - a).cross(c - a);
      if (n.lengthSquared < 1e-18) continue;
      n.normalize();
      // Either side: the one facing the viewer.
      if (n.z > 0) n.negate();
      final light = 0.4 + 0.6 * math.max(0, n.dot(toLight));
      final pa = screen(a), pb = screen(b), pc = screen(c);
      faces.add((
        (a.z + b.z + c.z) / 3,
        Path()
          ..moveTo(pa.dx, pa.dy)
          ..lineTo(pb.dx, pb.dy)
          ..lineTo(pc.dx, pc.dy)
          ..close(),
        light,
      ));
    }
    // Far first.
    faces.sort((x, y) => y.$1.compareTo(x.$1));
    final fill = Paint()..isAntiAlias = true;
    final seam = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.6;
    for (final (_, path, light) in faces) {
      final shaded = Color.lerp(Colors.black, colour, light.clamp(0.0, 1.0))!;
      fill.color = shaded;
      // Drawn over the gaps between neighbours, in their own colour.
      seam.color = shaded;
      canvas
        ..drawPath(path, fill)
        ..drawPath(path, seam);
    }
  }

  @override
  bool shouldRepaint(_ShapePainter old) =>
      old.geometry != geometry || old.colour != colour;
}

import 'package:flutter/material.dart';
import 'package:just_game_engine/just_game_engine.dart' as jge;

import 'package:just_editor_core/host.dart';
import '../tools/place_3d_tool.dart';

/// Place's preview: what a click would make, where it would go — a 3-D
/// shape's edges, anything else's box — in the prefab's colour, with the
/// spot on the surface and which way the surface faces.
class PlaceGhost3DOverlay extends DesignerOverlay {
  PlaceGhost3DOverlay(this.tool);

  /// The tool whose preview it draws.
  final Place3DTool tool;

  @override
  String get id => 'designer3d.placeGhost';

  @override
  String get label => 'Place preview';

  @override
  IconData get icon => Icons.add_location_alt_outlined;

  @override
  jge.Dimensions get dimensions => jge.Dimensions.threeD;

  @override
  int get order => OverlayOrder.selection;

  @override
  void paint(OverlayPaintContext context) {
    if (context.controller.toolId.value != BuiltInTools.place) return;
    final ghost = tool.ghost.value;
    if (ghost == null) return;
    final view = context.draw.camera;
    final canvas = context.draw.canvas;
    final colour = ghost.prefab.color;
    final line = Paint()
      ..color = colour.withValues(alpha: 0.9)
      ..strokeWidth = 1.2
      ..style = PaintingStyle.stroke;

    Offset? project(jge.Vector3 local) {
      final world = jge.Vector3.zero();
      ghost.world.transformPointInto(local, world);
      return view.projectToScreen(world);
    }

    final edges = ghost.edges ?? _boxEdges(ghost.box);
    final path = Path();
    for (var i = 0; i + 1 < edges.length; i += 2) {
      final a = project(edges[i]), b = project(edges[i + 1]);
      if (a == null || b == null) continue;
      path
        ..moveTo(a.dx, a.dy)
        ..lineTo(b.dx, b.dy);
    }
    canvas.drawPath(path, line);

    // The spot, and the way the surface faces.
    final spot = view.projectToScreen(ghost.at.position);
    final tip = view.projectToScreen(ghost.at.position + ghost.at.normal * 0.5);
    if (spot != null) {
      canvas.drawCircle(spot, 3, Paint()..color = colour);
      if (tip != null) {
        canvas.drawLine(
          spot,
          tip,
          Paint()
            ..color = colour.withValues(alpha: 0.7)
            ..strokeWidth = 1,
        );
      }
    }
    // Aiming: which way it will face.
    final from = ghost.aimFrom;
    if (from != null) {
      final forward = jge.Vector3.zero();
      ghost.world.transformPointInto(jge.Vector3(0, 0, 1), forward);
      final origin = jge.Vector3.zero();
      ghost.world.transformPointInto(jge.Vector3.zero(), origin);
      final a = view.projectToScreen(from);
      final b = view.projectToScreen(from + (forward - origin).normalized() * 1.5);
      if (a != null && b != null) {
        canvas.drawLine(
          a,
          b,
          Paint()
            ..color = EditorTheme.primary
            ..strokeWidth = 2,
        );
      }
    }
  }

  /// [box]'s twelve edges, two points each.
  static List<jge.Vector3> _boxEdges(jge.Aabb3 box) {
    jge.Vector3 corner(int i) => jge.Vector3(
      i & 1 == 0 ? box.min.x : box.max.x,
      i & 2 == 0 ? box.min.y : box.max.y,
      i & 4 == 0 ? box.min.z : box.max.z,
    );
    return [
      for (final (a, b) in const [
        (0, 1), (2, 3), (4, 5), (6, 7), // along X
        (0, 2), (1, 3), (4, 6), (5, 7), // along Y
        (0, 4), (1, 5), (2, 6), (3, 7), // along Z
      ]) ...[corner(a), corner(b)],
    ];
  }
}

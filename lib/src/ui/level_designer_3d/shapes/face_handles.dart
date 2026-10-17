import 'dart:math' as math;

import 'package:just_game_engine/just_game_engine.dart';

import 'package:just_editor_core/host.dart';

/// How a box's size along one of its own axes is set: [resize] to a new
/// size there, in its own units.
final class FaceAxis {
  const FaceAxis(this.axis, this.resize);

  /// 0 X, 1 Y, 2 Z.
  final int axis;

  /// Sets its size along [axis].
  final void Function(double extent) resize;
}

/// Size handles on the faces of a box in some frame — a shape's, a
/// collider's: drag one and that face follows the pointer while the face
/// opposite stays where it was (the frame's origin moves to keep it), as
/// one undo step; Ctrl snaps the size to the move step.
abstract final class FaceHandles {
  /// The smallest size a face may be pulled down to (metres).
  static const double smallest = 0.01;

  /// The handles of the box [boundsOf] gives in [frame] (its own space to
  /// the world, scale and all), one for each side of each of [axes].
  /// A drag sets the size through the axis and puts the frame's origin
  /// with [moveTo] — given where it should be in the frame as it was —
  /// so the far face keeps its place. [component] and [alsoEdits] are
  /// what is recorded.
  static List<ViewportHandle> build({
    required Matrix4 frame,
    required Aabb3 Function() boundsOf,
    required List<FaceAxis> axes,
    required void Function(Vector3 origin) moveTo,
    required Component component,
    List<Component> alsoEdits = const [],
    required String what,
  }) {
    final box = boundsOf();
    if (box.isEmpty) return const [];
    final centre = Vector3.zero();
    box.centerInto(centre);
    final handles = <ViewportHandle>[];
    for (final face in axes) {
      final a = face.axis;
      // How long a step of its own space is in the world, that way.
      final along = Vector3.zero();
      frame.transformDirectionInto(_unit(a), along);
      final metres = along.length;
      if (metres < 1e-9) continue;
      final direction = along.normalized();
      for (final side in const [-1.0, 1.0]) {
        final local = Vector3.copy(centre);
        _set(local, a, side > 0 ? _get(box.max, a) : _get(box.min, a));
        final at = Vector3.zero();
        frame.transformPointInto(local, at);
        // The face opposite, where the drag began: it stays.
        final keep = side > 0 ? _get(box.min, a) : _get(box.max, a);
        final start = _get(local, a);
        handles.add(
          ViewportHandle(
            position: at,
            component: component,
            alsoEdits: alsoEdits,
            style: ViewportHandleStyle.size,
            tooltip: 'Drag to size ${_axisName(a)} — the face opposite stays; '
                'Ctrl snaps',
            onDrag: (drag) {
              final t = drag.alongLine(at, direction);
              if (t == null) return;
              // Where the face goes, in its own space, and the size that
              // makes: in metres to snap, never through the far face.
              final moved = start + t / metres;
              var size = drag.snapped((moved - keep) * side * metres);
              size = math.max(size, smallest) / metres;
              face.resize(size);
              // Where the far face is now, about the same origin; the
              // origin moves so it is back where it was.
              final after = boundsOf();
              final farNow = side > 0 ? _get(after.min, a) : _get(after.max, a);
              final shift = Vector3.zero();
              _set(shift, a, keep - farNow);
              final origin = Vector3.zero();
              frame.transformPointInto(shift, origin);
              moveTo(origin);
            },
          ),
        );
      }
    }
    return handles;
  }

  static Vector3 _unit(int axis) => switch (axis) {
    0 => Vector3(1, 0, 0),
    1 => Vector3(0, 1, 0),
    _ => Vector3(0, 0, 1),
  };

  static String _axisName(int axis) => switch (axis) {
    0 => 'its width',
    1 => 'its height',
    _ => 'its depth',
  };

  static double _get(Vector3 v, int axis) => switch (axis) {
    0 => v.x,
    1 => v.y,
    _ => v.z,
  };

  static void _set(Vector3 v, int axis, double value) {
    switch (axis) {
      case 0:
        v.x = value;
      case 1:
        v.y = value;
      default:
        v.z = value;
    }
  }
}

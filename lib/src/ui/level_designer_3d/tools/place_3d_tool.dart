import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:just_game_engine/just_game_engine.dart' as jge;
import 'package:just_game_engine/graphics_3d.dart' as g3;
import 'package:just_signals/just_signals.dart';

import 'package:just_editor_core/host.dart';
import '../../level_designer/controls/designer_controls.dart';

/// Makes [prefab]'s entity on [at] — stood on the surface when [align],
/// spun [spin] degrees about its up, sized by [size] — without recording
/// it.
typedef PrefabSpawner =
    jge.Entity Function(
      PrefabDefinition prefab,
      SurfacePoint at, {
      bool align,
      double spin,
      double size,
    });

/// What a click of Place would make now, drawn over the scene before it
/// is made: the prefab's box (and a shape's edges) where it would go.
final class PlacementGhost {
  PlacementGhost({
    required this.prefab,
    required this.at,
    required this.world,
    required this.box,
    this.edges,
    this.aimFrom,
  });

  /// What would be placed.
  final PrefabDefinition prefab;

  /// The surface it would go on.
  final SurfacePoint at;

  /// Where it would be: its transform as a matrix.
  final jge.Matrix4 world;

  /// Its box about its own origin.
  final jge.Aabb3 box;

  /// A 3-D shape's edges in its own space, two points each; null for
  /// anything else, which shows its box.
  final List<jge.Vector3>? edges;

  /// While a press is being dragged to aim it: where it stands.
  final jge.Vector3? aimFrom;
}

/// The 3-D designer's Place: puts the prefab chosen in PREFABS on the
/// surface under the pointer, shown there first.
///
/// - A click places it; a press dragged turns it to face the pointer
///   before it is let go.
/// - Shift+wheel spins it; Align stands it on the surface (a slope, a
///   wall) instead of upright; a random turn and size vary each one.
/// - With Stamp on, a drag lays a trail of them, Spacing apart, as one
///   undo step.
///
/// While snapping it lands on the move step across the surface.
class Place3DTool extends LevelToolHandler {
  /// A tool making entities through [spawn] and recording them through
  /// [record], set up by [state].
  Place3DTool({
    required this.spawn,
    required this.record,
    required this.state,
    PlacementRoll? roll,
  }) : roll = roll ?? PlacementRoll();

  /// Makes one, not yet recorded.
  final PrefabSpawner spawn;

  /// Records what a gesture made, as one undo step, and selects it.
  final void Function(List<jge.Entity> entities, String label) record;

  /// How it places: align, spin, random, stamp.
  final Designer3DState Function() state;

  /// The random part of the next one.
  final PlacementRoll roll;

  /// What a click would make now, for the preview; null when nothing
  /// would.
  final Signal<PlacementGhost?> ghost = Signal(null, debugLabel: 'placeGhost');

  /// How far one notch of the wheel spins it (degrees).
  static const double spinNotch = 15;

  // A press being aimed: where it stands, and how far it is turned.
  SurfacePoint? _press;
  double? _aim;
  // A stamp stroke: what it has made, and where the last one went.
  List<jge.Entity>? _stroke;
  jge.Vector3? _lastStamp;

  @override
  String get id => BuiltInTools.place;

  @override
  String get label => 'Place';

  @override
  IconData get icon => Icons.add_location_alt_outlined;

  @override
  String? get shortcut => 'B';

  @override
  String? get description =>
      'Click to place the prefab chosen in PREFABS on what is under the '
      'pointer; drag to turn it, Shift+wheel to spin it';

  @override
  int get order => 20;

  @override
  String get group => ToolGroups.shapes;

  @override
  jge.Dimensions get dimensions => jge.Dimensions.threeD;

  /// Spun this far, for the next one: the set spin and the roll.
  double get _spin => state().placeSpin.value + roll.turn;

  void _reroll() {
    final s = state();
    roll.roll(turnRange: s.randomTurn.value, sizeRange: s.randomSize.value);
  }

  @override
  void onActivate() => _reroll();

  @override
  void onDeactivate() {
    onCancel();
    ghost.value = null;
  }

  @override
  void onPointerExit() {
    if (_press == null && _stroke == null) ghost.value = null;
  }

  @override
  void onPointerHover(ToolContext context) {
    final space = context.space;
    final prefab = context.controller.activePrefab;
    if (space == null || prefab == null) {
      ghost.value = null;
      return;
    }
    _show(context.world, prefab, space.snappedSurface(), _spin);
  }

  @override
  bool onPointerDown(ToolContext context) {
    final space = context.space;
    if (space == null) return false;
    final prefab = context.controller.activePrefab;
    if (prefab == null) {
      context.controller.setStatus('Choose something to place in PREFABS');
      return true;
    }
    final at = space.snappedSurface();
    if (state().stamp.value) {
      final first = _make(prefab, at, _spin);
      _stroke = [first];
      _lastStamp = jge.Vector3.copy(at.position);
      _reroll();
      _show(context.world, prefab, at, _spin);
      return true;
    }
    _press = at;
    _aim = null;
    _show(context.world, prefab, at, _spin, aiming: true);
    return true;
  }

  @override
  void onPointerMove(ToolContext context) {
    final space = context.space;
    final prefab = context.controller.activePrefab;
    if (space == null || prefab == null) return;
    final stroke = _stroke;
    if (stroke != null) {
      // Not onto what this stroke has just made.
      final at = space.snappedSurface(ignore: stroke.toSet());
      final last = _lastStamp;
      final spacing = math.max(state().stampSpacing.value, 0.05);
      if (last == null || (at.position - last).length >= spacing) {
        stroke.add(_make(prefab, at, _spin));
        _lastStamp = jge.Vector3.copy(at.position);
        _reroll();
      }
      _show(context.world, prefab, at, _spin);
      return;
    }
    final press = _press;
    if (press == null) return;
    final aim = _aimAt(press, space, snapping: space.snapping);
    if (aim != null) _aim = aim;
    _show(context.world, prefab, press, _aim ?? _spin, aiming: true);
  }

  @override
  void onPointerUp(ToolContext context) {
    final prefab = context.controller.activePrefab;
    final stroke = _stroke;
    if (stroke != null) {
      _stroke = null;
      _lastStamp = null;
      if (prefab != null) {
        record(
          stroke,
          stroke.length == 1
              ? 'Place ${prefab.name}'
              : 'Stamp ${stroke.length} × ${prefab.name}',
        );
        context.controller.setStatus(
          'Placed ${stroke.length} × ${prefab.name}',
        );
      }
      return;
    }
    final press = _press;
    _press = null;
    if (press == null || prefab == null) return;
    final placed = _make(prefab, press, _aim ?? _spin);
    _aim = null;
    record([placed], 'Place ${prefab.name}');
    context.controller.setStatus('Placed ${placed.name ?? prefab.name}');
    _reroll();
    final space = context.space;
    if (space != null) {
      _show(context.world, prefab, space.snappedSurface(), _spin);
    }
  }

  @override
  void onCancel() {
    _press = null;
    _aim = null;
    // A stroke cut short keeps what it made, as one step.
    final stroke = _stroke;
    _stroke = null;
    _lastStamp = null;
    if (stroke != null && stroke.isNotEmpty) {
      record(stroke, 'Stamp ${stroke.length}');
    }
  }

  @override
  bool onScroll(ToolContext context, Offset delta) {
    if (!context.isShiftDown) return false;
    // Shift turns a wheel's turn sideways on some systems.
    final turn = delta.dy != 0 ? delta.dy : delta.dx;
    if (turn == 0) return true;
    final spin = state().placeSpin;
    spin.value = ((spin.value + (turn > 0 ? spinNotch : -spinNotch)) % 360 + 360) % 360;
    final prefab = context.controller.activePrefab;
    final space = context.space;
    if (prefab != null && space != null && _press == null) {
      _show(context.world, prefab, space.snappedSurface(), _spin);
    }
    context.controller.setStatus('Spin ${spin.value.round()}°');
    return true;
  }

  @override
  bool onKey(LogicalKeyboardKey key, ToolContext context) {
    if (key == LogicalKeyboardKey.escape && _press != null) {
      _press = null;
      _aim = null;
      ghost.value = null;
      return true;
    }
    return false;
  }

  jge.Entity _make(PrefabDefinition prefab, SurfacePoint at, double spin) =>
      spawn(
        prefab,
        at,
        align: state().alignToSurface.value,
        spin: spin,
        size: roll.size,
      );

  /// The spin that turns what stands at [press] to face where the
  /// pointer meets the surface's plane: its forward (+Z) towards it.
  /// Null while the pointer is still on it.
  double? _aimAt(SurfacePoint press, SpaceContext space, {bool snapping = false}) {
    final align = state().alignToSurface.value;
    final up = align
        ? (jge.Vector3.copy(press.normal)..normalize())
        : jge.Vector3.copy(Placement3D.up);
    final denominator = up.dot(space.ray.direction);
    if (denominator.abs() < 1e-9) return null;
    final t = up.dot(press.position - space.ray.origin) / denominator;
    if (t < 0) return null;
    final towards = space.ray.origin + space.ray.direction * t - press.position;
    towards.sub(up * up.dot(towards));
    if (towards.length < 0.05) return null;
    final stand = align
        ? Placement3D.turnBetween(Placement3D.up, up)
        : jge.Quaternion.identity();
    final forward = jge.Vector3(0, 0, 1);
    stand.rotate(forward);
    var degrees =
        math.atan2(up.cross(forward).dot(towards), forward.dot(towards)) *
        180 /
        math.pi;
    if (snapping) degrees = (degrees / spinNotch).roundToDouble() * spinNotch;
    return degrees;
  }

  void _show(
    jge.World world,
    PrefabDefinition prefab,
    SurfacePoint at,
    double spin, {
    bool aiming = false,
  }) {
    final components = Placement3D.posed(
      prefab,
      at,
      align: state().alignToSurface.value,
      spin: spin,
      size: roll.size,
    );
    final transform = components.whereType<jge.TransformComponent>().first;
    final matrix = jge.Matrix4.identity();
    transform.localToWorldInto(matrix);
    final box = jge.Aabb3();
    RayEntityPicker.localBoundsOf(components, world.context.definitions, box);
    final shape = components.whereType<g3.Primitive3D>().firstOrNull;
    ghost.value = PlacementGhost(
      prefab: prefab,
      at: at,
      world: matrix,
      box: box,
      edges: shape == null ? null : _edgesOf(shape),
      aimFrom: aiming ? jge.Vector3.copy(at.position) : null,
    );
  }

  final Map<Object, List<jge.Vector3>> _edgeCache = {};

  /// [shape]'s edges, once each, for the preview: none for a shape too
  /// detailed to draw them all.
  List<jge.Vector3>? _edgesOf(g3.Primitive3D shape) {
    final key = shape.shapeKey;
    final cached = _edgeCache[key];
    if (cached != null) return cached.isEmpty ? null : cached;
    if (_edgeCache.length > 32) _edgeCache.clear();
    final geometry = shape.buildMesh().geometry;
    final p = geometry.positions, idx = geometry.indices;
    final out = <jge.Vector3>[];
    if (idx.length <= 3 * 1200) {
      final seen = <(int, int)>{};
      jge.Vector3 at(int i) => jge.Vector3(p[i * 3], p[i * 3 + 1], p[i * 3 + 2]);
      // Where two triangles share a flat face, the line between them is
      // left out: a box shows its edges, not its triangles.
      final normals = <(int, int), jge.Vector3>{};
      for (var i = 0; i + 2 < idx.length; i += 3) {
        final a = at(idx[i]), b = at(idx[i + 1]), c = at(idx[i + 2]);
        final n = (b - a).cross(c - a)..normalize();
        for (final (u, v) in [
          (idx[i], idx[i + 1]),
          (idx[i + 1], idx[i + 2]),
          (idx[i + 2], idx[i]),
        ]) {
          final edge = _keyOf(at(u), at(v));
          final other = normals[edge];
          if (other == null) {
            normals[edge] = n;
          } else if (other.dot(n) > 0.999) {
            seen.add(edge);
          }
        }
      }
      final points = <(int, int), (jge.Vector3, jge.Vector3)>{};
      for (var i = 0; i + 2 < idx.length; i += 3) {
        for (final (u, v) in [
          (idx[i], idx[i + 1]),
          (idx[i + 1], idx[i + 2]),
          (idx[i + 2], idx[i]),
        ]) {
          final edge = _keyOf(at(u), at(v));
          if (!seen.contains(edge)) points.putIfAbsent(edge, () => (at(u), at(v)));
        }
      }
      for (final (a, b) in points.values) {
        out
          ..add(a)
          ..add(b);
      }
    }
    _edgeCache[key] = out;
    return out.isEmpty ? null : out;
  }

  // An edge by its two ends' places, whichever way round, so a corner
  // shared by triangles with their own copies of it still matches.
  static (int, int) _keyOf(jge.Vector3 a, jge.Vector3 b) {
    int h(jge.Vector3 v) => Object.hash(
      (v.x * 1e4).round(),
      (v.y * 1e4).round(),
      (v.z * 1e4).round(),
    );
    final x = h(a), y = h(b);
    return x < y ? (x, y) : (y, x);
  }

  @override
  Widget? buildOptions(BuildContext context, ToolOptionsContext options) =>
      PlaceOptions(state: options.scope.designer3D);
}

/// Place's settings, at the left of the status bar: Align, the spin,
/// random turn and size, Stamp and its spacing.
class PlaceOptions extends StatelessWidget {
  const PlaceOptions({super.key, required this.state});

  final Designer3DState state;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      SignalBuilder<bool>(
        signal: state.alignToSurface,
        builder: (context, on, _) => DesignerToggle(
          icon: Icons.texture,
          label: 'Align',
          isOn: on,
          tooltip: 'Stand what is placed on the surface — a slope, a wall — '
              'instead of upright',
          onTap: () => state.alignToSurface.value = !on,
        ),
      ),
      const SizedBox(width: 6),
      SignalBuilder<double>(
        signal: state.placeSpin,
        builder: (context, spin, _) => _Choice<double>(
          tooltip: 'Spin about its up (Shift+wheel)',
          icon: Icons.rotate_right,
          value: spin,
          label: (v) => '${v.round()}°',
          values: const [0, 45, 90, 135, 180, 225, 270, 315],
          onChanged: (v) => state.placeSpin.value = v,
        ),
      ),
      SignalBuilder<double>(
        signal: state.randomTurn,
        builder: (context, turn, _) => _Choice<double>(
          tooltip: 'A random turn for each, up to this far either way',
          icon: Icons.casino_outlined,
          value: turn,
          label: (v) => v == 0 ? 'Turn' : '±${v.round()}°',
          values: const [0, 15, 45, 90, 180],
          onChanged: (v) => state.randomTurn.value = v,
        ),
      ),
      SignalBuilder<double>(
        signal: state.randomSize,
        builder: (context, size, _) => _Choice<double>(
          tooltip: 'A random size for each, up to this much bigger or smaller',
          icon: Icons.open_in_full,
          value: size,
          label: (v) => v == 0 ? 'Size' : '±${(v * 100).round()}%',
          values: const [0, 0.1, 0.2, 0.3, 0.5],
          onChanged: (v) => state.randomSize.value = v,
        ),
      ),
      const SizedBox(width: 6),
      SignalBuilder<bool>(
        signal: state.stamp,
        builder: (context, on, _) => DesignerToggle(
          icon: Icons.brush_outlined,
          label: 'Stamp',
          isOn: on,
          tooltip: 'Drag to lay a trail of them, Spacing apart',
          onTap: () => state.stamp.value = !on,
        ),
      ),
      SignalBuilder<double>(
        signal: state.stampSpacing,
        builder: (context, spacing, _) => _Choice<double>(
          tooltip: 'How far apart stamped ones are',
          icon: Icons.space_bar,
          value: spacing,
          label: (v) => '${_metres(v)} m',
          values: const [0.25, 0.5, 1, 2, 4, 8],
          onChanged: (v) => state.stampSpacing.value = v,
        ),
      ),
    ],
  );

  static String _metres(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString();
}

/// A small picker in the status bar: a value from a few.
class _Choice<T> extends StatelessWidget {
  const _Choice({
    required this.tooltip,
    required this.icon,
    required this.value,
    required this.label,
    required this.values,
    required this.onChanged,
  });

  final String tooltip;
  final IconData icon;
  final T value;
  final String Function(T value) label;
  final List<T> values;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) => PopupMenuButton<T>(
    tooltip: tooltip,
    initialValue: value,
    color: EditorTheme.menuBg,
    position: PopupMenuPosition.over,
    onSelected: onChanged,
    itemBuilder: (context) => [
      for (final v in values)
        PopupMenuItem(
          value: v,
          height: 28,
          child: Text(
            label(v),
            style: TextStyle(
              color: v == value ? EditorTheme.textPrimary : EditorTheme.textSecondary,
              fontSize: 11,
            ),
          ),
        ),
    ],
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: EditorTheme.textSecondary),
          const SizedBox(width: 3),
          Text(
            label(value),
            style: TextStyle(color: EditorTheme.textSecondary, fontSize: 11),
          ),
        ],
      ),
    ),
  );
}

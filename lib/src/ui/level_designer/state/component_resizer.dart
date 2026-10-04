import 'dart:math' as math;

import 'package:just_game_engine/just_game_engine.dart' as jge;

import 'designer_geometry.dart';

/// Changes how big an entity is, one size-bearing component at a time.
///
/// Resizing is not scaling. A transform scale stretches the drawing but not
/// the physics collider, which is built from the body's own shape — so a
/// platform "resized" by scale looks wider than the floor it actually is.
/// This rewrites the real sizes instead, and keeps the visual and the
/// collider in agreement.
abstract final class ComponentResizer {
  /// Smallest extent a resize will produce, so a hard drag past the opposite
  /// edge cannot collapse an entity to nothing.
  static const double minimumExtent = 1;

  /// Scales every size-bearing component of [entity] by ([sx], [sy]) in
  /// world axes.
  ///
  /// An entity turned a quarter turn has its local width along world Y, so
  /// the factors are swapped for it. Returns false when nothing on the entity
  /// could be resized.
  static bool scale(jge.Entity entity, double sx, double sy) {
    final rotation = entity.getComponent<jge.TransformComponent>()?.angle;
    if (rotation != null && _isQuarterTurn(rotation)) {
      (sx, sy) = (sy, sx);
    }
    var resized = false;
    final definitions = DesignerGeometry.definitionsFor(entity);
    for (final component in entity.components.toList()) {
      if (scaleComponent(component, sx, sy, definitions)) resized = true;
    }
    return resized;
  }

  /// Scales one component; see [scale].
  ///
  /// Through the extent on its definition in [definitions] (the engine's
  /// own when null), so what the handles resize is exactly what the marquee
  /// and the gizmo measure.
  static bool scaleComponent(
    jge.Component component,
    double sx,
    double sy, [
    jge.ComponentDefinitionRegistry? definitions,
  ]) {
    final extent = (definitions ?? DesignerGeometry.definitionsFor(null))
        .definitionFor(component)
        ?.extent;
    if (extent == null) return false;
    // Nothing shrinks below [minimumExtent]: clamp the factors, not the
    // result, so every extent gets the guarantee without knowing about it.
    final size = extent.sizeOf(component);
    if (size != null) {
      if (size.width > 0) sx = math.max(sx.abs(), minimumExtent / size.width);
      if (size.height > 0) {
        sy = math.max(sy.abs(), minimumExtent / size.height);
      }
    }
    return extent.scale(component, sx, sy);
  }

  static bool _isQuarterTurn(double radians) {
    final quarters = radians / (math.pi / 2);
    final nearest = quarters.roundToDouble();
    return (quarters - nearest).abs() < 1e-3 && nearest.toInt().isOdd;
  }
}

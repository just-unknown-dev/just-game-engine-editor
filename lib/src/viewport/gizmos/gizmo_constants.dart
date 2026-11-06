import 'dart:math' as math;

import 'package:flutter/painting.dart';

/// The sizes and colours of the move, scale and rotate gizmos, shared by
/// the editor's drawing (`Gizmo2DPainter`, `TransformGizmo`) and hit-testing
/// (`Gizmo2DHitTester`) so what takes a press lines up with what is drawn.
///
/// Sizes are in screen pixels, before the Handle size setting scales them.
abstract final class GizmoConstants {
  // Shared with hit-testing — keep in sync with what's drawn.

  /// From the centre to the tip of the X and Y arrows, and to the scale
  /// gizmo's axis handles.
  static const double arrowLength = 52.0;

  /// The rotate ring's radius, and the all-in-one gizmo's rotate arc's.
  static const double rotRadius = 60.0;

  /// Half the side of a corner scale handle.
  static const double scaleHandle = 7.0;

  /// How far round the all-in-one gizmo's rotate arc runs, in radians: its
  /// dot sits at the arc's end.
  static const double rotSweep = math.pi * 0.75;

  /// From the centre to the all-in-one gizmo's per-axis scale squares, along
  /// each arrow's shaft.
  static const double axisSquareOffset = 30.0;

  // Painter-only.

  /// An arrowhead's length, along the shaft.
  static const double arrowHeadLength = 12.0;

  /// An arrowhead's width at its base.
  static const double arrowHeadWidth = 7.0;

  /// The radius of the rotate knob and the rotate arc's dot.
  static const double dotRadius = 5.0;

  /// Half the side of the move gizmo's centre square, and the radius of the
  /// all-in-one gizmo's centre handle.
  static const double moveHandleRadius = 8.0;

  /// Half the side of an axis scale square.
  static const double axisSquareHalf = 5.0;

  /// The closest grid lines should be drawn on the screen, for a painter of
  /// a module's own. The built-in grids keep their own minimum and do not
  /// read it.
  static const double minGridScreenSpacing = 14.0;

  // Hit-tester-only.

  /// How near an arrow's tip a press has to be to take it.
  static const double arrowTipRadius = 14.0;

  /// How near the rotate arc's dot a press has to be to take it.
  static const double rotDotRadius = 10.0;

  /// How near an axis scale square a press has to be to take it.
  static const double axisSquareHitRadius = 9.0;

  /// How near the centre a press has to be to take the handle that moves on
  /// both axes.
  static const double moveHandleHitRadius = 11.0;

  /// How near an arrow's shaft a press has to be to take it.
  static const double axisHitWidth = 6.0;

  /// How near the rotate ring a press has to be to take it.
  static const double ringHitWidth = 8.0;

  // Colours.

  /// The X axis: its arrow and its scale handles.
  static const Color colX = Color(0xFFE54B4B);

  /// The Y axis: its arrow and its scale handles.
  static const Color colY = Color(0xFF4BCC73);

  /// The rotate ring, arc and knob.
  static const Color colRot = Color(0xFFFFD660);

  /// The corner scale handles.
  static const Color colScale = Color(0xFFCCCCCC);

  /// Selected keys and ranges in the Timeline. The viewport's selection
  /// outline takes the Selection colour setting, this colour until it is
  /// set.
  static const Color colSel = Color(0xFF40E0D0);

  /// The dot on the selected entity's origin.
  static const Color colOrigin = Color(0xFFFFFFFF);

  /// The centre handle that moves on both axes.
  static const Color colMove = Color(0xFF40E0D0);

  /// The selection frame's size, in world units, for an entity none of
  /// whose components says how big it is.
  static const Size defaultSelectionSize = Size(32, 32);
}

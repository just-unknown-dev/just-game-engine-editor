// The Move gizmo's centre square is drawn as big as the "Handle size"
// setting makes it — scaled once, as its grab area is — not that squared.

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_editor_core/host.dart';
import 'package:just_game_engine_editor/src/ui/overlay/gizmo_painter.dart';
import 'package:just_game_engine_editor/src/ui/overlay/transform_gizmo.dart';

/// Keeps the rectangles drawn on it.
class _Recorder implements Canvas {
  final List<Rect> rects = [];

  @override
  void drawRect(Rect rect, Paint paint) => rects.add(rect);

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

void main() {
  tearDown(() => ViewportLook.apply(const OverlayUiSettings.defaults()));

  for (final scale in [0.75, 2.0]) {
    test('at Handle size ${(scale * 100).round()} %, what is drawn is what '
        'can be grabbed', () {
      ViewportLook.apply(
        const OverlayUiSettings.defaults().copyWith(gizmoScale: scale),
      );
      final canvas = _Recorder();
      TransformGizmo.paintMove(canvas, Offset.zero);
      final square = canvas.rects.first;
      expect(
        square.width / 2,
        closeTo(GizmoConstants.moveHandleRadius * scale, 1e-9),
      );
      // Its corner, drawn, can be grabbed.
      final inside = Offset(square.right - 1, square.top + 1);
      expect(
        TransformGizmo.moveHandleAt(inside, Offset.zero),
        GizmoHandle.translateXY,
      );
    });
  }
}

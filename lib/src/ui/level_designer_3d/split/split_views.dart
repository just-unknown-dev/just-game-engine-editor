import 'dart:math' as math;
import 'dart:ui' show Offset, Rect, Size;

import 'package:just_game_engine/just_game_engine.dart' as jge;
import 'package:just_signals/just_signals.dart';

import 'package:just_editor_core/host.dart';
import '../../../core/view/orbit_fly_editor_view.dart';

/// Which of the four views a pane is.
enum PaneKind {
  /// From above, orthographic: a plan.
  top('Top'),

  /// From the front, orthographic: an elevation.
  front('Front'),

  /// From the side, orthographic: an elevation.
  side('Side'),

  /// The editor's own view: perspective, or as it was left.
  perspective('Perspective');

  const PaneKind(this.label);

  /// Its name in the pane's corner.
  final String label;
}

/// One of the four views: where it is on the canvas, what it looks
/// through, and the frame its picture is drawn from.
final class ViewPane {
  ViewPane(this.kind, this.view);

  /// Which view.
  final PaneKind kind;

  /// What it looks through.
  final OrbitFlyEditorView view;

  /// Where it is on the canvas.
  Rect rect = Rect.zero;

  /// Its picture's frame, kept so the 3-D renderer keeps a surface for it.
  final jge.FrameView frame = jge.FrameView();
}

/// The 3-D viewport split four ways, as a modelling program does: top,
/// front and side, orthographic, beside the perspective view the editor
/// had — each one its own camera to pan and zoom, the perspective one the
/// editor's own view.
///
/// Editor-only. While [on], the plugin draws each pane in its quarter and
/// sends the pointer to the one it is over.
class SplitViews {
  /// Splits around [main], the editor's 3-D view.
  SplitViews(this._main);

  final OrbitFlyEditorView Function() _main;

  /// Whether the viewport is split.
  final Signal<bool> on = Signal(false, debugLabel: 'splitViews');

  /// The gap between panes, in pixels.
  static const double gap = 2;

  late final ViewPane _top = ViewPane(
    PaneKind.top,
    _ortho(yaw: 0, pitch: -math.pi / 2),
  );
  late final ViewPane _front = ViewPane(
    PaneKind.front,
    _ortho(yaw: 0, pitch: 0),
  );
  late final ViewPane _side = ViewPane(
    PaneKind.side,
    _ortho(yaw: -math.pi / 2, pitch: 0),
  );
  ViewPane? _perspective;

  static OrbitFlyEditorView _ortho({
    required double yaw,
    required double pitch,
  }) => OrbitFlyEditorView.of(jge.Camera())
    ..yaw = yaw
    ..pitch = pitch
    ..orthographic = true;

  /// The four panes: top, front (the top row), side and perspective.
  List<ViewPane> get panes {
    final main = _main();
    final perspective = _perspective;
    if (perspective == null || !identical(perspective.view, main)) {
      _perspective = ViewPane(PaneKind.perspective, main);
    }
    return [_top, _front, _side, _perspective!];
  }

  /// The pane the pointer last went down in, or is over; null for none.
  ViewPane? active;

  /// Splits or joins the viewport. Split, the orthographic views look at
  /// what the editor's view was looking at, from as far.
  void toggle() {
    final next = !on.value;
    if (next) {
      final main = _main();
      for (final pane in [_top, _front, _side]) {
        pane.view.pivot.setFrom(main.pivot);
        pane.view
          ..distance = main.distance
          ..sync();
      }
    }
    active = null;
    on.value = next;
  }

  /// Lays the panes out over a canvas of [size]: top left, top right,
  /// bottom left, bottom right.
  void layout(Size size) {
    final w = (size.width - gap) / 2, h = (size.height - gap) / 2;
    final list = panes;
    for (var i = 0; i < list.length; i++) {
      final left = i.isOdd ? w + gap : 0.0;
      final top = i >= 2 ? h + gap : 0.0;
      list[i].rect = Rect.fromLTWH(left, top, math.max(1, w), math.max(1, h));
    }
  }

  /// The pane [at] (canvas pixels) is in, if any.
  ViewPane? paneAt(Offset at) {
    for (final pane in panes) {
      if (pane.rect.contains(at)) return pane;
    }
    return null;
  }

  void dispose() => on.dispose();
}

/// What the scope's view becomes while a pane is drawn or handled: that
/// pane's, sized to it.
extension SplitViewScope on EditorScope {
  /// Runs [body] with [pane]'s view as the editor's, sized to the pane.
  T throughPane<T>(ViewPane pane, T Function() body) {
    final before = viewOverride;
    viewOverride = pane.view..viewportSize = pane.rect.size;
    try {
      return body();
    } finally {
      viewOverride = before;
    }
  }
}
